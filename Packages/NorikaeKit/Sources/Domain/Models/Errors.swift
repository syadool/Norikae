import Foundation

/// API のエラーコード（api-contract 2.3）
public enum APIErrorCode: Hashable, Sendable {
    case invalidRequest
    case stationNotFound
    case routeNotFound
    case featureUnavailable
    case routeContextExpired
    case routeContextMismatch
    case authenticationRequired
    case attestationFailed
    case rateLimited
    case providerQuotaExceeded
    case providerUnavailable
    case internalError
    /// 表にないコード。`retryable` に従って汎用のエラー表示にする
    case unknown(String)

    public init(rawValue: String) {
        switch rawValue {
        case "INVALID_REQUEST": self = .invalidRequest
        case "STATION_NOT_FOUND": self = .stationNotFound
        case "ROUTE_NOT_FOUND": self = .routeNotFound
        case "FEATURE_UNAVAILABLE": self = .featureUnavailable
        case "ROUTE_CONTEXT_EXPIRED": self = .routeContextExpired
        case "ROUTE_CONTEXT_MISMATCH": self = .routeContextMismatch
        case "AUTHENTICATION_REQUIRED": self = .authenticationRequired
        case "ATTESTATION_FAILED": self = .attestationFailed
        case "RATE_LIMITED": self = .rateLimited
        case "PROVIDER_QUOTA_EXCEEDED": self = .providerQuotaExceeded
        case "PROVIDER_UNAVAILABLE": self = .providerUnavailable
        case "INTERNAL_ERROR": self = .internalError
        default: self = .unknown(rawValue)
        }
    }
}

/// API のエラー本文
public struct APIError: Error, Sendable, Hashable, Codable {
    public var code: APIErrorCode
    public var rawCode: String
    public var message: String
    public var retryable: Bool

    public init(code: String, message: String, retryable: Bool) {
        self.rawCode = code
        self.code = APIErrorCode(rawValue: code)
        self.message = message
        self.retryable = retryable
    }

    private enum CodingKeys: String, CodingKey {
        case code, message, retryable
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try container.decode(String.self, forKey: .code)
        self.init(
            code: raw,
            message: try container.decode(String.self, forKey: .message),
            retryable: try container.decodeIfPresent(Bool.self, forKey: .retryable) ?? false
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(rawCode, forKey: .code)
        try container.encode(message, forKey: .message)
        try container.encode(retryable, forKey: .retryable)
    }
}

/// アプリ内で扱うエラー
public enum AppError: Error, Sendable, Hashable {
    /// API が返したエラー
    case api(APIError)
    /// 通信できない（オフライン）
    case offline
    /// 通信に失敗した（タイムアウトなど）
    case network
    /// 応答を読めなかった
    case decoding
    /// `routeContext` の期限切れから再検索したが、同じ経路が見つからなかった（api-contract 4.2）
    case routeNoLongerAvailable(RouteSearchResult)
    /// その他
    case unexpected(String)

    public var apiCode: APIErrorCode? {
        if case .api(let error) = self { return error.code }
        return nil
    }

    /// 任意のエラーを `AppError` に寄せる
    public static func wrap(_ error: any Error) -> AppError {
        if let appError = error as? AppError { return appError }
        if let apiError = error as? APIError { return .api(apiError) }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff:
                return .offline
            default:
                return .network
            }
        }
        if error is DecodingError { return .decoding }
        return .unexpected(String(describing: error))
    }
}
