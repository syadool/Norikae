import Domain
import Foundation
@testable import NorikaeData
import Testing

/// 契約テスト（frontend.md 12.1）：api-contract 7 章の場面を fixture でデコードできること
///
/// fixture は OpenAPI（正本）が確定するまでの仮のもの。確定したらバックエンドと共有する fixture に置き換える。
enum FixtureLoader {
    static func data(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }
}

@Suite("契約：経路検索（API-01）")
struct RouteSearchContractTests {
    @Test("条件付き項目・警告を含む応答を読める（data は経路の配列）")
    func standard() throws {
        let envelope = try NorikaeJSON.makeDecoder().decode(Envelope<[Route]>.self, from: FixtureLoader.data("route-search-standard"))
        let routes = envelope.data
        #expect(routes.count == 2)
        #expect(envelope.meta.attributions.first?.licenseUrl == "https://example.com/license")

        let r1 = routes[0]
        #expect(r1.legs.count == 3)
        #expect(r1.trainLegs.first?.boardingPosition?.purpose == .transfer)
        #expect(r1.trainLegs.last?.trainRunId == nil)
        #expect(r1.trainLegs.last?.from.platform == nil)
        #expect(r1.transfers.first?.walkMinutes == 2)
        #expect(r1.fare.display(preferred: .ic) == .amount(684, kind: .ic, isPreferredKind: true))

        let r2 = routes[1]
        #expect(r2.fare.display(preferred: .ic) == .estimated(920))
        #expect(r2.trainLegs.first?.delayMinutes == 3)
        #expect(r2.availability == .partial)
        #expect(r2.warnings(forLegAt: 1).count == 1)
        #expect(r2.routeLevelWarnings.first?.code == "SOMETHING_NEW")

    }

    @Test("記号・略称・色がない路線（null のキーも読める）")
    func lineWithoutSymbol() throws {
        let includes = try NorikaeJSON.makeDecoder().decode(ReferenceIncludes.self, from: FixtureLoader.data("includes-no-symbol-line"))
        let line = try #require(includes.lines?.first)
        #expect(line.symbol == nil && line.displayCode == nil && line.color == nil)
        #expect(line.label == "サンプル線")
    }

    @Test("終電で日付をまたぐ経路：実際の日時で表し、運行日は別に持つ")
    func overnight() throws {
        let envelope = try NorikaeJSON.makeDecoder().decode(Envelope<[Route]>.self, from: FixtureLoader.data("route-search-overnight"))
        #expect(envelope.meta.partialResult)
        #expect(envelope.meta.isStale)
        let route = try #require(envelope.data.first)
        #expect(route.arrivalTime.timeIntervalSince(route.departureTime) == 39 * 60)
        #expect(route.trainLegs.first?.to.serviceDate.rawValue == "2026-09-26")
        #expect(route.fare.display(preferred: .ic) == .unavailable)
    }
}

@Suite("契約：駅マスタの差分（API-08）")
struct MasterDataContractTests {
    @Test("upsert と delete（統合・廃止）をアプリの形に変換する")
    func changes() throws {
        let envelope = try NorikaeJSON.makeDecoder().decode(Envelope<MasterDataChangesPayload>.self, from: FixtureLoader.data("master-data-changes"))
        let changes = envelope.data.asChanges
        #expect(changes.version == 12)
        #expect(changes.stations?.map(\.id) == ["jp.station.new-a"])
        let migration = StationMigration(changes: changes)
        #expect(migration.replacements == ["jp.station.old-a": "jp.station.new-a"])
        #expect(migration.removedWithoutReplacement == ["jp.station.gone"])
        #expect(migration.lineReplacements == ["jp.line.old": "jp.line.new"])
    }
}

