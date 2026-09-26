import Foundation

/// Live Activity の動的な情報（`ActivityAttributes.ContentState`、api-contract 5.3）
///
/// APNs の `content-state` と完全に一致させる。日時は UNIX 時刻の `Int` で持ち、`Date` は計算プロパティで作る
/// （ActivityKit は既定の `JSONDecoder` で読むため）。
public struct LiveRouteState: Codable, Sendable, Hashable {
    public struct LegState: Codable, Sendable, Hashable {
        /// 乗車区間の順番（0 始まり、徒歩区間は数えない）
        public var index: Int
        public var platform: String?
        public var scheduledDeparture: Int
        public var estimatedDeparture: Int?
        public var scheduledArrival: Int
        public var estimatedArrival: Int?
        public var delayMinutes: Int?
        public var isCancelled: Bool

        public init(
            index: Int, platform: String? = nil, scheduledDeparture: Int, estimatedDeparture: Int? = nil,
            scheduledArrival: Int, estimatedArrival: Int? = nil, delayMinutes: Int? = nil, isCancelled: Bool = false
        ) {
            self.index = index
            self.platform = platform
            self.scheduledDeparture = scheduledDeparture
            self.estimatedDeparture = estimatedDeparture
            self.scheduledArrival = scheduledArrival
            self.estimatedArrival = estimatedArrival
            self.delayMinutes = delayMinutes
            self.isCancelled = isCancelled
        }

        public var departureDate: Date { Date(timeIntervalSince1970: TimeInterval(estimatedDeparture ?? scheduledDeparture)) }
        public var arrivalDate: Date { Date(timeIntervalSince1970: TimeInterval(estimatedArrival ?? scheduledArrival)) }
        public var scheduledDepartureDate: Date { Date(timeIntervalSince1970: TimeInterval(scheduledDeparture)) }
        public var scheduledArrivalDate: Date { Date(timeIntervalSince1970: TimeInterval(scheduledArrival)) }

        /// 見込みの時刻があるか（リアルタイムの予測がある区間か）
        public var hasEstimate: Bool { estimatedDeparture != nil || estimatedArrival != nil }
    }

    /// 端末だけで付ける表示（サーバーは送らない。プッシュで置き換わると消える）
    public enum LocalNotice: String, Codable, Sendable, Hashable {
        /// オフラインで「1本後に変更」できなかった（FR-LA-21）
        case offlineChangeFailed
        /// 1本後の経路を取得できなかった
        case changeFailed
        /// 経路の構成が変わるため、アプリで開始し直す必要がある（frontend.md 14 章 #6 の代替表示）
        case reopenAppToChange
    }

    public var legs: [LegState]
    public var disruptionSummary: String?
    public var updatedAt: Int
    public var localNotice: LocalNotice?

    public init(legs: [LegState], disruptionSummary: String? = nil, updatedAt: Int, localNotice: LocalNotice? = nil) {
        self.legs = legs
        self.disruptionSummary = disruptionSummary
        self.updatedAt = updatedAt
        self.localNotice = localNotice
    }

    public var updatedAtDate: Date { Date(timeIntervalSince1970: TimeInterval(updatedAt)) }

    /// 経路から、時刻表どおりの初期状態を作る
    public init(route: Route, now: Date) {
        legs = route.trainLegs.enumerated().map { index, leg in
            LegState(
                index: index,
                platform: leg.from.platform,
                scheduledDeparture: Int(leg.from.scheduledTime.timeIntervalSince1970),
                estimatedDeparture: leg.from.estimatedTime.map { Int($0.timeIntervalSince1970) },
                scheduledArrival: Int(leg.to.scheduledTime.timeIntervalSince1970),
                estimatedArrival: leg.to.estimatedTime.map { Int($0.timeIntervalSince1970) },
                delayMinutes: leg.delayMinutes,
                isCancelled: false
            )
        }
        disruptionSummary = route.trainLegs.compactMap(\.disruption?.summary).first
        updatedAt = Int(now.timeIntervalSince1970)
        localNotice = nil
    }

    /// 最終到着時刻（遅延分を含む）
    public var finalArrival: Date? { legs.last?.arrivalDate }
}

