import Domain
import Foundation
import NorikaeData
import Observation
import SwiftData

/// 画面が使う依存関係の入れ物。本物の API とモックを差し替えられる（frontend.md 9.1）
@MainActor
@Observable
public final class AppDependencies {
    public let routes: any RouteRepository
    public let timetables: any TimetableRepository
    public let statuses: any OperationStatusRepository
    public let stations: any StationRepository
    public let liveActivityRegistration: any LiveActivityRegistrationRepository
    public let attributions: any AttributionRepository
    public let searchCache: any SearchResultCaching
    public let timetableCache: any TimetableCaching
    public let userData: any UserDataStore
    public let settings: AppSettings
    public let capabilities: CapabilityStore
    public let network: NetworkMonitor
    public let location: any LocationProviding
    public let walkingTime: any WalkingTimeProviding
    public let reminders: any ReminderScheduling
    public let router: AppRouter
    /// 案内（Live Activity）。自分自身を参照するため、初期化の最後に作る
    @ObservationIgnored public private(set) var guidance: GuidanceController! = nil
    /// 駅マスタ（参照表）。起動時に読み込む
    public private(set) var catalog: Catalog = .empty
    /// 駅の統合で移行先のなかった駅 ID（「この駅は利用できません」の表示に使う）
    public private(set) var removedStationIDs: Set<String> = []

    public init(
        routes: any RouteRepository, timetables: any TimetableRepository, statuses: any OperationStatusRepository,
        stations: any StationRepository, liveActivityRegistration: any LiveActivityRegistrationRepository,
        capabilities: any CapabilityRepository, attributions: any AttributionRepository,
        searchCache: any SearchResultCaching, timetableCache: any TimetableCaching, userData: any UserDataStore,
        settings: AppSettings, network: NetworkMonitor, location: any LocationProviding,
        walkingTime: any WalkingTimeProviding, reminders: any ReminderScheduling,
        guidanceSessionStore: any GuidanceSessionStoring
    ) {
        self.routes = routes
        self.timetables = timetables
        self.statuses = statuses
        self.stations = stations
        self.liveActivityRegistration = liveActivityRegistration
        self.attributions = attributions
        self.searchCache = searchCache
        self.timetableCache = timetableCache
        self.userData = userData
        self.settings = settings
        self.capabilities = CapabilityStore(repository: capabilities)
        self.network = network
        self.location = location
        self.walkingTime = walkingTime
        self.reminders = reminders
        self.router = AppRouter()
        self.guidance = GuidanceController(dependencies: self, sessionStore: guidanceSessionStore)
    }

    /// 起動時の準備：駅マスタ・提供状況の読み込み、駅マスタの差分の適用（FR-SRC-08、FR-CAP-01）
    public func bootstrap() async {
        catalog = await stations.catalog()
        await capabilities.load()
        await applyStationUpdates()
        await guidance.restore()
    }

    /// 前面に戻ったとき
    public func sceneDidBecomeActive() async {
        userData.reload()
        await capabilities.refreshIfNeeded()
        await guidance.appDidBecomeActive()
    }

    /// 駅マスタの差分を適用し、保存済みの ID を移行する（FR-SRC-09）
    public func applyStationUpdates() async {
        guard let migration = try? await stations.applyUpdates() else { return }
        if !migration.isEmpty {
            userData.migrateIDs(stations: migration.replacements, lines: migration.lineReplacements)
            removedStationIDs.formUnion(migration.removedWithoutReplacement)
        }
        // 駅の追加・名称変更だけの差分でも移行情報は空になるため、画面用マスタは毎回読み直す
        catalog = await stations.catalog()
    }

    /// 駅が利用できるか（駅マスタにある）
    public func isStationAvailable(_ id: String) -> Bool {
        catalog.station(id) != nil && !removedStationIDs.contains(id)
    }
}

// MARK: - 組み立て

