import Domain
import Foundation
import Observation
import SwiftData

// MARK: - SwiftData のモデル
//
// CloudKit で同期するため、全項目に既定値を持たせ、一意制約は付けない。

@Model
final class FavoriteRecord {
    var id: UUID = UUID()
    var kind: String = ""
    var payload: Data = Data()
    var sortIndex: Int = 0
    var createdAt: Date = Date()

    init(id: UUID, kind: String, payload: Data, sortIndex: Int, createdAt: Date) {
        self.id = id
        self.kind = kind
        self.payload = payload
        self.sortIndex = sortIndex
        self.createdAt = createdAt
    }
}

@Model
final class SearchHistoryRecord {
    var id: UUID = UUID()
    var payload: Data = Data()
    var searchedAt: Date = Date()

    init(id: UUID, payload: Data, searchedAt: Date) {
        self.id = id
        self.payload = payload
        self.searchedAt = searchedAt
    }
}

@Model
final class MyLineRecord {
    var id: UUID = UUID()
    var lineId: String = ""
    var createdAt: Date = Date()

    init(id: UUID, lineId: String, createdAt: Date) {
        self.id = id
        self.lineId = lineId
        self.createdAt = createdAt
    }
}

/// SwiftData のコンテナ
public enum UserDataContainer {
    /// - Parameter cloudSync: iCloud 同期（FR-MY-06）。切り替えはアプリの再起動後に反映する
    @MainActor
    public static func make(cloudSync: Bool, inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema([FavoriteRecord.self, SearchHistoryRecord.self, MyLineRecord.self])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: cloudSync && !inMemory ? .automatic : .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}

// MARK: - SwiftData 版

/// SwiftData ＋ CloudKit のお気に入り・履歴・マイ路線（frontend.md 8.1）
@MainActor
@Observable
public final class SwiftDataUserDataStore: UserDataStore {
    public private(set) var revision = 0
    /// mainContext はコンテナを保持しない。コンテナが解放されると、コンテキストを使った時点でクラッシュするので持っておく
    private let container: ModelContainer
    private let context: ModelContext
    private let encoder = NorikaeJSON.makeEncoder()
    private let decoder = NorikaeJSON.makeDecoder()

    /// 履歴の上限
    public static let historyLimit = 50

    public init(container: ModelContainer) {
        self.container = container
        context = container.mainContext
    }

    public func reload() {
        revision += 1
    }

    // MARK: お気に入り

    public func favorites() -> [FavoriteEntry] {
        _ = revision
        return fetchFavorites().compactMap { record in
            guard let item = try? decoder.decode(FavoriteItem.self, from: record.payload) else { return nil }
            return FavoriteEntry(id: record.id, item: item, createdAt: record.createdAt)
        }
    }

    @discardableResult
    public func addFavorite(_ item: FavoriteItem) -> FavoriteEntry {
        if let existing = favorite(matching: item) { return existing }
        let entry = FavoriteEntry(item: item)
        let nextIndex = (fetchFavorites().map(\.sortIndex).max() ?? -1) + 1
        if let payload = try? encoder.encode(item) {
            context.insert(FavoriteRecord(id: entry.id, kind: item.kind.rawValue, payload: payload, sortIndex: nextIndex, createdAt: entry.createdAt))
            commit()
        }
        return entry
    }

    public func removeFavorite(id: FavoriteEntry.ID) {
        for record in fetchFavorites() where record.id == id { context.delete(record) }
        commit()
    }

    public func moveFavorites(from source: IndexSet, to destination: Int) {
        var records = fetchFavorites()
        records.nkMove(fromOffsets: source, toOffset: destination)
        for (index, record) in records.enumerated() { record.sortIndex = index }
        commit()
    }

    public func favorite(matching item: FavoriteItem) -> FavoriteEntry? {
        favorites().first { FavoriteMatching.isSame($0.item, item) }
    }

    // MARK: 履歴

    public func history() -> [HistoryEntry] {
        _ = revision
        return fetchHistory().compactMap { record in
            guard let query = try? decoder.decode(RouteSearchQuery.self, from: record.payload) else { return nil }
            return HistoryEntry(id: record.id, query: query, searchedAt: record.searchedAt)
        }
    }

    public func addHistory(_ query: RouteSearchQuery) {
        // 同じ駅・条件の古い履歴は置き換える
        for record in fetchHistory() {
            if let old = try? decoder.decode(RouteSearchQuery.self, from: record.payload), FavoriteMatching.isSameTrip(old, query) {
                context.delete(record)
            }
        }
        if let payload = try? encoder.encode(query) {
            context.insert(SearchHistoryRecord(id: UUID(), payload: payload, searchedAt: Date()))
        }
        for record in fetchHistory().dropFirst(Self.historyLimit) { context.delete(record) }
        commit()
    }

    public func removeHistory(id: HistoryEntry.ID) {
        for record in fetchHistory() where record.id == id { context.delete(record) }
        commit()
    }

    public func clearHistory() {
        for record in fetchHistory() { context.delete(record) }
        commit()
    }

    // MARK: マイ路線

    public func myLines() -> [MyLineEntry] {
        _ = revision
        return fetchMyLines().map { MyLineEntry(id: $0.id, lineId: $0.lineId, createdAt: $0.createdAt) }
    }

    public func addMyLine(lineId: String) {
        guard !fetchMyLines().contains(where: { $0.lineId == lineId }) else { return }
        context.insert(MyLineRecord(id: UUID(), lineId: lineId, createdAt: Date()))
        commit()
    }

