import Foundation

/// 提供状況の機能名（api-contract 3.15）
public enum CapabilityFeature: String, Codable, Sendable, Hashable, CaseIterable {
    // 路線ごと
    case routeSearch
    case timetable
    case stopList
    case fare
    case operationAlerts
    case tripUpdates
    case vehiclePositions
    case platform
    case boardingPosition
    // 地域ごと（フロントからの追加要求）
    case viaStations
    case firstLastTrain
}

/// 路線ごとの提供状況
public struct LineCapability: Codable, Sendable, Hashable {
    public var lineId: String
    /// 未知の機能名が増えても読めるよう、キーは文字列のまま持つ
    public var features: [String: DataAvailability]
    public var asOf: Date

    public init(lineId: String, features: [CapabilityFeature: DataAvailability], asOf: Date) {
        self.lineId = lineId
        self.features = Dictionary(uniqueKeysWithValues: features.map { ($0.key.rawValue, $0.value) })
        self.asOf = asOf
    }

    public func availability(_ feature: CapabilityFeature) -> DataAvailability? {
        features[feature.rawValue]
    }
}

/// 地域ごとの提供状況
public struct RegionCapability: Codable, Sendable, Hashable {
    public var region: Region
    public var features: [String: DataAvailability]

    public init(region: Region, features: [CapabilityFeature: DataAvailability]) {
        self.region = region
        self.features = Dictionary(uniqueKeysWithValues: features.map { ($0.key.rawValue, $0.value) })
    }

    public func availability(_ feature: CapabilityFeature) -> DataAvailability? {
        features[feature.rawValue]
    }
}

/// 端末にキャッシュする提供状況の全体
public struct CapabilitySnapshot: Codable, Sendable, Hashable {
    public var lines: [LineCapability]
    public var regions: [RegionCapability]
    /// 端末で取得した時刻（1 日 1 回の更新判定に使う）
    public var fetchedAt: Date?

    public init(lines: [LineCapability] = [], regions: [RegionCapability] = [], fetchedAt: Date? = nil) {
        self.lines = lines
        self.regions = regions
        self.fetchedAt = fetchedAt
    }

    /// 取得できずキャッシュもないとき。全機能を利用可能として扱う（FR-CAP-03）
    public static let assumeAllAvailable = CapabilitySnapshot()

    /// 路線の機能の提供状況。情報がない場合は利用可能として扱い、API のエラーで判定する
    public func availability(_ feature: CapabilityFeature, lineId: String) -> DataAvailability {
        lines.first { $0.lineId == lineId }?.availability(feature) ?? .available
    }

    /// 地域の機能の提供状況。情報がない場合は利用可能として扱う
    public func availability(_ feature: CapabilityFeature, region: Region) -> DataAvailability {
        regions.first { $0.region == region }?.availability(feature) ?? .available
    }

    public func isSupported(_ feature: CapabilityFeature, lineId: String) -> Bool {
        availability(feature, lineId: lineId).isUsable
    }

    public func isSupported(_ feature: CapabilityFeature, region: Region) -> Bool {
        availability(feature, region: region).isUsable
    }

    /// 経路の全乗車区間でリアルタイム情報（`tripUpdates`）があるか
    public func supportsRealtime(for route: Route) -> Bool {
        route.trainLegs.allSatisfy { isSupported(.tripUpdates, lineId: $0.lineId) }
    }

    /// 1 日 1 回の更新が必要か（FR-CAP-01）
    public func needsRefresh(now: Date) -> Bool {
        guard let fetchedAt else { return true }
        return now.timeIntervalSince(fetchedAt) >= 24 * 60 * 60
    }
}
