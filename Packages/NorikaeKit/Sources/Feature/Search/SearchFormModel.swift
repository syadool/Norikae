import Domain
import Foundation
import Observation

/// 経路検索フォーム（FR-SRC、FR-CND）
@MainActor
@Observable
public final class SearchFormModel {
    public var from: Station?
    public var to: Station?
    public var via: [Station] = []
    public var searchType: SearchType = .departure
    /// 「今」で検索するか（出発のとき）
    public var usesCurrentTime = true
    public var dateTime = Date()
    public var useShinkansen: Bool
    public var usePaidExpress: Bool
    public var fareKind: FareKind
    public var sortOrder: RouteSortOrder

    public init(settings: AppSettings) {
        // 各条件の初期値は設定に従う（FR-CND-06）
        useShinkansen = settings.useShinkansen
        usePaidExpress = settings.usePaidExpress
        fareKind = settings.fareKind
        sortOrder = settings.sortOrder
    }

    public var canSearch: Bool {
        guard let from, let to else { return false }
        return from.id != to.id
    }

    /// 経由駅・始発終電の提供状況を判定する地域（出発駅の地域）
    public func region(default fallback: Region) -> Region {
        from?.region ?? fallback
    }

    public var canAddVia: Bool { via.count < RouteSearchQuery.maxViaStations }

    /// 出発駅と到着駅を入れ替える（FR-SRC-07）
    public func swap() {
        (from, to) = (to, from)
        via.reverse()
    }

    public func makeQuery(now: Date = Date()) -> RouteSearchQuery? {
        guard let from, let to, canSearch else { return nil }
        let date = searchType == .departure && usesCurrentTime ? now : dateTime
        return RouteSearchQuery(
            fromStationId: from.id, toStationId: to.id, viaStationIds: via.map(\.id), dateTime: date,
            searchType: searchType, useShinkansen: useShinkansen, usePaidExpress: usePaidExpress,
            sort: sortOrder, maxResults: RouteSearchQuery.defaultMaxResults
        )
    }

    /// 履歴・お気に入りの条件をフォームに入れる（FR-SRC-06）
    public func apply(_ query: RouteSearchQuery, catalog: Catalog) {
        from = catalog.station(query.fromStationId)
        to = catalog.station(query.toStationId)
        via = query.viaStationIds.compactMap(catalog.station)
        searchType = query.searchType
        useShinkansen = query.useShinkansen
        usePaidExpress = query.usePaidExpress
        usesCurrentTime = query.searchType == .departure
        dateTime = query.searchType == .departure ? Date() : query.refreshed(now: Date()).dateTime
    }

    /// 対応していない条件を外す（提供状況が変わったとき、FR-CND-01・02）
    public func removeUnsupported(capabilities: CapabilitySnapshot, region: Region) {
        if !capabilities.isSupported(.viaStations, region: region) { via = [] }
        if searchType.isFirstOrLast, !capabilities.isSupported(.firstLastTrain, region: region) { searchType = .departure }
    }

    /// 条件の要約（「IC運賃 · 新幹線なし · 特急なし」）
    public var conditionsSummary: String {
        [
            fareKind == .ic ? String(localized: "IC運賃", bundle: .module) : String(localized: "切符運賃", bundle: .module),
            useShinkansen ? String(localized: "新幹線あり", bundle: .module) : String(localized: "新幹線なし", bundle: .module),
            usePaidExpress ? String(localized: "特急あり", bundle: .module) : String(localized: "特急なし", bundle: .module),
        ].joined(separator: " · ")
    }
}