@Suite("契約：Live Activity の登録（API-09）")
struct RegistrationContractTests {
    @Test("本文は閉じたスキーマ：activityId を含めず、区間は from / to の入れ子")
    func body() throws {
        let route = try NorikaeJSON.makeDecoder().decode(Envelope<[Route]>.self, from: FixtureLoader.data("route-search-standard")).data[0]
        let registration = LiveActivityRegistration(activityId: "activity-1", pushToken: "abcd", route: route)
        let data = try NorikaeJSON.makeEncoder().encode(RemoteLiveActivityRegistrationRepository.RegistrationBody(registration))
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(object.keys) == ["pushToken", "routeContext", "legs", "expiresAt"])
        let legs = try #require(object["legs"] as? [[String: Any]])
        #expect(legs.count == 2)
        #expect(Set(legs[0].keys) == ["lineId", "trainRunId", "serviceDate", "from", "to"])
        // trainRunId がない区間はキーごと出さない
        #expect(Set(legs[1].keys) == ["lineId", "serviceDate", "from", "to"])
        let from = try #require(legs[0]["from"] as? [String: Any])
        #expect(Set(from.keys) == ["stationId", "scheduledTime"])
        // 到着予定時刻の 1 時間後
        #expect(object["expiresAt"] as? String == "2026-09-26T09:52:00+09:00")
    }
}

@Suite("契約：エラー（api-contract 2.3）")
struct ErrorContractTests {
    @Test("コードを読み分け、表にないコードは unknown として retryable に従う")
    func errors() throws {
        let list = try NorikaeJSON.makeDecoder().decode([ErrorEnvelope].self, from: FixtureLoader.data("errors"))
        #expect(list.map(\.error.code) == [.featureUnavailable, .routeContextExpired, .providerUnavailable, .unknown("NEW_CODE_IN_V1")])
        #expect(list[3].error.retryable)
    }
}

@Suite("契約：提供状況・運行情報・時刻表")
struct OtherContractTests {
    @Test("capabilities：未知の機能名・値があっても読める（値は非対応として扱う）")
    func capabilities() throws {
        let snapshot = try NorikaeJSON.makeDecoder().decode(CapabilitySnapshot.self, from: FixtureLoader.data("capabilities"))
        #expect(snapshot.isSupported(.timetable, lineId: "jp.line.tokyo-metro.ginza"))
        #expect(!snapshot.isSupported(.tripUpdates, lineId: "jp.line.tokyo-metro.ginza"))
        #expect(snapshot.lines.first?.features["futureFeature"] == .unavailable)
        #expect(!snapshot.isSupported(.viaStations, region: .kansai))
    }

    @Test("運行情報：unknown を平常と区別して読める")
    func statuses() throws {
        let envelope = try NorikaeJSON.makeDecoder().decode(Envelope<[OperationStatus]>.self, from: FixtureLoader.data("operation-statuses"))
        #expect(envelope.data.map(\.status) == [.delayed, .unknown])
        #expect(envelope.data[0].hasTransferTransport == false)
        #expect(envelope.data[1].cause == nil)
    }

    @Test("時刻表：深夜 0 時台の列車も実際の日時")
    func timetable() throws {
        let envelope = try NorikaeJSON.makeDecoder().decode(Envelope<Timetable>.self, from: FixtureLoader.data("timetable"))
        #expect(envelope.data.dayType == .saturday)
        #expect(envelope.data.departures.count == 2)
        #expect(envelope.data.departures[0].isOriginStation)
        #expect(ServiceDate.operatingDay(containing: envelope.data.departures[1].departureTime).rawValue == "2026-09-26")
    }
}

@Suite("契約：Live Activity の ContentState（api-contract 5.3）")
struct ContentStateContractTests {
    private struct Push: Decodable {
        struct APS: Decodable {
            var event: String
            var contentState: LiveRouteState
            enum CodingKeys: String, CodingKey {
                case event
                case contentState = "content-state"
            }
        }
        var aps: APS
    }

    @Test("ActivityKit と同じ既定の JSONDecoder で読める")
    func decodesWithDefaultDecoder() throws {
        let push = try JSONDecoder().decode(Push.self, from: FixtureLoader.data("content-state-push"))
        let state = push.aps.contentState
        #expect(push.aps.event == "update")
        #expect(state.legs.first?.estimatedDeparture == 1790378400)
        #expect(state.legs.first?.isCancelled == false)
        #expect(state.updatedAt == 1790378040)
    }

    @Test("書き出したキーが契約の例と一致する（端末だけの localNotice は nil なら出さない）")
    func encodesSameKeys() throws {
        let data = try FixtureLoader.data("content-state-push")
        let push = try JSONDecoder().decode(Push.self, from: data)
        let encoded = try JSONEncoder().encode(push.aps.contentState)
        let object = try #require(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let original = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let contentState = try #require((original["aps"] as? [String: Any])?["content-state"] as? [String: Any])
        #expect(Set(object.keys) == Set(contentState.keys))
        let encodedLeg = try #require((object["legs"] as? [[String: Any]])?.first)
        let originalLeg = try #require((contentState["legs"] as? [[String: Any]])?.first)
        #expect(Set(encodedLeg.keys) == Set(originalLeg.keys))
    }
}