    public func removeMyLine(id: MyLineEntry.ID) {
        for record in fetchMyLines() where record.id == id { context.delete(record) }
        commit()
    }

    // MARK: 移行

    public func migrateIDs(stations: [String: String], lines: [String: String]) {
        if !stations.isEmpty {
            for record in fetchFavorites() {
                guard let item = try? decoder.decode(FavoriteItem.self, from: record.payload),
                      let payload = try? encoder.encode(item.replacingStationIDs(stations)) else { continue }
                record.payload = payload
            }
            for record in fetchHistory() {
                guard let query = try? decoder.decode(RouteSearchQuery.self, from: record.payload),
                      let payload = try? encoder.encode(query.replacingStationIDs(stations)) else { continue }
                record.payload = payload
            }
        }
        for record in fetchMyLines() {
            if let replacement = lines[record.lineId] { record.lineId = replacement }
        }
        commit()
    }

    // MARK: 内部

    private func fetchFavorites() -> [FavoriteRecord] {
        (try? context.fetch(FetchDescriptor<FavoriteRecord>(sortBy: [SortDescriptor(\.sortIndex), SortDescriptor(\.createdAt)]))) ?? []
    }

    private func fetchHistory() -> [SearchHistoryRecord] {
        (try? context.fetch(FetchDescriptor<SearchHistoryRecord>(sortBy: [SortDescriptor(\.searchedAt, order: .reverse)]))) ?? []
    }

    private func fetchMyLines() -> [MyLineRecord] {
        (try? context.fetch(FetchDescriptor<MyLineRecord>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
    }

    private func commit() {
        try? context.save()
        revision += 1
    }
}

// MARK: - メモリ版（テスト・プレビュー）

@MainActor
@Observable
public final class InMemoryUserDataStore: UserDataStore {
    public private(set) var revision = 0
    private var favoriteEntries: [FavoriteEntry]
    private var historyEntries: [HistoryEntry]
    private var myLineEntries: [MyLineEntry]

    public init(favorites: [FavoriteEntry] = [], history: [HistoryEntry] = [], myLines: [MyLineEntry] = []) {
        favoriteEntries = favorites
        historyEntries = history
        myLineEntries = myLines
    }

    public func reload() { revision += 1 }

    public func favorites() -> [FavoriteEntry] { favoriteEntries }

    @discardableResult
    public func addFavorite(_ item: FavoriteItem) -> FavoriteEntry {
        if let existing = favorite(matching: item) { return existing }
        let entry = FavoriteEntry(item: item)
        favoriteEntries.append(entry)
        revision += 1
        return entry
    }

    public func removeFavorite(id: FavoriteEntry.ID) {
        favoriteEntries.removeAll { $0.id == id }
        revision += 1
    }

    public func moveFavorites(from source: IndexSet, to destination: Int) {
        favoriteEntries.nkMove(fromOffsets: source, toOffset: destination)
        revision += 1
    }

    public func favorite(matching item: FavoriteItem) -> FavoriteEntry? {
        favoriteEntries.first { FavoriteMatching.isSame($0.item, item) }
    }

    public func history() -> [HistoryEntry] { historyEntries }

    public func addHistory(_ query: RouteSearchQuery) {
        historyEntries.removeAll { FavoriteMatching.isSameTrip($0.query, query) }
        historyEntries.insert(HistoryEntry(query: query), at: 0)
        historyEntries = Array(historyEntries.prefix(SwiftDataUserDataStore.historyLimit))
        revision += 1
    }

    public func removeHistory(id: HistoryEntry.ID) {
        historyEntries.removeAll { $0.id == id }
        revision += 1
    }

    public func clearHistory() {
        historyEntries.removeAll()
        revision += 1
    }

    public func myLines() -> [MyLineEntry] { myLineEntries }

    public func addMyLine(lineId: String) {
        guard !myLineEntries.contains(where: { $0.lineId == lineId }) else { return }
        myLineEntries.append(MyLineEntry(lineId: lineId))
        revision += 1
    }

    public func removeMyLine(id: MyLineEntry.ID) {
        myLineEntries.removeAll { $0.id == id }
        revision += 1
    }

    public func migrateIDs(stations: [String: String], lines: [String: String]) {
        favoriteEntries = favoriteEntries.map { var e = $0; e.item = e.item.replacingStationIDs(stations); return e }
        historyEntries = historyEntries.map { var e = $0; e.query = e.query.replacingStationIDs(stations); return e }
        myLineEntries = myLineEntries.map { var e = $0; e.lineId = lines[e.lineId] ?? e.lineId; return e }
        revision += 1
    }
}

/// お気に入り・履歴の同一判定
enum FavoriteMatching {
    /// 日時と並び替えを除いて同じ移動か
    static func isSameTrip(_ lhs: RouteSearchQuery, _ rhs: RouteSearchQuery) -> Bool {
        lhs.fromStationId == rhs.fromStationId && lhs.toStationId == rhs.toStationId
            && lhs.viaStationIds == rhs.viaStationIds && lhs.searchType == rhs.searchType
            && lhs.useShinkansen == rhs.useShinkansen && lhs.usePaidExpress == rhs.usePaidExpress
    }

    static func isSame(_ lhs: FavoriteItem, _ rhs: FavoriteItem) -> Bool {
        switch (lhs, rhs) {
        case let (.route(l), .route(r)):
            isSameTrip(l.query, r.query) && l.signature.structure == r.signature.structure
        case let (.station(l), .station(r)):
            l == r
        case let (.timetable(l), .timetable(r)):
            l.stationId == r.stationId && l.lineId == r.lineId && l.directionId == r.directionId
        default:
            false
        }
    }
}
