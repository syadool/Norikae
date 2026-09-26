import Foundation

/// 経路を再現するための不透明な値。短寿命（api-contract 4.2）
public struct RouteContext: Codable, Sendable, Hashable {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public init(from decoder: any Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// 経路（api-contract 3.5）
public struct Route: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var departureTime: Date
    public var arrivalTime: Date
    public var durationMinutes: Int
    public var transferCount: Int
    public var fare: Fare
    public var legs: [Leg]
    public var hasServiceDisruption: Bool
    public var availability: DataAvailability
    public var warnings: [RouteWarning]
    public var routeContext: RouteContext

    public init(
        id: String, departureTime: Date, arrivalTime: Date, durationMinutes: Int, transferCount: Int, fare: Fare,
        legs: [Leg], hasServiceDisruption: Bool, availability: DataAvailability = .available,
        warnings: [RouteWarning] = [], routeContext: RouteContext
    ) {
        self.id = id
        self.departureTime = departureTime
        self.arrivalTime = arrivalTime
        self.durationMinutes = durationMinutes
        self.transferCount = transferCount
        self.fare = fare
        self.legs = legs
        self.hasServiceDisruption = hasServiceDisruption
        self.availability = availability
        self.warnings = warnings
        self.routeContext = routeContext
    }

    /// 乗車区間だけ（時刻順）
    public var trainLegs: [TrainLeg] {
        indexedTrainLegs.map(\.leg)
    }

    /// `legs` 上の位置付きの乗車区間
    public var indexedTrainLegs: [(legIndex: Int, leg: TrainLeg)] {
        var result: [(legIndex: Int, leg: TrainLeg)] = []
        for (index, leg) in legs.enumerated() {
            if case .train(let train) = leg {
                result.append((index, train))
            }
        }
        return result
    }

    /// 最初の乗車駅
    public var originStationId: String? { trainLegs.first?.from.stationId }
    /// 最後の降車駅
    public var destinationStationId: String? { trainLegs.last?.to.stationId }

    /// 区間に紐づかない警告
    public var routeLevelWarnings: [RouteWarning] { warnings.filter { $0.legIndex == nil } }

    /// その区間に紐づく警告
    public func warnings(forLegAt index: Int) -> [RouteWarning] {
        warnings.filter { $0.legIndex == index }
    }
}

/// 経路の警告（api-contract 3.5）
public struct RouteWarning: Codable, Sendable, Hashable {
    public var code: String
    public var message: String
    public var legIndex: Int?

    public init(code: String, message: String, legIndex: Int? = nil) {
        self.code = code
        self.message = message
        self.legIndex = legIndex
    }
}

/// 区間（api-contract 3.6）
public enum Leg: Codable, Sendable, Hashable {
    case train(TrainLeg)
    case walk(WalkLeg)

    private enum CodingKeys: String, CodingKey {
        case type
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "train": self = .train(try TrainLeg(from: decoder))
        case "walk": self = .walk(try WalkLeg(from: decoder))
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "未知の区間の種類: \(type)")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .train(let leg):
            try container.encode("train", forKey: .type)
            try leg.encode(to: encoder)
        case .walk(let leg):
            try container.encode("walk", forKey: .type)
            try leg.encode(to: encoder)
        }
    }
}

/// 乗車区間（`type: "train"`）
public struct TrainLeg: Codable, Sendable, Hashable {
    public var lineId: String
    public var trainTypeId: String
    public var trainRunId: String?
    public var destinationName: String
    public var from: StopPoint
    public var to: StopPoint
    public var stopCount: Int
    public var boardingPosition: BoardingPosition?
    public var disruption: LegDisruption?

