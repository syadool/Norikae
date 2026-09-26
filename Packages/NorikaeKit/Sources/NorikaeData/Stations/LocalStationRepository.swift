import Domain
import Foundation

/// 駅マスタの差分の取得元（API-08）
public protocol MasterDataSource: Sendable {
    func changes(sinceVersion: Int) async throws -> MasterDataChanges
}

/// 駅マスタのスナップショット（同梱ファイル・差分適用後の保存ファイルの形）
///
/// `GET /v1/master-data/snapshot` の `data` と同じ形。同梱ファイルは、バックエンドの月次スナップショットから作る（FR-SRC-08）。
/// いま同梱している StationMaster.json は開発用のサンプル（version 0）。
public struct StationMasterSnapshot: Codable, Sendable {
    public var version: Int
    public var stations: [Station]
    public var lines: [Line]
    public var operators: [Operator]
    public var trainTypes: [TrainType]

    public init(version: Int, stations: [Station], lines: [Line], operators: [Operator], trainTypes: [TrainType]) {
        self.version = version
        self.stations = stations
        self.lines = lines
        self.operators = operators
        self.trainTypes = trainTypes
    }

    public init(version: Int, catalog: Catalog) {
        self.init(
            version: version,
            stations: Array(catalog.stations.values), lines: Array(catalog.lines.values),
            operators: Array(catalog.operators.values), trainTypes: Array(catalog.trainTypes.values)
        )
    }

    public var catalog: Catalog {
        Catalog(stations: stations, lines: lines, operators: operators, trainTypes: trainTypes)
    }

    /// パッケージに同梱した駅マスタ
    public static func bundled() -> StationMasterSnapshot {
        guard let url = Bundle.module.url(forResource: "StationMaster", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let snapshot = try? NorikaeJSON.makeDecoder().decode(StationMasterSnapshot.self, from: data) else {
            assertionFailure("同梱の駅マスタを読めません")
            return StationMasterSnapshot(version: 0, stations: [], lines: [], operators: [], trainTypes: [])
        }
        return snapshot
    }
}

/// 同梱の駅マスタを端末内で検索する Repository（FR-SRC-02、FR-OFF-04）
public actor LocalStationRepository: StationRepository {
    private let source: (any MasterDataSource)?
    private let store: JSONFileStore
    private var loaded: (version: Int, catalog: Catalog, stations: [Station])?

    /// - Parameter source: 差分の取得元。`nil` なら差分を取りに行かない（モック・テスト）
    public init(source: (any MasterDataSource)?, store: JSONFileStore = .applicationSupport("station-master")) {
        self.source = source
        self.store = store
    }

    public func search(text: String, preferredRegion: Region) async throws -> [Station] {
        StationSearchMatcher.search(text, in: await load().stations, preferredRegion: preferredRegion)
    }

    public func nearest(to coordinate: Coordinate, limit: Int) async throws -> [Station] {
        StationSearchMatcher.nearest(to: coordinate, in: await load().stations, limit: limit)
    }

    public func catalog() async -> Catalog {
        await load().catalog
    }

    public func applyUpdates() async throws -> StationMigration {
        guard let source else { return StationMigration() }
        let current = await load()
        let changes = try await source.changes(sinceVersion: current.version)
        guard changes.version > current.version else { return StationMigration() }
        var catalog = current.catalog
        catalog.apply(changes)
        let snapshot = StationMasterSnapshot(version: changes.version, catalog: catalog)
        await store.save(snapshot, key: "snapshot")
        loaded = (changes.version, catalog, Array(catalog.stations.values))
        return StationMigration(changes: changes)
    }

    private func load() async -> (version: Int, catalog: Catalog, stations: [Station]) {
        if let loaded { return loaded }
        let bundled = StationMasterSnapshot.bundled()
        var snapshot = bundled
        // 差分を適用して保存したものが、同梱より新しければそちらを使う
        if let saved = await store.load(StationMasterSnapshot.self, key: "snapshot"), saved.version > bundled.version {
            snapshot = saved
        }
        let catalog = snapshot.catalog
        let result = (snapshot.version, catalog, snapshot.stations)
        loaded = result
        return result
    }
}
