import Domain
import Foundation

/// キャッシュした検索結果（FR-OFF-01）
public struct CachedSearch: Codable, Sendable, Hashable {
    public var query: RouteSearchQuery
    public var result: RouteSearchResult
    public var savedAt: Date

    public init(query: RouteSearchQuery, result: RouteSearchResult, savedAt: Date) {
        self.query = query
        self.result = result
        self.savedAt = savedAt
    }
}

/// 検索結果のキャッシュ（直近 20 件、端末内のみ）
///
/// `routeContext` は期限切れを前提に扱い、案内開始・1 本前・1 本後の前には保存した検索条件で再検索する（FR-OFF-06）。
public protocol SearchResultCaching: Sendable {
    func save(_ result: RouteSearchResult, for query: RouteSearchQuery) async
    /// 同じ駅・条件の、最も新しいキャッシュ（日時は問わない）
    func latest(matching query: RouteSearchQuery) async -> CachedSearch?
}

public actor SearchResultCache: SearchResultCaching {
    public static let capacity = 20
    private let store: JSONFileStore
    private var entries: [CachedSearch]?

    public init(store: JSONFileStore = .caches("search-results")) {
        self.store = store
    }

    public func save(_ result: RouteSearchResult, for query: RouteSearchQuery) async {
        var list = await loadEntries()
        list.removeAll { Self.key(for: $0.query) == Self.key(for: query) }
        list.insert(CachedSearch(query: query, result: result, savedAt: Date()), at: 0)
        list = Array(list.prefix(Self.capacity))
        entries = list
        await store.save(list, key: "entries")
    }

    public func latest(matching query: RouteSearchQuery) async -> CachedSearch? {
        let key = Self.key(for: query)
        return await loadEntries().first { Self.key(for: $0.query) == key }
    }

    private func loadEntries() async -> [CachedSearch] {
        if let entries { return entries }
        let loaded = await store.load([CachedSearch].self, key: "entries") ?? []
        entries = loaded
        return loaded
    }

    /// 日時と並び替えを除いた条件
    static func key(for query: RouteSearchQuery) -> String {
        [
            query.fromStationId, query.toStationId, query.viaStationIds.joined(separator: ","),
            query.searchType.rawValue, String(query.useShinkansen), String(query.usePaidExpress),
        ].joined(separator: "|")
    }
}

/// 閲覧した時刻表のキャッシュ（FR-OFF-01）
public protocol TimetableCaching: Sendable {
    func save(_ result: TimetableResult) async
    func load(stationID: String, lineID: String, directionID: String, dayType: DayType) async -> (result: TimetableResult, savedAt: Date)?
}

public actor TimetableCache: TimetableCaching {
    private struct Entry: Codable, Sendable {
        var result: TimetableResult
        var savedAt: Date
    }

    private let store: JSONFileStore

    public init(store: JSONFileStore = .caches("timetables")) {
        self.store = store
    }

    public func save(_ result: TimetableResult) async {
        let t = result.timetable
        await store.save(Entry(result: result, savedAt: Date()), key: Self.key(t.stationId, t.lineId, t.directionId, t.dayType))
    }

    public func load(stationID: String, lineID: String, directionID: String, dayType: DayType) async -> (result: TimetableResult, savedAt: Date)? {
        guard let entry = await store.load(Entry.self, key: Self.key(stationID, lineID, directionID, dayType)) else { return nil }
        return (entry.result, entry.savedAt)
    }

    private static func key(_ station: String, _ line: String, _ direction: String, _ dayType: DayType) -> String {
        StableHash.of([station, line, direction, dayType.rawValue])
    }
}

/// インメモリのキャッシュ（テスト・プレビュー用）
public actor InMemorySearchResultCache: SearchResultCaching {
    private var entries: [CachedSearch] = []

    public init() {}

    public func save(_ result: RouteSearchResult, for query: RouteSearchQuery) async {
        entries.removeAll { SearchResultCache.key(for: $0.query) == SearchResultCache.key(for: query) }
        entries.insert(CachedSearch(query: query, result: result, savedAt: Date()), at: 0)
    }

    public func latest(matching query: RouteSearchQuery) async -> CachedSearch? {
        entries.first { SearchResultCache.key(for: $0.query) == SearchResultCache.key(for: query) }
    }
}

public actor InMemoryTimetableCache: TimetableCaching {
    private var entries: [String: (TimetableResult, Date)] = [:]

    public init() {}

    public func save(_ result: TimetableResult) async {
        let t = result.timetable
        entries["\(t.stationId)|\(t.lineId)|\(t.directionId)|\(t.dayType.rawValue)"] = (result, Date())
    }

    public func load(stationID: String, lineID: String, directionID: String, dayType: DayType) async -> (result: TimetableResult, savedAt: Date)? {
        entries["\(stationID)|\(lineID)|\(directionID)|\(dayType.rawValue)"].map { ($0.0, $0.1) }
    }
}