    public init(
        lineId: String, trainTypeId: String, trainRunId: String? = nil, destinationName: String,
        from: StopPoint, to: StopPoint, stopCount: Int, boardingPosition: BoardingPosition? = nil, disruption: LegDisruption? = nil
    ) {
        self.lineId = lineId
        self.trainTypeId = trainTypeId
        self.trainRunId = trainRunId
        self.destinationName = destinationName
        self.from = from
        self.to = to
        self.stopCount = stopCount
        self.boardingPosition = boardingPosition
        self.disruption = disruption
    }

    /// 遅延の分数。区間の遅延情報、なければ見込み時刻から求める。どちらもなければ `nil`（「遅延なし」ではない）
    public var delayMinutes: Int? {
        if let minutes = disruption?.delayMinutes { return minutes }
        return from.delayMinutes ?? to.delayMinutes
    }
}

/// 徒歩区間（`type: "walk"`）
public struct WalkLeg: Codable, Sendable, Hashable {
    public var fromStationId: String
    public var toStationId: String
    public var durationMinutes: Int

    public init(fromStationId: String, toStationId: String, durationMinutes: Int) {
        self.fromStationId = fromStationId
        self.toStationId = toStationId
        self.durationMinutes = durationMinutes
    }
}

/// 停車点（api-contract 3.7）
public struct StopPoint: Codable, Sendable, Hashable {
    public var stationId: String
    public var scheduledTime: Date
    public var estimatedTime: Date?
    public var platform: String?
    public var serviceDate: ServiceDate

    public init(stationId: String, scheduledTime: Date, estimatedTime: Date? = nil, platform: String? = nil, serviceDate: ServiceDate) {
        self.stationId = stationId
        self.scheduledTime = scheduledTime
        self.estimatedTime = estimatedTime
        self.platform = platform
        self.serviceDate = serviceDate
    }

    /// 見込みの時刻があればそれ、なければ時刻表上の時刻
    public var effectiveTime: Date { estimatedTime ?? scheduledTime }

    /// 見込み時刻と時刻表上の時刻の差（分）。見込み時刻がなければ `nil`
    public var delayMinutes: Int? {
        guard let estimatedTime else { return nil }
        return Int((estimatedTime.timeIntervalSince(scheduledTime) / 60).rounded())
    }
}

/// 乗車位置（api-contract 3.9）
public struct BoardingPosition: Codable, Sendable, Hashable {
    public enum Purpose: Codable, Sendable, Hashable {
        case transfer
        case exit
        case other(String)

        public init(from decoder: any Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            switch raw {
            case "transfer": self = .transfer
            case "exit": self = .exit
            default: self = .other(raw)
            }
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .transfer: try container.encode("transfer")
            case .exit: try container.encode("exit")
            case .other(let raw): try container.encode(raw)
            }
        }
    }

    public var carNumber: Int
    public var carCount: Int?
    public var purpose: Purpose
    public var note: String?

    public init(carNumber: Int, carCount: Int? = nil, purpose: Purpose, note: String? = nil) {
        self.carNumber = carNumber
        self.carCount = carCount
        self.purpose = purpose
        self.note = note
    }
}

/// 区間の遅延情報（api-contract 3.10）
public struct LegDisruption: Codable, Sendable, Hashable {
    public var status: OperationStatusKind
    public var delayMinutes: Int?
    public var summary: String

    public init(status: OperationStatusKind, delayMinutes: Int? = nil, summary: String) {
        self.status = status
        self.delayMinutes = delayMinutes
        self.summary = summary
    }
}

/// 列車の運行（停車駅一覧、api-contract 3.11）
public struct TrainRun: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var lineId: String
    public var trainTypeId: String
    public var destinationName: String
    public var stops: [StopPoint]

    public init(id: String, lineId: String, trainTypeId: String, destinationName: String, stops: [StopPoint]) {
        self.id = id
        self.lineId = lineId
        self.trainTypeId = trainTypeId
        self.destinationName = destinationName
        self.stops = stops
    }
}

/// 1 本前・1 本後
public enum AdjacentDirection: String, Codable, Sendable, Hashable {
    case previous
    case next
}
