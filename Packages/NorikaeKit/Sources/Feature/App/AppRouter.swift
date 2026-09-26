import Domain
import Foundation
import Observation

/// タブ（frontend.md 4.1）
public enum AppTab: Hashable, Sendable {
    case search
    case status
    case timetable
    case my
}

/// 経路詳細に渡す内容
public struct RouteSelection: Hashable, Sendable {
    public var route: Route
    public var query: RouteSearchQuery
    public var includes: ReferenceIncludes?
    public var badges: [RouteBadge]
    public var attributions: [Attribution]
    /// キャッシュから開いたか（案内開始・1 本前・1 本後の前に再検索する、FR-OFF-06）
    public var isFromCache: Bool
    /// 情報の基準時刻（古い情報・キャッシュの表示に使う）
    public var asOf: Date?
    /// 検索結果で選んでいた運賃種別。`nil` なら設定の既定値
    public var fareKind: FareKind?

    public init(
        route: Route, query: RouteSearchQuery, includes: ReferenceIncludes? = nil, badges: [RouteBadge] = [],
        attributions: [Attribution] = [], isFromCache: Bool = false, asOf: Date? = nil, fareKind: FareKind? = nil
    ) {
        self.route = route
        self.query = query
        self.includes = includes
        self.badges = badges
        self.attributions = attributions
        self.isFromCache = isFromCache
        self.asOf = asOf
        self.fareKind = fareKind
    }
}

/// 停車駅一覧を開くための内容（経路詳細・時刻表から共通で使う）
public struct StopListRequest: Hashable, Sendable {
    public var trainRunId: String
    public var serviceDate: ServiceDate
    public var lineId: String
    /// 強調する区間（乗車駅・降車駅）
    public var fromStationId: String?
    public var toStationId: String?

    public init(trainRunId: String, serviceDate: ServiceDate, lineId: String, fromStationId: String? = nil, toStationId: String? = nil) {
        self.trainRunId = trainRunId
        self.serviceDate = serviceDate
        self.lineId = lineId
        self.fromStationId = fromStationId
        self.toStationId = toStationId
    }
}

/// 経路検索タブの画面遷移
public enum SearchDestination: Hashable, Sendable {
    /// `fareKind` は検索条件で選んだ運賃種別。`nil` なら設定の既定値
    case results(RouteSearchQuery, preferred: RouteSignature? = nil, fareKind: FareKind? = nil)
    case detail(RouteSelection)
    case stopList(StopListRequest)
    case stationMap(stationId: String)
}

/// 運行情報タブの画面遷移
public enum StatusDestination: Hashable, Sendable {
    case detail(lineId: String)
}

/// 時刻表タブの画面遷移
public enum TimetableDestination: Hashable, Sendable {
    case directions(stationId: String)
    case timetable(FavoriteTimetable)
    case stopList(StopListRequest)
}

/// マイタブの画面遷移
public enum MyDestination: Hashable, Sendable {
    case favorites
    case history
    case myLines
    case settings
    case attributions
}

/// タブと各タブの画面遷移をまとめて持つ（マイ画面のお気に入りから経路検索タブを開く、など）
@MainActor
@Observable
public final class AppRouter {
    public var selectedTab: AppTab = .search
    public var searchPath: [SearchDestination] = []
    public var statusPath: [StatusDestination] = []
    public var timetablePath: [TimetableDestination] = []
    public var myPath: [MyDestination] = []
    /// 経路検索フォームに入れる駅（駅のお気に入りから開いたとき）
    public var pendingOriginStationId: String?

    public init() {}

    /// 経路検索タブで検索結果を開く
    public func openSearch(_ query: RouteSearchQuery, preferred: RouteSignature? = nil) {
        selectedTab = .search
        searchPath = [.results(query, preferred: preferred)]
    }

    /// 時刻表タブで時刻表を開く
    public func openTimetable(_ timetable: FavoriteTimetable) {
        selectedTab = .timetable
        timetablePath = [.timetable(timetable)]
    }

    /// 駅を出発駅にして経路検索タブを開く
    public func startSearch(from stationId: String) {
        pendingOriginStationId = stationId
        selectedTab = .search
        searchPath = []
    }
}
