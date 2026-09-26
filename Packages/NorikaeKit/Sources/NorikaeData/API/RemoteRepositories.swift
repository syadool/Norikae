import Domain
import Foundation

// 本物の API 実装（backend-api-proposal 4 章のエンドポイント）。
//
// 応答の形は backend/openapi.json（v0.1.0）に合わせている。すべて `{ meta, data }` の形。
// - API-01: data = Route[]（api-contract 4 章の includes が付く `{ routes, includes }` の形も読める）
// - API-02: data = Route
// - API-04: data = LineDirection[]
// - API-06: data = OperationStatus[]
// - API-08: data = { version, changes: [{ version, entity, id, operation, value?, replacedById? }] }
// - capabilities: data = { lines, regions }
// - attributions: data = Attribution[]

private struct SearchPayload: Decodable, Sendable {
    var routes: [Route]
    var includes: ReferenceIncludes?

    init(from decoder: any Decoder) throws {
        // data が経路の配列そのもの（OpenAPI）と、{ routes, includes } の両方を読む
        if let routes = try? [Route](from: decoder) {
            self.routes = routes
            includes = nil
        } else {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            routes = try container.decode([Route].self, forKey: .routes)
            includes = try container.decodeIfPresent(ReferenceIncludes.self, forKey: .includes)
        }
    }

    private enum CodingKeys: String, CodingKey { case routes, includes }
}

private struct AdjacentPayload: Decodable, Sendable {
    var route: Route
    var includes: ReferenceIncludes?

    init(from decoder: any Decoder) throws {
        // { route, includes } と Route そのものの両方を読む
        if let container = try? decoder.container(keyedBy: CodingKeys.self), container.contains(.route) {
            route = try container.decode(Route.self, forKey: .route)
            includes = try container.decodeIfPresent(ReferenceIncludes.self, forKey: .includes)
        } else {
            route = try Route(from: decoder)
            includes = nil
        }
    }

    private enum CodingKeys: String, CodingKey { case route, includes }
}

private func missingMeta() -> ResponseMeta { ResponseMeta(asOf: Date()) }

public struct RemoteRouteRepository: RouteRepository {
    private let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    public func searchRoutes(_ query: RouteSearchQuery) async throws -> RouteSearchResult {
        let body = try NorikaeJSON.makeEncoder().encode(query)
        let (payload, meta) = try await client.send(APIRequest(method: .post, path: "v1/routes/search", body: body), as: SearchPayload.self)
        return RouteSearchResult(meta: meta ?? missingMeta(), routes: payload.routes, includes: payload.includes)
    }

    public func adjacentRoute(context: RouteContext, direction: AdjacentDirection) async throws -> AdjacentRouteResult {
        struct Body: Encodable { var routeContext: RouteContext; var direction: AdjacentDirection }
        let body = try NorikaeJSON.makeEncoder().encode(Body(routeContext: context, direction: direction))
        let (payload, meta) = try await client.send(APIRequest(method: .post, path: "v1/routes/adjacent", body: body), as: AdjacentPayload.self)
        return AdjacentRouteResult(meta: meta, route: payload.route, includes: payload.includes)
    }

    public func trainRun(id: TrainRun.ID, serviceDate: ServiceDate) async throws -> TrainRunResult {
        let request = APIRequest(
            method: .get, path: "v1/train-runs/\(id.urlPathEscaped)",
            queryItems: [URLQueryItem(name: "serviceDate", value: serviceDate.rawValue)]
        )
        let (run, meta) = try await client.send(request, as: TrainRun.self)
        return TrainRunResult(meta: meta ?? missingMeta(), trainRun: run)
    }
}

public struct RemoteTimetableRepository: TimetableRepository {
    private let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    public func directions(stationID: Station.ID) async throws -> [LineDirection] {
        try await client.send(APIRequest(method: .get, path: "v1/stations/\(stationID.urlPathEscaped)/directions"), as: [LineDirection].self).value
    }

