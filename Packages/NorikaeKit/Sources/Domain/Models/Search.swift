import Foundation

/// 検索の種類（api-contract 4.1）
public enum SearchType: String, Codable, Sendable, Hashable, CaseIterable {
    case departure
    case arrival
    case firstTrain
    case lastTrain

    /// 始発・終電か（提供状況 `firstLastTrain` の対象）
    public var isFirstOrLast: Bool { self == .firstTrain || self == .lastTrain }
}

/// 並び替え（FR-CND-04）
public enum RouteSortOrder: String, Codable, Sendable, Hashable, CaseIterable {
    case fastest
    case fewestTransfers
    case cheapest
}

/// 経路検索の条件（API-01 の入力）。お気に入り・履歴・キャッシュにも、この形で保存する
public struct RouteSearchQuery: Codable, Sendable, Hashable {
    public var fromStationId: String
    public var toStationId: String
    public var viaStationIds: [String]
    public var dateTime: Date
    public var searchType: SearchType
    public var useShinkansen: Bool
    public var usePaidExpress: Bool
    public var sort: RouteSortOrder
    public var maxResults: Int?

    public static let maxViaStations = 3
    public static let defaultMaxResults = 10

    public init(
        fromStationId: String, toStationId: String, viaStationIds: [String] = [], dateTime: Date,
        searchType: SearchType = .departure, useShinkansen: Bool = false, usePaidExpress: Bool = false,
        sort: RouteSortOrder = .fastest, maxResults: Int? = RouteSearchQuery.defaultMaxResults
    ) {
        self.fromStationId = fromStationId
        self.toStationId = toStationId
        self.viaStationIds = Array(viaStationIds.prefix(Self.maxViaStations))
        self.dateTime = dateTime
        self.searchType = searchType
        self.useShinkansen = useShinkansen
        self.usePaidExpress = usePaidExpress
        self.sort = sort
        self.maxResults = maxResults
    }

    /// 出発駅と到着駅を入れ替えた条件（FR-SRC-07）
    public func swapped() -> RouteSearchQuery {
        var copy = self
        copy.fromStationId = toStationId
        copy.toStationId = fromStationId
        copy.viaStationIds = viaStationIds.reversed()
        return copy
    }

    /// 保存した条件を、今の時刻で開き直すときの条件（お気に入り経路を開くとき、FR-DTL-03）
    public func refreshed(now: Date) -> RouteSearchQuery {
        var copy = self
        switch searchType {
        case .departure:
            copy.dateTime = now
        case .arrival:
            // 同じ時刻の、今日（過ぎていれば明日）
            let calendar = JapanCalendar.calendar
            let time = calendar.dateComponents([.hour, .minute], from: dateTime)
            var candidate = calendar.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: 0, of: now) ?? now
            if candidate < now, let tomorrow = calendar.date(byAdding: .day, value: 1, to: candidate) {
                candidate = tomorrow
            }
            copy.dateTime = candidate
        case .firstTrain, .lastTrain:
            copy.dateTime = now
        }
        return copy
    }

    /// 経由駅や始発・終電を外した条件（FEATURE_UNAVAILABLE からの再検索、FR-CND-02）
    public func removing(_ condition: RemovableCondition) -> RouteSearchQuery {
        var copy = self
        switch condition {
        case .viaStations:
            copy.viaStationIds = []
        case .firstLastTrain:
            copy.searchType = .departure
        }
        return copy
    }

    /// この条件で外せる、対応していない可能性のある条件
    public var removableConditions: [RemovableCondition] {
        var result: [RemovableCondition] = []
        if !viaStationIds.isEmpty { result.append(.viaStations) }
        if searchType.isFirstOrLast { result.append(.firstLastTrain) }
        return result
    }

    /// 駅 ID の置き換え（駅マスタの統合、FR-SRC-09）
    public func replacingStationIDs(_ replacements: [String: String]) -> RouteSearchQuery {
        var copy = self
        copy.fromStationId = replacements[fromStationId] ?? fromStationId
        copy.toStationId = replacements[toStationId] ?? toStationId
        copy.viaStationIds = viaStationIds.map { replacements[$0] ?? $0 }
        return copy
    }

    public var allStationIds: [String] { [fromStationId] + viaStationIds + [toStationId] }
}

/// 対応していない場合に外して再検索できる条件
public enum RemovableCondition: String, Sendable, Hashable, CaseIterable {
    case viaStations
    case firstLastTrain
}

/// 経路検索の結果（API-01 の出力）
public struct RouteSearchResult: Codable, Sendable, Hashable {
    public var meta: ResponseMeta
    public var routes: [Route]
    public var includes: ReferenceIncludes?

    public init(meta: ResponseMeta, routes: [Route], includes: ReferenceIncludes? = nil) {
        self.meta = meta
        self.routes = routes
        self.includes = includes
    }
}

/// 1 本前・1 本後の結果（API-02 の出力）
public struct AdjacentRouteResult: Sendable, Hashable {
    public var meta: ResponseMeta?
    public var route: Route
    public var includes: ReferenceIncludes?

    public init(meta: ResponseMeta? = nil, route: Route, includes: ReferenceIncludes? = nil) {
        self.meta = meta
        self.route = route
        self.includes = includes
    }
}
