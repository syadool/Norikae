#if canImport(ActivityKit) && os(iOS)
@preconcurrency import ActivityKit
#endif
import DesignSystem
import Domain
import Foundation
import LiveGuidance
import NorikaeData
import Observation

/// 案内（Live Activity）の開始・更新・終了（frontend.md 6 章、7.1）
///
/// - 同時に案内できる経路は 1 つ（FR-LA-02）
/// - 通常の進行は端末だけで動かし、区間の切り替えは予定時刻で行う（FR-LA-10）
/// - プッシュトークンを取得して登録し、更新されたら同じ `activityId` で登録し直す。失敗しても案内は続け、通信が戻ったら再試行する（FR-LA-11、FR-LA-14）
/// - 「1本後に変更」「案内終了」は `LiveActivityIntent` から呼ばれる（FR-LA-20〜22）
@MainActor
@Observable
public final class GuidanceController: GuidanceIntentHandling {
    public enum StartError: Error, Equatable {
        /// 設定で Live Activity が許可されていない
        case activitiesDisabled
    }

    /// 案内中の経路
    public private(set) var session: GuidanceSession?

    private unowned let dependencies: AppDependencies
    private let sessionStore: any GuidanceSessionStoring
    @ObservationIgnored private var currentState: LiveRouteState?
    @ObservationIgnored private var observationTasks: [Task<Void, Never>] = []
    @ObservationIgnored private var transitionTask: Task<Void, Never>?

    init(dependencies: AppDependencies, sessionStore: any GuidanceSessionStoring) {
        self.dependencies = dependencies
        self.sessionStore = sessionStore
    }

    public var isActive: Bool { session != nil }

    // MARK: - 開始

    /// 案内を開始する（FR-DTL-02、FR-LA-01）
    ///
    /// キャッシュから開いた経路は、保存した検索条件で再検索してから開始する（FR-OFF-06）。
    /// - Returns: 実際に案内する経路（取り直した場合は新しい `routeContext` を持つ）
    @discardableResult
    public func start(selection: RouteSelection) async throws -> Route {
        var route = selection.route
        if selection.isFromCache {
            guard dependencies.network.isOnline else { throw AppError.offline }
            route = try await RouteContextRecovery(repository: dependencies.routes).refreshedRoute(route, query: selection.query).route
        }
        // 通知の権限は、案内開始を初めて使うときに要求する（frontend.md 7.2）
        _ = await dependencies.reminders.requestAuthorizationIfNeeded()
        let catalog = dependencies.catalog.merging(selection.includes)
        try await startActivity(route: route, query: selection.query, catalog: catalog)
        await rescheduleReminder(promptForLocation: true)
        return route
    }

    /// 新しい Live Activity を先に作ってから、それ以外を終了する。
    /// 作れなかったとき（バックグラウンドからの開始など）は、今の案内をそのまま残す
    private func startActivity(route: Route, query: RouteSearchQuery, catalog: Catalog) async throws {
        let summary = GuidanceSummary(
            route: route, catalog: catalog, capabilities: dependencies.capabilities.snapshot,
            fallbackStationName: String(localized: "駅名不明", bundle: .module),
            fallbackTrainTypeName: ""
        )
        let state = LiveRouteState(route: route, now: Date())
        let activityID = try requestActivity(summary: summary, state: state)
        await endAllActivities(except: activityID)
        session = GuidanceSession(activityId: activityID, route: route, query: query, summary: summary, startedAt: Date())
        currentState = state
        persist()
        observeActivity(id: activityID)
        scheduleTransitions(for: state)
    }

    private func requestActivity(summary: GuidanceSummary, state: LiveRouteState) throws -> String {
        #if canImport(ActivityKit) && os(iOS)
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { throw StartError.activitiesDisabled }
        let attributes = NavigationActivityAttributes(summary: summary)
        let content = ActivityContent(state: state, staleDate: nil)
        do {
            return try Activity.request(attributes: attributes, content: content, pushType: .token).id
        } catch {
            // プッシュが使えない環境でも、時刻表どおりの表示で動かす（FR-LA-14）
            return try Activity.request(attributes: attributes, content: content, pushType: nil).id
        }
        #else
        return UUID().uuidString
        #endif
    }