extension AppDependencies {
    /// 起動引数と Info.plist から組み立てる
    ///
    /// - `-UseMockData`：モックを使う（UI テスト）。`-MockScenario <名前>` で場面を選ぶ
    /// - Info.plist の `NorikaeAPIBaseURL` が空なら、バックエンドの準備ができるまでモックで動かす
    /// - `-ResetUserData`：UI テスト用に、保存したデータと設定を消して始める
    public static func makeFromLaunchEnvironment(bundle: Bundle = .main) -> AppDependencies {
        let arguments = ProcessInfo.processInfo.arguments
        let defaults = UserDefaults.standard
        if arguments.contains("-ResetUserData") {
            for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("settings.") {
                defaults.removeObject(forKey: key)
            }
        }
        let settings = AppSettings(defaults: defaults)
        if let regionIndex = arguments.firstIndex(of: "-Region"), arguments.indices.contains(regionIndex + 1) {
            settings.region = Region(rawValue: arguments[regionIndex + 1])
        }

        let userData: any UserDataStore
        if arguments.contains("-ResetUserData") {
            userData = InMemoryUserDataStore()
        } else if let container = try? UserDataContainer.make(cloudSync: settings.iCloudSyncAtLaunch) {
            userData = SwiftDataUserDataStore(container: container)
        } else if let container = try? UserDataContainer.make(cloudSync: false) {
            userData = SwiftDataUserDataStore(container: container)
        } else {
            userData = InMemoryUserDataStore()
        }

        let baseURLString = (bundle.object(forInfoDictionaryKey: "NorikaeAPIBaseURL") as? String) ?? ""
        let useMock = arguments.contains("-UseMockData") || baseURLString.isEmpty
        if useMock {
            let scenario = arguments.firstIndex(of: "-MockScenario")
                .flatMap { arguments.indices.contains($0 + 1) ? MockScenario(rawValue: arguments[$0 + 1]) : nil } ?? .standard
            return mock(scenario: scenario, settings: settings, userData: userData)
        }

        guard let baseURL = URL(string: baseURLString) else {
            return mock(scenario: .standard, settings: settings, userData: userData)
        }
        let version = (bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0"
        let client = APIClient(configuration: APIConfiguration(baseURL: baseURL, appVersion: version), tokenStore: KeychainTokenStore())
        return AppDependencies(
            routes: RemoteRouteRepository(client: client),
            timetables: RemoteTimetableRepository(client: client),
            statuses: RemoteOperationStatusRepository(client: client),
            stations: LocalStationRepository(source: RemoteMasterDataSource(client: client)),
            liveActivityRegistration: RemoteLiveActivityRegistrationRepository(client: client),
            capabilities: CachingCapabilityRepository(source: RemoteCapabilitySource(client: client)),
            attributions: CachingAttributionRepository(source: RemoteAttributionSource(client: client)),
            searchCache: SearchResultCache(), timetableCache: TimetableCache(), userData: userData,
            settings: settings, network: NetworkMonitor(), location: LocationService(),
            walkingTime: MapKitWalkingTimeService(), reminders: NotificationReminderScheduler(),
            guidanceSessionStore: AppGroupGuidanceSessionStore()
        )
    }

    /// モックで組み立てる（開発・UI テスト・プレビュー）
    public static func mock(
        scenario: MockScenario = .standard,
        settings: AppSettings? = nil,
        userData: (any UserDataStore)? = nil,
        latency: Duration = .milliseconds(400),
        network: NetworkMonitor? = nil,
        location: (any LocationProviding)? = nil,
        reminders: (any ReminderScheduling)? = nil,
        guidanceSessionStore: (any GuidanceSessionStoring)? = nil
    ) -> AppDependencies {
        let set = MockRepositorySet(scenario: scenario, latency: latency)
        return AppDependencies(
            routes: set.routes, timetables: set.timetables, statuses: set.statuses, stations: set.stations,
            liveActivityRegistration: set.liveActivityRegistration, capabilities: set.capabilities, attributions: set.attributions,
            searchCache: InMemorySearchResultCache(), timetableCache: InMemoryTimetableCache(),
            userData: userData ?? InMemoryUserDataStore(),
            settings: settings ?? AppSettings(defaults: UserDefaults(suiteName: "norikae.mock") ?? .standard),
            network: network ?? NetworkMonitor(),
            location: location ?? LocationService(),
            walkingTime: MapKitWalkingTimeService(),
            reminders: reminders ?? NotificationReminderScheduler(),
            guidanceSessionStore: guidanceSessionStore ?? AppGroupGuidanceSessionStore()
        )
    }
}
