import Foundation

// Repository のプロトコル（api-contract 6 章）。
// 本物の API 実装とモックは NorikaeData モジュールにある。

public protocol RouteRepository: Sendable {
    func searchRoutes(_ query: RouteSearchQuery) async throws -> RouteSearchResult
    func adjacentRoute(context: RouteContext, direction: AdjacentDirection) async throws -> AdjacentRouteResult
    func trainRun(id: TrainRun.ID, serviceDate: ServiceDate) async throws -> TrainRunResult
}

public protocol TimetableRepository: Sendable {
    func directions(stationID: Station.ID) async throws -> [LineDirection]
    /// `directionID` は `LineDirection.directionId`（路線の中での方面の ID）
    func timetable(stationID: Station.ID, lineID: Line.ID, directionID: String, dayType: DayType) async throws -> TimetableResult
}

public protocol OperationStatusRepository: Sendable {
    func statuses(region: Region) async throws -> OperationStatusList
    func status(lineID: Line.ID) async throws -> OperationStatusDetail
}

public protocol StationRepository: Sendable {
    /// 同梱の駅マスタを端末内で検索する（オフラインで動く）
    func search(text: String, preferredRegion: Region) async throws -> [Station]
    func nearest(to coordinate: Coordinate, limit: Int) async throws -> [Station]
    /// API-08 で差分を取得して適用する。無効になった駅 ID と移行先を返す（FR-SRC-09）
    func applyUpdates() async throws -> StationMigration
    /// 駅・路線・事業者・種別の参照表
    func catalog() async -> Catalog
}

public protocol LiveActivityRegistrationRepository: Sendable {
    func register(_ registration: LiveActivityRegistration) async throws
    func unregister(activityID: String) async throws
}

public protocol CapabilityRepository: Sendable {
    /// キャッシュがあればそれを返し、古ければ API から取り直す。取れなければ直前のキャッシュ、それもなければ全機能を利用可能とみなす
    func capabilities() async -> CapabilitySnapshot
    /// 強制的に取り直す
    func refresh() async throws -> CapabilitySnapshot
}

public protocol AttributionRepository: Sendable {
    /// 取得できない場合は直前のキャッシュを返す（FR-MY-08）
    func attributions() async throws -> [Attribution]
}

/// Live Activity のプッシュトークン登録（API-09 の入力、api-contract 5.2）
public struct LiveActivityRegistration: Codable, Sendable, Hashable {
    /// 乗車区間ごとの監視対象（`PUT /v1/live-activities/{activityId}` の `legs`）
    public struct MonitoredLeg: Codable, Sendable, Hashable {
        public struct Endpoint: Codable, Sendable, Hashable {
            public var stationId: String
            public var scheduledTime: Date
        }

        public var lineId: String
        /// ある場合のみ（ない場合はキーごと出さない）
        public var trainRunId: String?
        public var serviceDate: ServiceDate
        public var from: Endpoint
        public var to: Endpoint

        public init(leg: TrainLeg) {
            lineId = leg.lineId
            trainRunId = leg.trainRunId
            serviceDate = leg.from.serviceDate
            from = Endpoint(stationId: leg.from.stationId, scheduledTime: leg.from.scheduledTime)
            to = Endpoint(stationId: leg.to.stationId, scheduledTime: leg.to.scheduledTime)
        }
    }

    public var activityId: String
    public var pushToken: String
    public var routeContext: RouteContext
    public var legs: [MonitoredLeg]
    public var expiresAt: Date

    /// 到着予定時刻に足す余裕（上限は 1 時間、api-contract 5.2）
    public static let expiryMargin: TimeInterval = 60 * 60

    public init(activityId: String, pushToken: String, route: Route) {
        self.activityId = activityId
        self.pushToken = pushToken
        self.routeContext = route.routeContext
        self.legs = route.trainLegs.map(MonitoredLeg.init(leg:))
        self.expiresAt = route.arrivalTime.addingTimeInterval(Self.expiryMargin)
    }
}

/// お気に入り・履歴・マイ路線の保存先（SwiftData ＋ CloudKit、frontend.md 8.1）
///
/// 画面から直接使うため MainActor で扱う。変更は `revision` で通知する。
@MainActor
public protocol UserDataStore: AnyObject {
    /// 変更のたびに増える。画面はこれを読んで再描画する
    var revision: Int { get }

    func favorites() -> [FavoriteEntry]
    @discardableResult func addFavorite(_ item: FavoriteItem) -> FavoriteEntry
    func removeFavorite(id: FavoriteEntry.ID)
    func moveFavorites(from source: IndexSet, to destination: Int)
    func favorite(matching item: FavoriteItem) -> FavoriteEntry?

    func history() -> [HistoryEntry]
    func addHistory(_ query: RouteSearchQuery)
    func removeHistory(id: HistoryEntry.ID)
    func clearHistory()

    func myLines() -> [MyLineEntry]
    func addMyLine(lineId: String)
    func removeMyLine(id: MyLineEntry.ID)

    /// 駅・路線の統合で ID を置き換える（FR-SRC-09）
    func migrateIDs(stations: [String: String], lines: [String: String])

    /// 同期などで外から変わった可能性があるときに読み直す
    func reload()
}

extension Array {
    /// SwiftUI の `move(fromOffsets:toOffset:)` と同じ並べ替え（Domain は SwiftUI に依存しないため自前で持つ）
    public mutating func nkMove(fromOffsets source: IndexSet, toOffset destination: Int) {
        let moving = source.sorted().map { self[$0] }
        let removedBefore = source.filter { $0 < destination }.count
        for index in source.sorted(by: >) { remove(at: index) }
        insert(contentsOf: moving, at: Swift.max(0, Swift.min(destination - removedBefore, count)))
    }
}