    // MARK: - 終了

    /// 「案内終了」（FR-LA-04、FR-LA-22）
    public func endGuidance(activityID: String) async {
        await end(activityID: activityID)
    }

    /// 案内を終了する。`activityID` が `nil` なら今の案内
    public func end(activityID: String? = nil) async {
        let target = activityID ?? session?.activityId
        #if canImport(ActivityKit) && os(iOS)
        for activity in Activity<NavigationActivityAttributes>.activities where target == nil || activity.id == target {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        #endif
        await cleanUp(activityID: target)
    }

    private func endAllActivities(except keptID: String) async {
        #if canImport(ActivityKit) && os(iOS)
        for activity in Activity<NavigationActivityAttributes>.activities where activity.id != keptID {
            let id = activity.id
            await activity.end(nil, dismissalPolicy: .immediate)
            if id != session?.activityId {
                try? await dependencies.liveActivityRegistration.unregister(activityID: id)
            }
        }
        #endif
        if let current = session?.activityId {
            await cleanUp(activityID: current)
        }
    }

    /// 登録の解除・リマインドの取り消し・保存の削除（FR-LA-11）
    private func cleanUp(activityID: String?) async {
        observationTasks.forEach { $0.cancel() }
        observationTasks.removeAll()
        transitionTask?.cancel()
        transitionTask = nil
        await dependencies.reminders.cancel()
        let wasRegistered = session?.registeredPushToken != nil
        if let activityID, wasRegistered || session?.activityId == activityID {
            try? await dependencies.liveActivityRegistration.unregister(activityID: activityID)
        }
        if activityID == nil || session?.activityId == activityID {
            session = nil
            currentState = nil
            persist()
        }
    }

    // MARK: - 1本後に変更（FR-LA-20、FR-LA-21）

    public func shiftToLaterTrain(activityID: String) async {
        guard let session, session.activityId == activityID else { return }
        // オフラインでは経路を変えない。推測した経路は出さない（FR-LA-21）
        guard dependencies.network.isOnline else {
            await setNotice(.offlineChangeFailed)
            return
        }
        do {
            let recovery = RouteContextRecovery(repository: dependencies.routes)
            let result = try await recovery.adjacentRoute(from: session.route, query: session.query, direction: .next)
            let change = AdjacentRouteChange(original: session.route, adjacent: result.route)
            if change.structureChanged {
                // 構成が変わるときは ActivityAttributes を変えられないため、終了して開始し直す（api-contract 5.3）
                do {
                    try await startActivity(route: result.route, query: session.query, catalog: dependencies.catalog.merging(result.includes))
                    await rescheduleReminder(promptForLocation: false)
                } catch {
                    // バックグラウンドから開始できない場合は、アプリを開くよう促す（frontend.md 14 章 #6）
                    await setNotice(.reopenAppToChange)
                }
            } else {
                await replaceRoute(with: result.route)
            }
        } catch {
            await setNotice(AppError.wrap(error) == .offline ? .offlineChangeFailed : .changeFailed)
        }
    }

    /// 構成が同じ経路に差し替える。同じ activityId のまま、新しい routeContext で登録し直す
    private func replaceRoute(with route: Route) async {
        guard var session else { return }
        let state = LiveRouteState(route: route, now: Date())
        session.route = route
        session.registeredPushToken = nil
        self.session = session
        currentState = state
        persist()
        await updateActivity(id: session.activityId, state: state)
        scheduleTransitions(for: state)
        await registerIfNeeded()
        await rescheduleReminder(promptForLocation: false)
    }

    private func setNotice(_ notice: LiveRouteState.LocalNotice) async {
        guard let session else { return }
        var state = latestState() ?? LiveRouteState(route: session.route, now: Date())
        state.localNotice = notice
        currentState = state
        await updateActivity(id: session.activityId, state: state)
    }

    // MARK: - 前面・起動

    /// 起動時に、残っている Live Activity と保存した案内をつなぎ直す
    public func restore() async {
        guard let saved = sessionStore.load() else { return }
        #if canImport(ActivityKit) && os(iOS)
        guard let activity = Self.activity(id: saved.activityId) else {
            session = saved
            await cleanUp(activityID: saved.activityId)
            return
        }
        session = saved
        currentState = activity.content.state
        observeActivity(id: saved.activityId)
        scheduleTransitions(for: activity.content.state)
        #else
        session = saved
        #endif
        await endIfArrived()
    }

    /// アプリを開いたとき：到着済みなら終了、登録の再試行、リマインドの再計算（FR-NTF-04、FR-LA-14）
    public func appDidBecomeActive() async {
        guard session != nil else { return }
        await endIfArrived()
        await registerIfNeeded()
        await rescheduleReminder(promptForLocation: false)
    }

    /// 通信が戻ったとき
    public func networkDidBecomeAvailable() async {
        await registerIfNeeded()
    }

    // MARK: - プッシュトークンの登録（API-09）

    private func didReceivePushToken(_ token: String, activityID: String) async {
        guard var session, session.activityId == activityID else { return }
        session.pendingPushToken = token
        self.session = session
        persist()
        await registerIfNeeded()
    }

    private func registerIfNeeded() async {
        guard let session, session.needsRegistration, let token = session.pendingPushToken, dependencies.network.isOnline else { return }
        let registration = dependencies.liveActivityRegistration
        let activityID = session.activityId
        do {
            // 期限切れ・不一致なら、保存した検索条件で取り直してから登録し直す（api-contract 4.2、2.3）
            let result = try await RouteContextRecovery(repository: dependencies.routes).perform(
                route: session.route, query: session.query, refreshOn: [.routeContextExpired, .routeContextMismatch]
            ) { route in
                try await registration.register(LiveActivityRegistration(activityId: activityID, pushToken: token, route: route))
            }
            guard var latest = self.session, latest.activityId == activityID else { return }
            latest.route = result.route
            latest.registeredPushToken = token
            self.session = latest
            persist()
        } catch {
            // 失敗しても案内は時刻表どおりの表示で続ける（FR-LA-14）
        }
    }

    // MARK: - 表示の更新

    private func observeActivity(id: String) {
        observationTasks.forEach { $0.cancel() }
        observationTasks.removeAll()
        #if canImport(ActivityKit) && os(iOS)
        // Activity を Task をまたいで持ち回らないよう、それぞれの Task の中で探す
        observationTasks.append(Task { [weak self] in
            guard let activity = Self.activity(id: id) else { return }
            for await tokenData in activity.pushTokenUpdates {
                let token = tokenData.map { String(format: "%02x", $0) }.joined()
                await self?.didReceivePushToken(token, activityID: id)
            }
        })
        observationTasks.append(Task { [weak self] in
            guard let activity = Self.activity(id: id) else { return }
            for await content in activity.contentUpdates {
                await self?.contentDidChange(content.state)
            }
        })
        observationTasks.append(Task { [weak self] in
            guard let activity = Self.activity(id: id) else { return }
            for await state in activity.activityStateUpdates where state == .dismissed || state == .ended {
                await self?.activityDidEnd(id: id)
            }
        })
        #endif
    }

    #if canImport(ActivityKit) && os(iOS)
    private static func activity(id: String) -> Activity<NavigationActivityAttributes>? {
        Activity<NavigationActivityAttributes>.activities.first { $0.id == id }
    }
    #endif

    /// プッシュで内容が変わったとき（FR-LA-12）
    private func contentDidChange(_ state: LiveRouteState) async {
        guard state != currentState else { return }
        currentState = state
        scheduleTransitions(for: state)
        await rescheduleReminder(promptForLocation: false)
    }

    private func activityDidEnd(id: String) async {
        guard session?.activityId == id else { return }
        await cleanUp(activityID: id)
    }

    /// 予定時刻で区間を切り替える。アプリが動いている間は、発車・到着の時刻に表示を描き直す（FR-LA-10）
    private func scheduleTransitions(for state: LiveRouteState) {
        transitionTask?.cancel()
        let dates = GuidanceProgress.transitionDates(for: state, after: Date())
        transitionTask = Task { [weak self] in
            for date in dates {
                let interval = date.timeIntervalSinceNow
                if interval > 0 { try? await Task.sleep(for: .seconds(interval)) }
                if Task.isCancelled { return }
                await self?.redraw()
            }
            if Task.isCancelled { return }
            await self?.endIfArrived()
        }
    }

    private func redraw() async {
        guard let session, let state = latestState() else { return }
        await updateActivity(id: session.activityId, state: state)
    }

    /// 到着予定時刻（遅延分を含む）を過ぎたら自動で終了する（FR-LA-03）
    private func endIfArrived(now: Date = Date()) async {
        guard let session else { return }
        let state = latestState() ?? LiveRouteState(route: session.route, now: now)
        guard let arrival = GuidanceProgress.endDate(for: state), arrival <= now else { return }
        #if canImport(ActivityKit) && os(iOS)
        for activity in Activity<NavigationActivityAttributes>.activities where activity.id == session.activityId {
            await activity.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: .after(now.addingTimeInterval(5 * 60)))
        }
        #endif
        await cleanUp(activityID: session.activityId)
    }

