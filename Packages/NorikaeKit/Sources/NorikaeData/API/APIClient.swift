import Domain
import Foundation

/// API の接続設定
public struct APIConfiguration: Sendable {
    public var baseURL: URL
    public var timeout: TimeInterval
    public var appVersion: String

    public init(baseURL: URL, timeout: TimeInterval = 10, appVersion: String = "0") {
        self.baseURL = baseURL
        self.timeout = timeout
        self.appVersion = appVersion
    }
}

/// 1 回の API 呼び出し
public struct APIRequest: Sendable {
    public enum Method: String, Sendable {
        case get = "GET", post = "POST", put = "PUT", delete = "DELETE"
    }

    public var method: Method
    public var path: String
    public var queryItems: [URLQueryItem]
    public var body: Data?
    public var requiresAuth: Bool
    /// 登録・解除系に付ける（backend-api-proposal 2 章）
    public var idempotencyKey: String?

    public init(method: Method, path: String, queryItems: [URLQueryItem] = [], body: Data? = nil, requiresAuth: Bool = true, idempotencyKey: String? = nil) {
        self.method = method
        self.path = path
        self.queryItems = queryItems
        self.body = body
        self.requiresAuth = requiresAuth
        self.idempotencyKey = idempotencyKey
    }
}

/// 認証トークン
///
/// 応答は `{ installationId, accessToken, refreshToken, expiresIn, tokenType }`（openapi.json）。使う項目だけを持つ。
public struct AuthTokens: Codable, Sendable, Hashable {
    public var accessToken: String
    public var refreshToken: String

    public init(accessToken: String, refreshToken: String) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
    }
}

/// API クライアント
///
/// - 匿名インストール登録とトークン更新を内部で行い、Repository には出さない（api-contract 6 章）
/// - `AUTHENTICATION_REQUIRED` のときはトークンを更新して 1 回だけ再送し、失敗したらインストール登録からやり直す（2.3）
public actor APIClient {
    private let configuration: APIConfiguration
    private let session: URLSession
    private let tokenStore: any TokenStoring
    private var tokens: AuthTokens?
    private var didLoadTokens = false

    public init(configuration: APIConfiguration, tokenStore: any TokenStoring, session: URLSession = .shared) {
        self.configuration = configuration
        self.tokenStore = tokenStore
        self.session = session
    }

    /// 本文を型に読む。`{ meta, data }` の形ならメタデータも返す
    public func send<T: Decodable & Sendable>(_ request: APIRequest, as type: T.Type) async throws -> (value: T, meta: ResponseMeta?) {
        let data = try await sendRaw(request)
        return try Self.decodeFlexible(T.self, from: data)
    }

    /// 本文を読まない呼び出し（登録・解除）
    public func sendWithoutResponse(_ request: APIRequest) async throws {
        _ = try await sendRaw(request)
    }

    // MARK: - 内部

    private func sendRaw(_ request: APIRequest) async throws -> Data {
        do {
            return try await perform(request, retryingAuthentication: true)
        } catch {
            throw AppError.wrap(error)
        }
    }

    private func perform(_ request: APIRequest, retryingAuthentication: Bool) async throws -> Data {
        let accessToken = request.requiresAuth ? try await validAccessToken() : nil
        let (data, response) = try await session.data(for: makeURLRequest(request, accessToken: accessToken))
        guard let http = response as? HTTPURLResponse else { throw AppError.network }
        if (200..<300).contains(http.statusCode) { return data }

        let apiError = (try? NorikaeJSON.makeDecoder().decode(ErrorEnvelope.self, from: data))?.error
        if request.requiresAuth, retryingAuthentication, http.statusCode == 401 || apiError?.code == .authenticationRequired {
            try await recoverAuthentication()
            return try await perform(request, retryingAuthentication: false)
        }
        if let apiError { throw apiError }
        throw AppError.network
    }

    private func makeURLRequest(_ request: APIRequest, accessToken: String?) throws -> URLRequest {
        var components = URLComponents(url: configuration.baseURL.appending(path: request.path), resolvingAgainstBaseURL: false)
        if !request.queryItems.isEmpty { components?.queryItems = request.queryItems }
        guard let url = components?.url else { throw AppError.unexpected("URL を作れません: \(request.path)") }
        var urlRequest = URLRequest(url: url, timeoutInterval: configuration.timeout)
        urlRequest.httpMethod = request.method.rawValue
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        urlRequest.setValue("gzip, br", forHTTPHeaderField: "Accept-Encoding")
        if let body = request.body {
            urlRequest.httpBody = body
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let accessToken { urlRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization") }
        if let key = request.idempotencyKey { urlRequest.setValue(key, forHTTPHeaderField: "Idempotency-Key") }
        return urlRequest
    }

    private func validAccessToken() async throws -> String {
        if !didLoadTokens {
            tokens = tokenStore.load()
            didLoadTokens = true
        }
        if let tokens { return tokens.accessToken }
        return try await registerInstallation().accessToken
    }

    /// トークンを更新し、失敗したらインストール登録からやり直す
    private func recoverAuthentication() async throws {
        if let refreshToken = tokens?.refreshToken {
            do {
                let body = try NorikaeJSON.makeEncoder().encode(["refreshToken": refreshToken])
                let data = try await perform(APIRequest(method: .post, path: "v1/auth/refresh", body: body, requiresAuth: false), retryingAuthentication: false)
                let refreshed = try Self.decodeFlexible(AuthTokens.self, from: data).value
                store(refreshed)
                return
            } catch {
                // 更新に失敗したら登録し直す
            }
        }
        _ = try await registerInstallation()
    }

    private func registerInstallation() async throws -> AuthTokens {
        // 本文なし（openapi.json の POST /v1/installations）
        let data = try await perform(APIRequest(method: .post, path: "v1/installations", requiresAuth: false), retryingAuthentication: false)
        let registered = try Self.decodeFlexible(AuthTokens.self, from: data).value
        store(registered)
        return registered
    }

    private func store(_ newTokens: AuthTokens?) {
        tokens = newTokens
        tokenStore.save(newTokens)
    }

    /// `{ meta, data }` の形と、本体だけの形の両方を読む（エンドポイントごとの形は OpenAPI の確定待ち）
    static func decodeFlexible<T: Decodable & Sendable>(_ type: T.Type, from data: Data) throws -> (value: T, meta: ResponseMeta?) {
        let decoder = NorikaeJSON.makeDecoder()
        if let envelope = try? decoder.decode(Envelope<T>.self, from: data) {
            return (envelope.data, envelope.meta)
        }
        return (try decoder.decode(T.self, from: data), nil)
    }
}

/// 認証トークンの保存先（Keychain）
public protocol TokenStoring: Sendable {
    func load() -> AuthTokens?
    func save(_ tokens: AuthTokens?)
}
