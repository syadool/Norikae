import Foundation

/// 運賃（api-contract 3.8）
public struct Fare: Codable, Sendable, Hashable {
    public enum FareType: String, Codable, Sendable, Hashable {
        case exact
        case estimated
        case unavailable

        public init(from decoder: any Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = FareType(rawValue: raw) ?? .unavailable
        }
    }

    public var fareType: FareType
    public var icTotal: Int?
    public var ticketTotal: Int?
    public var estimatedTotal: Int?
    public var expressTotal: Int?
    public var breakdown: [FareItem]?

    public init(fareType: FareType, icTotal: Int? = nil, ticketTotal: Int? = nil, estimatedTotal: Int? = nil, expressTotal: Int? = nil, breakdown: [FareItem]? = nil) {
        self.fareType = fareType
        self.icTotal = icTotal
        self.ticketTotal = ticketTotal
        self.estimatedTotal = estimatedTotal
        self.expressTotal = expressTotal
        self.breakdown = breakdown
    }

    public static let unavailable = Fare(fareType: .unavailable)
}

/// 運賃の内訳。項目はバックエンドと未確定のため、すべて任意にしている
public struct FareItem: Codable, Sendable, Hashable {
    public var operatorId: String?
    public var name: String?
    public var icFare: Int?
    public var ticketFare: Int?

    public init(operatorId: String? = nil, name: String? = nil, icFare: Int? = nil, ticketFare: Int? = nil) {
        self.operatorId = operatorId
        self.name = name
        self.icFare = icFare
        self.ticketFare = ticketFare
    }
}

/// 利用者が選ぶ運賃の種別（FR-CND-05）
public enum FareKind: String, Codable, Sendable, Hashable, CaseIterable {
    case ic
    case ticket

    public var other: FareKind { self == .ic ? .ticket : .ic }
}

/// 表示する運賃（api-contract 3.8 の表示ルール）
public enum FareDisplay: Sendable, Hashable {
    /// 確定運賃。`kind` が設定と違うときは種別を併記する
    case amount(Int, kind: FareKind, isPreferredKind: Bool)
    /// 概算（「約◯円」）
    case estimated(Int)
    /// 運賃不明
    case unavailable

    /// 「安」の判定に使う、表示運賃の種別
    public enum ComparisonKind: Hashable, Sendable {
        case ic
        case ticket
        case estimated
    }

    public var comparisonKind: ComparisonKind? {
        switch self {
        case .amount(_, let kind, _): kind == .ic ? .ic : .ticket
        case .estimated: .estimated
        case .unavailable: nil
        }
    }

    public var value: Int? {
        switch self {
        case .amount(let value, _, _), .estimated(let value): value
        case .unavailable: nil
        }
    }
}

extension Fare {
    /// 設定した種別に対する表示運賃を決める
    ///
    /// 1. 設定した種別の運賃があればその金額
    /// 2. もう一方の種別があれば、その金額に種別を併記
    /// 3. 概算だけがあれば「約◯円」
    /// 4. いずれもなければ「運賃不明」
    ///
    /// 特急料金・新幹線料金（`expressTotal`）が分かっている場合は合計に含める。
    public func display(preferred kind: FareKind) -> FareDisplay {
        let express = expressTotal ?? 0
        if fareType != .unavailable {
            if let preferred = total(for: kind) {
                return .amount(preferred + express, kind: kind, isPreferredKind: true)
            }
            if let other = total(for: kind.other) {
                return .amount(other + express, kind: kind.other, isPreferredKind: false)
            }
        }
        if let estimatedTotal {
            return .estimated(estimatedTotal + express)
        }
        return .unavailable
    }

    private func total(for kind: FareKind) -> Int? {
        switch kind {
        case .ic: icTotal
        case .ticket: ticketTotal
        }
    }
}