    private func updateActivity(id: String, state: LiveRouteState) async {
        #if canImport(ActivityKit) && os(iOS)
        for activity in Activity<NavigationActivityAttributes>.activities where activity.id == id {
            await activity.update(ActivityContent(state: state, staleDate: activity.content.staleDate))
        }
        #endif
    }

    /// 端末に届いている最新の状態（プッシュで更新されていればそれ）
    private func latestState() -> LiveRouteState? {
        #if canImport(ActivityKit) && os(iOS)
        if let id = session?.activityId, let activity = Self.activity(id: id) {
            return activity.content.state
        }
        #endif
        return currentState
    }

    // MARK: - 出発リマインド（FR-NTF-02〜05）

    /// 「発車時刻 − 歩く時間 − 余裕の時間」に予約する。位置情報が取れなければ「発車時刻 − 余裕の時間」
    private func rescheduleReminder(promptForLocation: Bool) async {
        guard let session else { return }
        let state = latestState() ?? LiveRouteState(route: session.route, now: Date())
        guard let first = state.legs.first else { return }

        var walking: TimeInterval?
        if let originID = session.route.originStationId, let origin = dependencies.catalog.station(originID),
           promptForLocation || dependencies.location.authorization == .authorized,
           let here = try? await dependencies.location.currentLocation() {
            walking = await dependencies.walkingTime.walkingDuration(from: here, to: origin.coordinate)
        }
        let settings = dependencies.settings
        guard let fireDate = ReminderCalculator.fireDate(
            departure: first.departureDate, walkingDuration: walking, walkingSpeed: settings.walkingSpeed,
            margin: settings.reminderMargin, now: Date()
        ) else {
            await dependencies.reminders.cancel()
            return
        }
        let leg = session.summary.legs.first
        let title = String(localized: "そろそろ出発の時間です", bundle: .module)
        let body = String(
            localized: "\(session.summary.originName) \(NKFormat.time(first.departureDate))発 \(leg?.lineName ?? "") \(leg?.destinationName ?? "")",
            bundle: .module
        )
        await dependencies.reminders.schedule(at: fireDate, title: title, body: body)
    }

    private func persist() {
        sessionStore.save(session)
    }
}
