import Foundation

/// 事業者（api-contract 3.1）
public struct Operator: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var region: [Region]

    public init(id: String, name: String, region: [Region]) {
        self.id = id
        self.name = name
        self.region = region
    }
}

/// 路線（api-contract 3.2）
public struct Line: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var operatorId: String
    public var name: String
    public var symbol: String?
    public var displayCode: String?
    public var color: String?
    public var region: Region

    public init(id: String, operatorId: String, name: String, symbol: String? = nil, displayCode: String? = nil, color: String? = nil, region: Region) {
        self.id = id
        self.operatorId = operatorId
        self.name = name
        self.symbol = symbol
        self.displayCode = displayCode
        self.color = color
        self.region = region
    }

    /// 路線記号の欄に出す文字。`symbol` → `displayCode` → `name` の順で最初にある値（NFR-A11Y-04）
    public var label: String {
        [symbol, displayCode].compactMap { $0?.nonEmpty }.first ?? name
    }

    /// 公式の路線記号があるか
    public var hasOfficialSymbol: Bool { symbol?.nonEmpty != nil }

    /// 路線色（`#RRGGBB`）。ない場合は `nil`（DesignSystem の既定色で描く）
    public var rgbColor: RGBColor? { color.flatMap(RGBColor.init(hex:)) }
}

/// 駅の出口
public struct StationExit: Codable, Sendable, Hashable {
    public var name: String
    public var latitude: Double
    public var longitude: Double

    public init(name: String, latitude: Double, longitude: Double) {
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
    }

    public var coordinate: Coordinate { Coordinate(latitude: latitude, longitude: longitude) }
}

/// 駅（駅マスタ、api-contract 3.3）
public struct Station: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var reading: String
    public var prefecture: String
    public var region: Region
    public var lineIds: [String]
    public var stationCodes: [String]?
    public var latitude: Double
    public var longitude: Double
    public var exits: [StationExit]?

    public init(
        id: String, name: String, reading: String, prefecture: String, region: Region,
        lineIds: [String], stationCodes: [String]? = nil, latitude: Double, longitude: Double, exits: [StationExit]? = nil
    ) {
        self.id = id
        self.name = name
        self.reading = reading
        self.prefecture = prefecture
        self.region = region
        self.lineIds = lineIds
        self.stationCodes = stationCodes
        self.latitude = latitude
        self.longitude = longitude
        self.exits = exits
    }

    public var coordinate: Coordinate { Coordinate(latitude: latitude, longitude: longitude) }
}

/// 種別（api-contract 3.4）
public struct TrainType: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var shortName: String
    public var color: String?
    public var isPaidExpress: Bool
    public var isShinkansen: Bool

    public init(id: String, name: String, shortName: String, color: String? = nil, isPaidExpress: Bool = false, isShinkansen: Bool = false) {
        self.id = id
        self.name = name
        self.shortName = shortName
        self.color = color
        self.isPaidExpress = isPaidExpress
        self.isShinkansen = isShinkansen
    }
}

/// 駅・路線・事業者・種別の参照表。駅マスタと、応答に同梱された定義（includes）をまとめて引く
public struct Catalog: Sendable, Hashable {
    public private(set) var stations: [String: Station]
    public private(set) var lines: [String: Line]
    public private(set) var operators: [String: Operator]
    public private(set) var trainTypes: [String: TrainType]

