import Foundation

/// 縦比較の 1 列の配置（design-spec 7.4）。描画は DesignSystem、位置の計算はここで行う
public struct CompareColumnLayout: Sendable, Hashable {
    /// 乗車区間の帯
    public struct Band: Sendable, Hashable {
        public var legIndex: Int
        public var leg: TrainLeg
        public var top: Double
        public var bottom: Double

        public var height: Double { bottom - top }
        public var midY: Double { (top + bottom) / 2 }
    }

    /// 乗換・待ち時間の点線
    public struct Connector: Sendable, Hashable {
        public var top: Double
        public var bottom: Double
    }

    /// 発着の時刻と駅名のラベル
    public struct TimeLabel: Sendable, Hashable {
        public enum Role: Sendable, Hashable {
            case departure
            case arrival
        }

        public var y: Double
        public var time: Date
        public var stationId: String
        public var role: Role
        /// 駅名を出すか。乗換駅で着と発が近いときは 2 つ目の駅名を省く
        public var showsStationName: Bool
    }

    public var bands: [Band]
    public var connectors: [Connector]
    public var labels: [TimeLabel]

    /// 列の配置を計算する
    ///
    /// - Parameters:
    ///   - collapseDistance: 乗換駅の着と発のラベルがこれより近いとき、発の駅名を省く（32pt）
    ///   - minimumLabelSpacing: これより近いと重なるため、着のラベルを省いて発車の時刻を優先する
    public init(
        route: Route, axis: TimeAxis, pointsPerMinute: Double, verticalPadding: Double,
        collapseDistance: Double = 32, minimumLabelSpacing: Double = 16
    ) {
        func y(_ date: Date) -> Double {
            axis.y(for: date, pointsPerMinute: pointsPerMinute, verticalPadding: verticalPadding)
        }

        let trains = route.indexedTrainLegs
        bands = trains.map { item in
            Band(legIndex: item.legIndex, leg: item.leg, top: y(item.leg.from.scheduledTime), bottom: y(item.leg.to.scheduledTime))
        }

        var connectors: [Connector] = []
        if let first = trains.first, route.departureTime < first.leg.from.scheduledTime {
            connectors.append(Connector(top: y(route.departureTime), bottom: y(first.leg.from.scheduledTime)))
        }
        for (previous, next) in zip(trains, trains.dropFirst()) where previous.leg.to.scheduledTime < next.leg.from.scheduledTime {
            connectors.append(Connector(top: y(previous.leg.to.scheduledTime), bottom: y(next.leg.from.scheduledTime)))
        }
        if let last = trains.last, last.leg.to.scheduledTime < route.arrivalTime {
            connectors.append(Connector(top: y(last.leg.to.scheduledTime), bottom: y(route.arrivalTime)))
        }
        self.connectors = connectors

        var labels: [TimeLabel] = []
        for (offset, item) in trains.enumerated() {
            let departure = TimeLabel(
                y: y(item.leg.from.scheduledTime), time: item.leg.from.scheduledTime,
                stationId: item.leg.from.stationId, role: .departure, showsStationName: true
            )
            if offset > 0, let previousArrival = labels.last, previousArrival.role == .arrival {
                let distance = departure.y - previousArrival.y
                if distance < minimumLabelSpacing {
                    // 重なるときは発車の時刻を優先する
                    labels.removeLast()
                    labels.append(departure)
                } else if distance < collapseDistance {
                    var collapsed = departure
                    collapsed.showsStationName = previousArrival.stationId != departure.stationId
                    labels.append(collapsed)
                } else {
                    labels.append(departure)
                }
            } else {
                labels.append(departure)
            }
            labels.append(TimeLabel(
                y: y(item.leg.to.scheduledTime), time: item.leg.to.scheduledTime,
                stationId: item.leg.to.stationId, role: .arrival, showsStationName: true
            ))
        }
        self.labels = labels
    }
}

/// 経路詳細の乗換（FR-DTL-01、design-spec 7.5）
public struct TransferInfo: Sendable, Hashable {
    /// 前の区間の到着から次の区間の出発までの分数
    public var totalMinutes: Int
    /// 歩く時間（徒歩区間がある場合）
    public var walkMinutes: Int?
    /// 乗換駅（降車駅）
    public var fromStationId: String
    /// 乗り換える駅（次の乗車駅）
    public var toStationId: String

    public init(totalMinutes: Int, walkMinutes: Int?, fromStationId: String, toStationId: String) {
        self.totalMinutes = totalMinutes
        self.walkMinutes = walkMinutes
        self.fromStationId = fromStationId
        self.toStationId = toStationId
    }
}

extension Route {
    /// 乗車区間の間の乗換。`transfers[i]` は i 番目と i+1 番目の乗車区間の間
    public var transfers: [TransferInfo] {
        let indexed = indexedTrainLegs
        return zip(indexed, indexed.dropFirst()).map { previous, next in
            var walk = 0
            for leg in legs[(previous.legIndex + 1)..<next.legIndex] {
                if case .walk(let walkLeg) = leg { walk += walkLeg.durationMinutes }
            }
            let minutes = Int((next.leg.from.scheduledTime.timeIntervalSince(previous.leg.to.scheduledTime) / 60).rounded())
            return TransferInfo(
                totalMinutes: max(minutes, 0),
                walkMinutes: walk > 0 ? walk : nil,
                fromStationId: previous.leg.to.stationId,
                toStationId: next.leg.from.stationId
            )
        }
    }
}
