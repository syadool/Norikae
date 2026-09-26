import DesignSystem
import Domain
import Foundation
import Observation

/// 経路詳細の ViewModel（FR-DTL）
@MainActor
@Observable
public final class RouteDetailModel {
    public enum ActionState: Equatable {
        case idle
        case running
        case failed(ErrorPresentation)
    }

    public private(set) var selection: RouteSelection
    public private(set) var catalog: Catalog
    public private(set) var adjacentState: ActionState = .idle
    /// 1 本前・1 本後に切り替えたときに変わった点（FR-DTL-06）
    public private(set) var adjacentChange: AdjacentRouteChange?
    public private(set) var guidanceState: ActionState = .idle

    private let dependencies: AppDependencies

    public init(selection: RouteSelection, dependencies: AppDependencies) {
        self.selection = selection
        self.dependencies = dependencies
        catalog = dependencies.catalog.merging(selection.includes)
    }

    public var route: Route { selection.route }
    public var capabilities: CapabilitySnapshot { dependencies.capabilities.snapshot }
    public var fareKind: FareKind { selection.fareKind ?? dependencies.settings.fareKind }
    public var fareText: String { NKFormat.fare(route.fare.display(preferred: fareKind)) }

    /// 案内中の経路か
    public var isGuiding: Bool {
        guard let session = dependencies.guidance.session else { return false }
        return RouteSignature(route: session.route) == RouteSignature(route: route)
    }

    // MARK: お気に入り（FR-DTL-03）

    private var favoriteItem: FavoriteItem {
        .route(FavoriteRoute(query: selection.query, signature: RouteSignature(route: route)))
    }

    public var isFavorite: Bool {
        dependencies.userData.favorite(matching: favoriteItem) != nil
    }

    public func toggleFavorite() {
        if let entry = dependencies.userData.favorite(matching: favoriteItem) {
            dependencies.userData.removeFavorite(id: entry.id)
        } else {
            dependencies.userData.addFavorite(favoriteItem)
        }
    }

    // MARK: 1 本前・1 本後（FR-DTL-06）

    /// 経路全体を探し直す。`routeContext` が期限切れなら、保存した検索条件で取り直してから行う（api-contract 4.2）
    public func loadAdjacent(_ direction: AdjacentDirection) async {
        guard dependencies.network.isOnline else {
            adjacentState = .failed(.offlineAction)
            return
        }
        adjacentState = .running
        do {
            let original = route
            let result = try await RouteContextRecovery(repository: dependencies.routes)
                .adjacentRoute(from: original, query: selection.query, direction: direction)
            adjacentChange = AdjacentRouteChange(original: original, adjacent: result.route)
            selection.route = result.route
            selection.badges = []
            selection.isFromCache = false
            selection.asOf = result.meta?.asOf ?? Date()
            if let includes = result.includes {
                catalog = catalog.merging(includes)
                selection.includes = includes
            }
            if let meta = result.meta, !meta.attributions.isEmpty { selection.attributions = meta.attributions }
            adjacentState = .idle
        } catch {
            adjacentState = .failed(AppError.wrap(error).presentation)
        }
    }

    /// 変わった点の説明
    public var adjacentChangeText: String? {
        guard let change = adjacentChange else { return nil }
        var parts: [String] = []
        if change.structureChanged {
            parts.append(String(localized: "乗換駅や乗り継ぐ列車が変わりました", bundle: .module))
        }
        if change.arrivalDeltaMinutes != 0 {
            let delta = change.arrivalDeltaMinutes
            parts.append(delta > 0
                ? String(localized: "到着が\(delta)分遅くなります", bundle: .module)
                : String(localized: "到着が\(-delta)分早くなります", bundle: .module))
        }
        return parts.isEmpty ? nil : parts.joined(separator: "。")
    }

    // MARK: 案内開始（FR-DTL-02）

    public func startGuidance() async {
        if selection.isFromCache, !dependencies.network.isOnline {
            guidanceState = .failed(.offlineAction)
            return
        }
        guidanceState = .running
        do {
            let started = try await dependencies.guidance.start(selection: selection)
            selection.route = started
            selection.isFromCache = false
            guidanceState = .idle
        } catch GuidanceController.StartError.activitiesDisabled {
            guidanceState = .failed(ErrorPresentation(
                message: String(localized: "設定で「ライブアクティビティ」が許可されていません", bundle: .module), retryable: false
            ))
        } catch {
            guidanceState = .failed(AppError.wrap(error).presentation)
        }
    }

    public func endGuidance() async {
        await dependencies.guidance.end()
    }

    // MARK: 共有（FR-DTL-04）

    /// 共有するテキスト
    public var shareText: String {
        var lines: [String] = []
        lines.append(QueryText.title(selection.query, catalog: catalog))
        lines.append(String(
            localized: "\(NKFormat.date(route.departureTime)) \(NKFormat.time(route.departureTime))発 → \(NKFormat.time(route.arrivalTime))着（\(NKFormat.duration(minutes: route.durationMinutes))・\(NKFormat.transfers(route.transferCount))・\(fareText)）",
            bundle: .module
        ))
        for leg in route.trainLegs {
            let line = catalog.line(leg.lineId)?.name ?? leg.lineId
            let type = catalog.trainType(leg.trainTypeId)?.name ?? ""
            let from = catalog.station(leg.from.stationId)?.name ?? ""
            let to = catalog.station(leg.to.stationId)?.name ?? ""
            lines.append("\(NKFormat.time(leg.from.scheduledTime)) \(from) → \(NKFormat.time(leg.to.scheduledTime)) \(to)  \(line) \(type) \(leg.destinationName)")
        }
        return lines.joined(separator: "\n")
    }
}