    public init(stations: [Station] = [], lines: [Line] = [], operators: [Operator] = [], trainTypes: [TrainType] = []) {
        self.stations = Dictionary(stations.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        self.lines = Dictionary(lines.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        self.operators = Dictionary(operators.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        self.trainTypes = Dictionary(trainTypes.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
    }

    public static let empty = Catalog()

    public func station(_ id: String) -> Station? { stations[id] }
    public func line(_ id: String) -> Line? { lines[id] }
    public func `operator`(_ id: String) -> Operator? { operators[id] }
    public func trainType(_ id: String) -> TrainType? { trainTypes[id] }

    /// 応答に同梱された定義を上書きで取り込む
    public func merging(_ includes: ReferenceIncludes?) -> Catalog {
        guard let includes else { return self }
        var copy = self
        for line in includes.lines ?? [] { copy.lines[line.id] = line }
        for type in includes.trainTypes ?? [] { copy.trainTypes[type.id] = type }
        for station in includes.stations ?? [] { copy.stations[station.id] = station }
        for op in includes.operators ?? [] { copy.operators[op.id] = op }
        return copy
    }

    /// 差分を適用する（API-08）
    public mutating func apply(_ changes: MasterDataChanges) {
        for station in changes.stations ?? [] { stations[station.id] = station }
        for line in changes.lines ?? [] { lines[line.id] = line }
        for op in changes.operators ?? [] { operators[op.id] = op }
        for type in changes.trainTypes ?? [] { trainTypes[type.id] = type }
        for removal in changes.removed ?? [] {
            switch removal.kind {
            case .station: stations[removal.id] = nil
            case .line: lines[removal.id] = nil
            case .operator: operators[removal.id] = nil
            case .trainType: trainTypes[removal.id] = nil
            }
        }
    }
}

/// 応答に同梱された参照データ（api-contract 4 章の `includes`）
public struct ReferenceIncludes: Codable, Sendable, Hashable {
    public var lines: [Line]?
    public var trainTypes: [TrainType]?
    public var stations: [Station]?
    public var operators: [Operator]?

    public init(lines: [Line]? = nil, trainTypes: [TrainType]? = nil, stations: [Station]? = nil, operators: [Operator]? = nil) {
        self.lines = lines
        self.trainTypes = trainTypes
        self.stations = stations
        self.operators = operators
    }
}

/// 駅マスタの差分（API-08）をアプリで扱う形にまとめたもの
///
/// API の応答（`{ version, changes: [{ entity, id, operation, value, replacedById }] }`）からの変換は NorikaeData で行う。
public struct MasterDataChanges: Codable, Sendable, Hashable {
    public var version: Int
    public var stations: [Station]?
    public var lines: [Line]?
    public var operators: [Operator]?
    public var trainTypes: [TrainType]?
    public var removed: [Removal]?

    public struct Removal: Codable, Sendable, Hashable {
        public enum Kind: String, Codable, Sendable {
            case station, line, `operator`, trainType
        }

        public var kind: Kind
        public var id: String
        /// 統合先の ID。移行先がない廃止は `nil`
        public var replacedById: String?

        public init(kind: Kind, id: String, replacedById: String? = nil) {
            self.kind = kind
            self.id = id
            self.replacedById = replacedById
        }
    }

    public init(version: Int, stations: [Station]? = nil, lines: [Line]? = nil, operators: [Operator]? = nil, trainTypes: [TrainType]? = nil, removed: [Removal]? = nil) {
        self.version = version
        self.stations = stations
        self.lines = lines
        self.operators = operators
        self.trainTypes = trainTypes
        self.removed = removed
    }
}

/// 差分の適用で無効になった駅・路線の ID と、その移行先（FR-SRC-09）
public struct StationMigration: Sendable, Hashable {
    /// 駅：旧 ID → 新 ID
    public var replacements: [String: String]
    /// 移行先のない廃止駅（お気に入りなどに「この駅は利用できません」と出す）
    public var removedWithoutReplacement: Set<String>
    /// 路線：旧 ID → 新 ID（マイ路線の移行に使う）
    public var lineReplacements: [String: String]

    public init(replacements: [String: String] = [:], removedWithoutReplacement: Set<String> = [], lineReplacements: [String: String] = [:]) {
        self.replacements = replacements
        self.removedWithoutReplacement = removedWithoutReplacement
        self.lineReplacements = lineReplacements
    }

    /// 差分から作る
    public init(changes: MasterDataChanges) {
        var replacements: [String: String] = [:]
        var removed: Set<String> = []
        var lineReplacements: [String: String] = [:]
        for removal in changes.removed ?? [] {
            switch removal.kind {
            case .station:
                if let target = removal.replacedById { replacements[removal.id] = target } else { removed.insert(removal.id) }
            case .line:
                if let target = removal.replacedById { lineReplacements[removal.id] = target }
            case .operator, .trainType:
                break
            }
        }
        self.init(replacements: replacements, removedWithoutReplacement: removed, lineReplacements: lineReplacements)
    }

    public var isEmpty: Bool { replacements.isEmpty && removedWithoutReplacement.isEmpty && lineReplacements.isEmpty }
}

extension String {
    /// 空文字を `nil` として扱う（api-contract 2 章「空文字は使わない」への防御）
    var nonEmpty: String? { isEmpty ? nil : self }
}
