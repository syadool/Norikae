import Foundation

/// 運行状況の種類（api-contract 3.13）
public enum OperationStatusKind: String, Codable, Sendable, Hashable, CaseIterable {
    case normal
    case delayed
    case suspended
    case partial
    case other
    /// 運行情報を確認できない。「平常」ではない
    case unknown

    /// 未知の値は `other`（`summary` をそのまま出す）として扱う
    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = OperationStatusKind(rawValue: raw) ?? .other
    }

    /// 異常があるか（一覧でマイ路線を目立たせる判定などに使う）
    public var isDisrupted: Bool {
        switch self {
        case .delayed, .suspended, .partial: true
        case .normal, .other, .unknown: false
        }
    }
}

/// 運行情報（api-contract 3.13）
public struct OperationStatus: Codable, Sendable, Hashable, Identifiable {
    public var lineId: String
    public var status: OperationStatusKind
    public var summary: String
    public var cause: String?
    public var occurredAt: Date?
    public var outlook: String?
    public var hasTransferTransport: Bool?
    public var asOf: Date

    public var id: String { lineId }

    public init(
        lineId: String, status: OperationStatusKind, summary: String, cause: String? = nil, occurredAt: Date? = nil,
        outlook: String? = nil, hasTransferTransport: Bool? = nil, asOf: Date
    ) {
        self.lineId = lineId
        self.status = status
        self.summary = summary
        self.cause = cause
        self.occurredAt = occurredAt
        self.outlook = outlook
        self.hasTransferTransport = hasTransferTransport
        self.asOf = asOf
    }
}

/// 運行情報の一覧（API-06）
public struct OperationStatusList: Sendable, Hashable {
    public var meta: ResponseMeta
    public var statuses: [OperationStatus]

    public init(meta: ResponseMeta, statuses: [OperationStatus]) {
        self.meta = meta
        self.statuses = statuses
    }
}

/// 運行情報の詳細（API-07）
public struct OperationStatusDetail: Sendable, Hashable {
    public var meta: ResponseMeta
    public var status: OperationStatus

    public init(meta: ResponseMeta, status: OperationStatus) {
        self.meta = meta
        self.status = status
    }
}