/// Live Activity の開始後に変わらない情報（`ActivityAttributes` の中身、api-contract 5.3）
public struct GuidanceSummary: Codable, Sendable, Hashable {
    public struct LegInfo: Codable, Sendable, Hashable {
        public var lineName: String
        /// 路線記号の欄に出す文字（`symbol` → `displayCode` → `name`）
        public var lineLabel: String
        /// 路線色（`#RRGGBB`）。ない場合は既定色
        public var lineColorHex: String?
        public var trainTypeName: String
        public var destinationName: String
        public var fromStationName: String
        public var toStationName: String
        /// その区間にリアルタイム情報があるか（capabilities の `tripUpdates`）
        public var hasRealtime: Bool

        public init(
            lineName: String, lineLabel: String, lineColorHex: String?, trainTypeName: String, destinationName: String,
            fromStationName: String, toStationName: String, hasRealtime: Bool
        ) {
            self.lineName = lineName
            self.lineLabel = lineLabel
            self.lineColorHex = lineColorHex
            self.trainTypeName = trainTypeName
            self.destinationName = destinationName
            self.fromStationName = fromStationName
            self.toStationName = toStationName
            self.hasRealtime = hasRealtime
        }
    }

    public var originName: String
    public var destinationName: String
    public var legs: [LegInfo]

    public init(originName: String, destinationName: String, legs: [LegInfo]) {
        self.originName = originName
        self.destinationName = destinationName
        self.legs = legs
    }

    /// 経路と参照表から作る
    public init(route: Route, catalog: Catalog, capabilities: CapabilitySnapshot, fallbackStationName: String, fallbackTrainTypeName: String) {
        let trains = route.trainLegs
        func stationName(_ id: String) -> String { catalog.station(id)?.name ?? fallbackStationName }
        originName = trains.first.map { stationName($0.from.stationId) } ?? fallbackStationName
        destinationName = trains.last.map { stationName($0.to.stationId) } ?? fallbackStationName
        legs = trains.map { leg in
            let line = catalog.line(leg.lineId)
            return LegInfo(
                lineName: line?.name ?? leg.lineId,
                lineLabel: line?.label ?? leg.lineId,
                lineColorHex: line?.color,
                trainTypeName: catalog.trainType(leg.trainTypeId)?.name ?? fallbackTrainTypeName,
                destinationName: leg.destinationName,
                fromStationName: stationName(leg.from.stationId),
                toStationName: stationName(leg.to.stationId),
                hasRealtime: capabilities.isSupported(.tripUpdates, lineId: leg.lineId)
            )
        }
    }
}

/// 案内の進み具合（端末だけで計算する、FR-LA-10）
public struct GuidanceProgress: Sendable, Hashable {
    public enum Phase: Sendable, Hashable {
        /// 区間 `legIndex` の発車を待っている
        case waiting(legIndex: Int)
        /// 区間 `legIndex` に乗車中
        case riding(legIndex: Int)
        /// 到着した
        case arrived
    }

    public var phase: Phase
    /// 経路全体の進み具合（0〜1）
    public var fraction: Double
    /// 次の出来事（発車または到着）の時刻
    public var nextEventDate: Date?

    public init(state: LiveRouteState, now: Date) {
        guard let first = state.legs.first, let last = state.legs.last else {
            phase = .arrived
            fraction = 1
            nextEventDate = nil
            return
        }
        let start = first.departureDate
        let end = last.arrivalDate
        let total = end.timeIntervalSince(start)
        fraction = total > 0 ? min(max(now.timeIntervalSince(start) / total, 0), 1) : (now >= end ? 1 : 0)

        if let current = state.legs.first(where: { $0.arrivalDate > now && !$0.isCancelled }) ?? state.legs.first(where: { $0.arrivalDate > now }) {
            if now < current.departureDate {
                phase = .waiting(legIndex: current.index)
                nextEventDate = current.departureDate
            } else {
                phase = .riding(legIndex: current.index)
                nextEventDate = current.arrivalDate
            }
        } else {
            phase = .arrived
            nextEventDate = nil
        }
    }

    /// 次に乗る（または乗っている）区間
    public var currentLegIndex: Int? {
        switch phase {
        case .waiting(let index), .riding(let index): index
        case .arrived: nil
        }
    }

    /// 次に区間の状態が切り替わる時刻（端末で表示を更新する時刻、FR-LA-10）
    public static func transitionDates(for state: LiveRouteState, after now: Date) -> [Date] {
        state.legs.flatMap { [$0.departureDate, $0.arrivalDate] }.filter { $0 > now }.sorted()
    }

    /// 自動で終了する時刻（到着予定時刻。遅延分は延長する、FR-LA-03）
    public static func endDate(for state: LiveRouteState) -> Date? {
        state.finalArrival
    }
}
