import Foundation

/// 経路の構成（乗車区間の路線・乗車駅・降車駅）
///
/// 「1本後に変更」で Live Activity を更新できるか（構成が同じか）の判定に使う（FR-LA-20、api-contract 5.3）
public struct RouteStructure: Codable, Sendable, Hashable {
    public struct Segment: Codable, Sendable, Hashable {
        public var lineId: String
        public var fromStationId: String
        public var toStationId: String

        public init(lineId: String, fromStationId: String, toStationId: String) {
            self.lineId = lineId
            self.fromStationId = fromStationId
            self.toStationId = toStationId
        }
    }

    public var segments: [Segment]

    public init(segments: [Segment]) {
        self.segments = segments
    }

    public init(route: Route) {
        segments = route.trainLegs.map {
            Segment(lineId: $0.lineId, fromStationId: $0.from.stationId, toStationId: $0.to.stationId)
        }
    }
}

/// 経路の特定情報（区間の路線・乗車駅・降車駅・出発時刻）
///
/// お気に入り経路の保存（FR-DTL-03）と、`routeContext` 期限切れ時の同一経路の照合（api-contract 4.2）に使う
public struct RouteSignature: Codable, Sendable, Hashable {
    public struct Segment: Codable, Sendable, Hashable {
        public var lineId: String
        public var fromStationId: String
        public var toStationId: String
        public var departureTime: Date

        public init(lineId: String, fromStationId: String, toStationId: String, departureTime: Date) {
            self.lineId = lineId
            self.fromStationId = fromStationId
            self.toStationId = toStationId
            self.departureTime = departureTime
        }
    }

    public var segments: [Segment]

    public init(segments: [Segment]) {
        self.segments = segments
    }

    public init(route: Route) {
        segments = route.trainLegs.map {
            Segment(lineId: $0.lineId, fromStationId: $0.from.stationId, toStationId: $0.to.stationId, departureTime: $0.from.scheduledTime)
        }
    }

    public var structure: RouteStructure {
        RouteStructure(segments: segments.map {
            RouteStructure.Segment(lineId: $0.lineId, fromStationId: $0.fromStationId, toStationId: $0.toStationId)
        })
    }

    /// 同じ経路か。出発時刻は時刻表上の時刻を分単位で比べる
    public func matches(_ route: Route) -> Bool {
        let other = RouteSignature(route: route)
        guard segments.count == other.segments.count else { return false }
        return zip(segments, other.segments).allSatisfy { lhs, rhs in
            lhs.lineId == rhs.lineId
                && lhs.fromStationId == rhs.fromStationId
                && lhs.toStationId == rhs.toStationId
                && Int(lhs.departureTime.timeIntervalSince1970 / 60) == Int(rhs.departureTime.timeIntervalSince1970 / 60)
        }
    }

    /// 検索結果から同じ経路を探す
    public func findMatch(in routes: [Route]) -> Route? {
        routes.first { matches($0) }
    }

    /// 構成だけ一致する経路を探す（お気に入りを開くとき、時刻が変わっていても同じ乗り方を探す）
    public func findStructuralMatch(in routes: [Route]) -> Route? {
        let structure = self.structure
        return routes.first { RouteStructure(route: $0) == structure }
    }

    public func replacingStationIDs(_ replacements: [String: String]) -> RouteSignature {
        RouteSignature(segments: segments.map {
            var copy = $0
            copy.fromStationId = replacements[$0.fromStationId] ?? $0.fromStationId
            copy.toStationId = replacements[$0.toStationId] ?? $0.toStationId
            return copy
        })
    }
}

/// 1 本前・1 本後の経路で変わった点（FR-DTL-06）
public struct AdjacentRouteChange: Sendable, Hashable {
    /// 乗換駅が変わった
    public var transferStationsChanged: Bool
    /// 乗換後の列車（路線・区間の構成）が変わった
    public var trainsChanged: Bool
    /// 到着時刻の差（分）。正なら遅くなった
    public var arrivalDeltaMinutes: Int

    public init(original: Route, adjacent: Route) {
        let originalTransfers = original.transfers.map(\.fromStationId)
        let adjacentTransfers = adjacent.transfers.map(\.fromStationId)
        transferStationsChanged = originalTransfers != adjacentTransfers
        trainsChanged = RouteStructure(route: original) != RouteStructure(route: adjacent)
        arrivalDeltaMinutes = Int((adjacent.arrivalTime.timeIntervalSince(original.arrivalTime) / 60).rounded())
    }

    /// 経路の構成が変わったか（Live Activity を開始し直す必要があるか）
    public var structureChanged: Bool { transferStationsChanged || trainsChanged }
}