// MARK: - API クライアント

/// URLSession の応答を差し替える
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) -> (Int, Data))?
    nonisolated(unsafe) static var requests: [URLRequest] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requests.append(request)
        let (status, data) = Self.handler?(request) ?? (500, Data())
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class MemoryTokenStore: TokenStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var tokens: AuthTokens?

    init(_ tokens: AuthTokens? = nil) {
        self.tokens = tokens
    }

    func load() -> AuthTokens? { lock.withLock { tokens } }
    func save(_ tokens: AuthTokens?) { lock.withLock { self.tokens = tokens } }
}

@Suite("API クライアント", .serialized)
struct APIClientTests {
    private func makeClient(tokens: AuthTokens? = nil) -> (APIClient, MemoryTokenStore) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let store = MemoryTokenStore(tokens)
        let client = APIClient(
            configuration: APIConfiguration(baseURL: URL(string: "https://api.example.com")!),
            tokenStore: store, session: URLSession(configuration: configuration)
        )
        return (client, store)
    }

    @Test("初回は匿名インストール登録をしてから呼ぶ")
    func registersInstallation() async throws {
        let search = try FixtureLoader.data("route-search-standard")
        StubURLProtocol.requests = []
        StubURLProtocol.handler = { request in
            switch request.url?.path ?? "" {
            case "/v1/installations": (200, Data(#"{"accessToken":"a1","refreshToken":"r1"}"#.utf8))
            case "/v1/routes/search": (200, search)
            default: (404, Data())
            }
        }
        let (client, store) = makeClient()
        let result = try await RemoteRouteRepository(client: client).searchRoutes(
            RouteSearchQuery(fromStationId: "jp.station.ikebukuro", toStationId: "jp.station.yokohama", dateTime: Date())
        )
        #expect(result.routes.count == 2)
        #expect(store.load()?.accessToken == "a1")
        #expect(StubURLProtocol.requests.last?.value(forHTTPHeaderField: "Authorization") == "Bearer a1")
    }

    @Test("AUTHENTICATION_REQUIRED ならトークンを更新して 1 回だけ再送する")
    func refreshesOnce() async throws {
        let search = try FixtureLoader.data("route-search-standard")
        StubURLProtocol.requests = []
        StubURLProtocol.handler = { request in
            let auth = request.value(forHTTPHeaderField: "Authorization")
            switch request.url?.path ?? "" {
            case "/v1/auth/refresh": return (200, Data(#"{"accessToken":"a2","refreshToken":"r2"}"#.utf8))
            case "/v1/routes/search" where auth == "Bearer a2": return (200, search)
            case "/v1/routes/search":
                return (401, Data(#"{"error":{"code":"AUTHENTICATION_REQUIRED","message":"期限切れ","retryable":true}}"#.utf8))
            default: return (404, Data())
            }
        }
        let (client, store) = makeClient(tokens: AuthTokens(accessToken: "old", refreshToken: "r1"))
        let result = try await RemoteRouteRepository(client: client).searchRoutes(
            RouteSearchQuery(fromStationId: "a", toStationId: "b", dateTime: Date())
        )
        #expect(result.routes.count == 2)
        #expect(store.load()?.accessToken == "a2")
        #expect(StubURLProtocol.requests.filter { $0.url?.path == "/v1/routes/search" }.count == 2)
    }

    @Test("エラー本文を APIError として返す")
    func errorBody() async throws {
        StubURLProtocol.handler = { _ in
            (422, Data(#"{"error":{"code":"FEATURE_UNAVAILABLE","message":"この区間・条件には対応していません","retryable":false}}"#.utf8))
        }
        let (client, _) = makeClient(tokens: AuthTokens(accessToken: "a", refreshToken: "r"))
        do {
            _ = try await RemoteRouteRepository(client: client).searchRoutes(RouteSearchQuery(fromStationId: "a", toStationId: "b", dateTime: Date()))
            Issue.record("エラーになるはず")
        } catch {
            #expect(AppError.wrap(error).apiCode == .featureUnavailable)
        }
    }
}
