import DesignSystem
import Domain
import Foundation
import Observation

/// 縦比較（検索結果）の ViewModel（FR-CMP、FR-OFF）
@MainActor
@Observable
public final class RouteResultsModel {
    public enum Phase: Equatable {
        case loading
        case loaded
        /// 検索結果 0 件（ROUTE_NOT_FOUND を含む）
        case empty
        case failed(ErrorPresentation)
        /// FEATURE_UNAVAILABLE：対象の条件を外して再検索する導線を出す（FR-CND-02）
        case featureUnavailable(message: String, removable: [RemovableCondition])
    }

    public private(set) var phase: Phase = .loading
    public private(set) var query: RouteSearchQuery
    public var sortOrder: RouteSortOrder
    public var fareKind: FareKind
    public private(set) var result: RouteSearchResult?
    public private(set) var catalog: Catalog = .empty
    /// キャッシュを表示しているときの保存時刻（FR-OFF-02）
    public private(set) var cachedAt: Date?

    private let dependencies: AppDependencies
    /// お気に入りから開いたときに探す経路（FR-DTL-03）
    private let preferred: RouteSignature?
    private var didOpenPreferred = false

    public init(query: RouteSearchQuery, preferred: RouteSignature? = nil, fareKind: FareKind? = nil, dependencies: AppDependencies) {
        self.query = query
        self.preferred = preferred
        self.dependencies = dependencies
        sortOrder = query.sort
        self.fareKind = fareKind ?? dependencies.settings.fareKind
    }

    // MARK: 表示用

    /// 並び替えた列（並び替えはアプリ内で行う、FR-CND-04）
    public var columns: [CompareColumn] {
        guard let routes = result?.routes else { return [] }
        let badges = RouteRanking.badges(for: routes, fareKind: fareKind)
        return RouteRanking.sorted(routes, by: sortOrder, fareKind: fareKind).map {
            CompareColumn(route: $0, badges: badges[$0.id] ?? [], fare: $0.fare.display(preferred: fareKind))
        }
    }

    /// 縦比較の上部に出す注意（FR-CMP-12）
    public var notices: [DataNoticeBanner.Kind] {
        guard let meta = result?.meta else { return [] }
        var list: [DataNoticeBanner.Kind] = []
        if let cachedAt {
            list.append(.cached(asOf: min(cachedAt, meta.asOf)))
        } else if meta.isStale {
            list.append(.stale(asOf: meta.asOf))
        }
        if meta.partialResult { list.append(.partial) }
        return list
    }

    public var attributions: [Attribution] { result?.meta.attributions ?? [] }

    /// 「IC運賃 · 8:04 時点の情報」
    public var infoText: String? {
        guard let meta = result?.meta else { return nil }
        return "\(NKFormat.fareKindLabel(fareKind)) · \(NKFormat.asOf(meta.asOf))"
    }

    public func selection(for routeID: Route.ID) -> RouteSelection? {
        guard let result, let route = result.routes.first(where: { $0.id == routeID }) else { return nil }
        let badges = columns.first { $0.id == routeID }?.badges ?? []
        return RouteSelection(
            route: route, query: query, includes: result.includes, badges: badges,
            attributions: result.meta.attributions, isFromCache: cachedAt != nil,
            asOf: cachedAt.map { min($0, result.meta.asOf) } ?? result.meta.asOf,
            fareKind: fareKind
        )
    }

    // MARK: 読み込み

    public func load() async {
        phase = .loading
        catalog = dependencies.catalog
        if !dependencies.network.isOnline {
            await showCacheOrFail(.offline)
            return
        }
        do {
            let result = try await dependencies.routes.searchRoutes(query)
            self.result = result
            cachedAt = nil
            catalog = dependencies.catalog.merging(result.includes)
            phase = result.routes.isEmpty ? .empty : .loaded
            await dependencies.searchCache.save(result, for: query)
        } catch {
            await handle(AppError.wrap(error))
        }
    }

    /// 経由駅や始発・終電を外して再検索する（FR-CND-02）
    public func searchRemoving(_ condition: RemovableCondition) async {
        query = query.removing(condition)
        await load()
    }

    /// お気に入りから開いたとき、同じ乗り方の経路があればそれを返す（1 回だけ）
    public func takePreferredSelection() -> RouteSelection? {
        guard !didOpenPreferred, let preferred, let routes = result?.routes, phase == .loaded else { return nil }
        didOpenPreferred = true
        guard let match = preferred.findMatch(in: routes) ?? preferred.findStructuralMatch(in: routes) else { return nil }
        return selection(for: match.id)
    }

    private func handle(_ error: AppError) async {
        switch error.apiCode {
        case .routeNotFound?:
            result = nil
            phase = .empty
        case .featureUnavailable?:
            phase = .featureUnavailable(message: error.presentation.message, removable: query.removableConditions)
        case .stationNotFound?:
            // 駅マスタの差分更新を試み、駅の選び直しを促す（api-contract 2.3）
            await dependencies.applyStationUpdates()
            phase = .failed(error.presentation)
        default:
            if error == .offline || error == .network {
                await showCacheOrFail(error)
            } else {
                phase = .failed(error.presentation)
            }
        }
    }

    /// 通信できないときは、キャッシュがあれば取得時刻を明示して出す（FR-OFF-01、FR-OFF-02）
    private func showCacheOrFail(_ error: AppError) async {
        if let cached = await dependencies.searchCache.latest(matching: query) {
            result = cached.result
            cachedAt = cached.savedAt
            catalog = dependencies.catalog.merging(cached.result.includes)
            phase = cached.result.routes.isEmpty ? .empty : .loaded
        } else {
            phase = .failed(error.presentation)
        }
    }
}
