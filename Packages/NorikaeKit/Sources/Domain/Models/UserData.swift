import Foundation

/// お気に入り経路（FR-DTL-03）。`routeContext` ではなく検索条件と経路の特定情報を保存する（api-contract 4.2）
public struct FavoriteRoute: Codable, Sendable, Hashable {
    public var query: RouteSearchQuery
    public var signature: RouteSignature

    public init(query: RouteSearchQuery, signature: RouteSignature) {
        self.query = query
        self.signature = signature
    }
}

/// お気に入りの時刻表（FR-TT-07）
public struct FavoriteTimetable: Codable, Sendable, Hashable {
    public var stationId: String
    public var lineId: String
    public var directionId: String
    public var directionName: String

    public init(stationId: String, lineId: String, directionId: String, directionName: String) {
        self.stationId = stationId
        self.lineId = lineId
        self.directionId = directionId
        self.directionName = directionName
    }
}

/// お気に入りの中身（経路・駅・時刻表、FR-MY-01）
public enum FavoriteItem: Codable, Sendable, Hashable {
    case route(FavoriteRoute)
    case station(stationId: String)
    case timetable(FavoriteTimetable)

    public var kind: Kind {
        switch self {
        case .route: .route
        case .station: .station
        case .timetable: .timetable
        }
    }

    public enum Kind: String, Codable, Sendable, CaseIterable {
        case route, station, timetable
    }

    /// 参照している駅 ID
    public var stationIds: [String] {
        switch self {
        case .route(let route): route.query.allStationIds
        case .station(let id): [id]
        case .timetable(let timetable): [timetable.stationId]
        }
    }

    public func replacingStationIDs(_ replacements: [String: String]) -> FavoriteItem {
        switch self {
        case .route(var route):
            route.query = route.query.replacingStationIDs(replacements)
            route.signature = route.signature.replacingStationIDs(replacements)
            return .route(route)
        case .station(let id):
            return .station(stationId: replacements[id] ?? id)
        case .timetable(var timetable):
            timetable.stationId = replacements[timetable.stationId] ?? timetable.stationId
            return .timetable(timetable)
        }
    }
}

public struct FavoriteEntry: Identifiable, Sendable, Hashable {
    public var id: UUID
    public var item: FavoriteItem
    public var createdAt: Date

    public init(id: UUID = UUID(), item: FavoriteItem, createdAt: Date = Date()) {
        self.id = id
        self.item = item
        self.createdAt = createdAt
    }
}

/// 検索履歴（FR-MY-02）
public struct HistoryEntry: Identifiable, Sendable, Hashable {
    public var id: UUID
    public var query: RouteSearchQuery
    public var searchedAt: Date

    public init(id: UUID = UUID(), query: RouteSearchQuery, searchedAt: Date = Date()) {
        self.id = id
        self.query = query
        self.searchedAt = searchedAt
    }
}

/// マイ路線（FR-MY-03）
public struct MyLineEntry: Identifiable, Sendable, Hashable {
    public var id: UUID
    public var lineId: String
    public var createdAt: Date

    public init(id: UUID = UUID(), lineId: String, createdAt: Date = Date()) {
        self.id = id
        self.lineId = lineId
        self.createdAt = createdAt
    }
}

/// リマインドの余裕の時間（FR-MY-05）
public enum ReminderMargin: Int, Codable, Sendable, CaseIterable {
    case zero = 0
    case three = 3
    case five = 5
}

/// 歩く速さ（FR-MY-05）
///
/// 補正値は未決（frontend.md 14 章 #4）。MapKit の徒歩時間に掛ける仮の値
public enum WalkingSpeed: String, Codable, Sendable, CaseIterable {
    case slow
    case normal
    case fast

    public var durationFactor: Double {
        switch self {
        case .slow: 1.25
        case .normal: 1.0
        case .fast: 0.85
        }
    }
}