    public func timetable(stationID: Station.ID, lineID: Line.ID, directionID: String, dayType: DayType) async throws -> TimetableResult {
        let request = APIRequest(method: .get, path: "v1/timetables", queryItems: [
            URLQueryItem(name: "stationId", value: stationID),
            URLQueryItem(name: "lineId", value: lineID),
            URLQueryItem(name: "directionId", value: directionID),
            URLQueryItem(name: "dayType", value: dayType.rawValue),
        ])
        let (timetable, meta) = try await client.send(request, as: Timetable.self)
        return TimetableResult(meta: meta ?? ResponseMeta(asOf: timetable.asOf), timetable: timetable)
    }
}

public struct RemoteOperationStatusRepository: OperationStatusRepository {
    private let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    public func statuses(region: Region) async throws -> OperationStatusList {
        let request = APIRequest(method: .get, path: "v1/operation-statuses", queryItems: [URLQueryItem(name: "region", value: region.rawValue)])
        let (statuses, meta) = try await client.send(request, as: [OperationStatus].self)
        return OperationStatusList(meta: meta ?? missingMeta(), statuses: statuses)
    }

    public func status(lineID: Line.ID) async throws -> OperationStatusDetail {
        let (status, meta) = try await client.send(APIRequest(method: .get, path: "v1/operation-statuses/\(lineID.urlPathEscaped)"), as: OperationStatus.self)
        return OperationStatusDetail(meta: meta ?? ResponseMeta(asOf: status.asOf), status: status)
    }
}

public struct RemoteLiveActivityRegistrationRepository: LiveActivityRegistrationRepository {
    private let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    /// 本文は閉じたスキーマ。activityId はパスに入れ、本文には含めない
    struct RegistrationBody: Encodable {
        var pushToken: String
        var routeContext: RouteContext
        var legs: [LiveActivityRegistration.MonitoredLeg]
        var expiresAt: Date

        init(_ registration: LiveActivityRegistration) {
            pushToken = registration.pushToken
            routeContext = registration.routeContext
            legs = registration.legs
            expiresAt = registration.expiresAt
        }
    }

    public func register(_ registration: LiveActivityRegistration) async throws {
        let body = try NorikaeJSON.makeEncoder().encode(RegistrationBody(registration))
        try await client.sendWithoutResponse(APIRequest(
            method: .put, path: "v1/live-activities/\(registration.activityId.urlPathEscaped)", body: body,
            idempotencyKey: "\(registration.activityId)-\(registration.pushToken.suffix(16))-\(registration.routeContext.rawValue.suffix(16))"
        ))
    }

    public func unregister(activityID: String) async throws {
        try await client.sendWithoutResponse(APIRequest(
            method: .delete, path: "v1/live-activities/\(activityID.urlPathEscaped)", idempotencyKey: "delete-\(activityID)"
        ))
    }
}

/// 駅マスタの差分（API-08）
public struct RemoteMasterDataSource: MasterDataSource {
    private let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    public func changes(sinceVersion: Int) async throws -> MasterDataChanges {
        let request = APIRequest(method: .get, path: "v1/master-data/changes", queryItems: [URLQueryItem(name: "sinceVersion", value: String(sinceVersion))])
        return try await client.send(request, as: MasterDataChangesPayload.self).value.asChanges
    }
}

/// 提供状況（`GET /v1/capabilities`）の取得元
public struct RemoteCapabilitySource: CapabilitySource {
    private let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    private struct Payload: Decodable, Sendable {
        var lines: [LineCapability]
        var regions: [RegionCapability]?
    }

    public func fetch() async throws -> CapabilitySnapshot {
        let payload = try await client.send(APIRequest(method: .get, path: "v1/capabilities"), as: Payload.self).value
        return CapabilitySnapshot(lines: payload.lines, regions: payload.regions ?? [], fetchedAt: Date())
    }
}

/// 出典（`GET /v1/attributions`）の取得元
public struct RemoteAttributionSource: AttributionSource {
    private let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    public func fetch() async throws -> [Attribution] {
        try await client.send(APIRequest(method: .get, path: "v1/attributions"), as: [Attribution].self).value
    }
}

extension String {
    var urlPathEscaped: String {
        addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))) ?? self
    }
}
