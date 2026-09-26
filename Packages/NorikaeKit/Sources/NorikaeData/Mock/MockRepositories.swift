import Domain
import Foundation

/// 停車駅一覧の種を、経路と時刻表のモックで共有する
actor MockTrainRunRegistry {
    private var seeds: [String: MockRunSeed] = [:]

    func register(_ newSeeds: [String: MockRunSeed]) {
        seeds.merge(newSeeds) { _, new in new }
    }

    func seed(for id: String) -> MockRunSeed? {
        seeds[id]
    }
}

/// モックの経路 Repository（api-contract 7 章の場面を再現する）
public actor MockRouteRepository: RouteRepository {
    private let scenario: MockScenario
    private let catalog: Catalog
    private let registry: MockTrainRunRegistry
    private let latency: Duration
    /// 発行した routeContext → 経路と、発行したときの検索の回数
    private var issued: [RouteContext: (route: Route, generation: Int)] = [:]
    private var searchCount = 0

    public init(scenario: MockScenario = .standard, catalog: Catalog = MockData.catalog, latency: Duration = .milliseconds(400)) {
        self.scenario = scenario
        self.catalog = catalog
        self.registry = MockTrainRunRegistry()
        self.latency = latency
    }

    init(scenario: MockScenario, catalog: Catalog, registry: MockTrainRunRegistry, latency: Duration) {
        self.scenario = scenario
        self.catalog = catalog
        self.registry = registry
        self.latency = latency
    }

    var trainRunRegistry: MockTrainRunRegistry { registry }

    public func searchRoutes(_ query: RouteSearchQuery) async throws -> RouteSearchResult {
        try await Task.sleep(for: scenario == .slow ? .seconds(3) : latency)
        searchCount += 1
        try validate(query)

        var factory = MockRouteFactory(base: baseDate(for: query), catalog: catalog)
        let isSample = query.fromStationId == MockID.ikebukuro && query.toStationId == MockID.yokohama
        var routes: [Route]
        var meta = ResponseMeta(asOf: Date(), sources: ["mock"], attributions: [MockData.attributions[0]])
        var includes: ReferenceIncludes?

        if isSample {
            let sample = factory.ikebukuroToYokohama()
            switch scenario {
            case .threeRoutes:
                routes = Array(sample.prefix(3))
            case .wideSpread:
                let slow = factory.shifted(sample[3], byMinutes: 0, id: "r-slow")
                routes = [sample[0], stretch(slow, toMinutes: 125)]
            case .manyTransfers:
                routes = [sample[0], factory.threeTransfers(), sample[1]]
            case .missingOptional:
                routes = Array(sample.prefix(3)).map(Self.removingOptionalFields)
            case .noSymbolLine:
                routes = [sample[0], factory.noSymbolRoute(), sample[1]]
                includes = ReferenceIncludes(lines: [MockData.noSymbolLine])
            case .fareVariants:
                routes = Array(sample.prefix(4))
                routes[0].fare = Fare(fareType: .estimated, estimatedTotal: 840)
                routes[1].fare = Fare(fareType: .exact, icTotal: 684)
                routes[2].fare = .unavailable
                routes[3].fare = Fare(fareType: .exact, ticketTotal: 790)
            case .partialStale:
                meta.partialResult = true
                meta.isStale = true
                meta.asOf = Date().addingTimeInterval(-9 * 60)
                routes = Array(sample.prefix(3))
                routes[1].availability = .partial
                routes[1].warnings = [RouteWarning(code: "PARTIAL_DATA", message: "東横線の番線を取得できませんでした", legIndex: 2)]
                routes[2].availability = .stale
                routes[2].warnings = [RouteWarning(code: "STALE_DATA", message: "運行情報が古い可能性があります")]
            default:
                routes = sample
            }
        } else {
            routes = factory.generic(from: query.fromStationId, to: query.toStationId)
        }

        if query.searchType == .arrival {
            // 到着時刻の指定：指定時刻までに着く経路にそろえる
            let latestArrival = routes.map(\.arrivalTime).max() ?? query.dateTime
            let shift = Int((query.dateTime.timeIntervalSince(latestArrival) / 60).rounded(.down))
            routes = routes.map { factory.shifted($0, byMinutes: shift, id: $0.id) }
        }

        await registry.register(factory.runSeeds)
        for route in routes { issued[route.routeContext] = (route, searchCount) }
        return RouteSearchResult(meta: meta, routes: routes, includes: includes)
    }

    public func adjacentRoute(context: RouteContext, direction: AdjacentDirection) async throws -> AdjacentRouteResult {
        try await Task.sleep(for: latency)
        guard let entry = issued[context] else {
            // アプリを起動し直すなどで手元にない routeContext は、期限切れとして扱う
            throw APIError(code: "ROUTE_CONTEXT_EXPIRED", message: "経路の情報の有効期限が切れました", retryable: false)
        }
        if scenario == .contextExpired, entry.generation == 1 {
            throw APIError(code: "ROUTE_CONTEXT_EXPIRED", message: "経路の情報の有効期限が切れました", retryable: false)
        }
        var factory = MockRouteFactory(base: entry.route.departureTime, catalog: catalog)
        let minutes = direction == .next ? 8 : -8
        var adjacent: Route
        if scenario == .adjacentStructureChange, direction == .next, entry.route.trainLegs.count == 1,
           entry.route.originStationId == MockID.ikebukuro, entry.route.destinationStationId == MockID.yokohama {
            // 1 本後は渋谷で乗り換える経路になる（#18）
            var sampleFactory = MockRouteFactory(base: entry.route.departureTime.addingTimeInterval(-9 * 60), catalog: catalog)
            let viaShibuya = sampleFactory.ikebukuroToYokohama()[1]
            adjacent = sampleFactory.shifted(viaShibuya, byMinutes: 8, id: "adjacent-\(UUID().uuidString.prefix(6))")
            await registry.register(sampleFactory.runSeeds)
        } else {
            adjacent = factory.shifted(entry.route, byMinutes: minutes, id: "adjacent-\(UUID().uuidString.prefix(6))")
            await registry.register(factory.runSeeds)
        }
        issued[adjacent.routeContext] = (adjacent, searchCount + 1)
        return AdjacentRouteResult(meta: ResponseMeta(asOf: Date(), sources: ["mock"]), route: adjacent)
    }

    public func trainRun(id: TrainRun.ID, serviceDate: ServiceDate) async throws -> TrainRunResult {
        try await Task.sleep(for: latency)
        guard let seed = await registry.seed(for: id) else {
            throw APIError(code: "INVALID_REQUEST", message: "列車の情報が見つかりません", retryable: false)
        }
        return TrainRunResult(meta: ResponseMeta(asOf: Date(), sources: ["mock"], attributions: [MockData.attributions[0]]), trainRun: Self.buildRun(id: id, seed: seed))
    }

    /// 登録（API-09）を期限切れにするか（#17）。`MockLiveActivityRegistrationRepository` から使う
    func isExpired(_ context: RouteContext) -> Bool {
        guard let entry = issued[context] else { return true }
        return scenario == .contextExpired && entry.generation == 1
    }

    // MARK: - 内部

    private func validate(_ query: RouteSearchQuery) throws {
        switch scenario {
        case .retryableError:
            throw APIError(code: "PROVIDER_UNAVAILABLE", message: "経路データの提供元に接続できませんでした", retryable: true)
        case .nonRetryableError:
            throw APIError(code: "INVALID_REQUEST", message: "検索条件を確認してください", retryable: false)
        case .empty:
            throw APIError(code: "ROUTE_NOT_FOUND", message: "条件に合う経路が見つかりませんでした", retryable: false)
        case .featureUnavailable where !query.removableConditions.isEmpty:
            throw APIError(code: "FEATURE_UNAVAILABLE", message: "この区間・条件には対応していません", retryable: false)
        default:
            break
        }
        if query.fromStationId == query.toStationId {
            throw APIError(code: "INVALID_REQUEST", message: "出発駅と到着駅が同じです", retryable: false)
        }
        guard let from = catalog.station(query.fromStationId), catalog.station(query.toStationId) != nil else {
            throw APIError(code: "STATION_NOT_FOUND", message: "指定された駅が見つかりません", retryable: false)
        }
        // 関西圏は経由駅・始発終電に非対応（capabilities と合わせる）
        if from.region == .kansai, !query.removableConditions.isEmpty {
            throw APIError(code: "FEATURE_UNAVAILABLE", message: "この区間・条件には対応していません", retryable: false)
        }
    }

    private func baseDate(for query: RouteSearchQuery) -> Date {
        let calendar = JapanCalendar.calendar
        switch scenario == .overnight ? .lastTrain : query.searchType {
        case .departure:
            return query.dateTime
        case .arrival:
            return query.dateTime.addingTimeInterval(-75 * 60)
        case .firstTrain:
            return calendar.date(bySettingHour: 4, minute: 50, second: 0, of: query.dateTime) ?? query.dateTime
        case .lastTrain:
            // 23:40 発 → 日付をまたいで到着（#4）
            return calendar.date(bySettingHour: 23, minute: 40, second: 0, of: query.dateTime) ?? query.dateTime
        }
    }

    /// 所要時間を引き延ばす（#3）
    private func stretch(_ route: Route, toMinutes minutes: Int) -> Route {
        var copy = route
        let factor = Double(minutes) / Double(max(route.durationMinutes, 1))
        let start = route.departureTime
        func scale(_ point: StopPoint) -> StopPoint {
            var p = point
            p.scheduledTime = start.addingTimeInterval(point.scheduledTime.timeIntervalSince(start) * factor)
            p.estimatedTime = nil
            return p
        }
        copy.legs = route.legs.map { leg in
            guard case .train(var train) = leg else { return leg }
            train.from = scale(train.from)
            train.to = scale(train.to)
            train.trainTypeId = MockID.local
            return .train(train)
        }
        copy.arrivalTime = copy.trainLegs.last?.to.scheduledTime ?? route.arrivalTime
        copy.durationMinutes = minutes
        copy.fare = Fare(fareType: .exact, icTotal: 620, ticketTotal: 630)
        return copy
    }

    static func removingOptionalFields(_ route: Route) -> Route {
        var copy = route
        copy.legs = route.legs.map { leg in
            guard case .train(var train) = leg else { return leg }
            train.from.platform = nil
            train.to.platform = nil
            train.boardingPosition = nil
            return .train(train)
        }
        return copy
    }

    static func buildRun(id: String, seed: MockRunSeed) -> TrainRun {
        guard let sequence = MockData.lineSequences[seed.lineId], let anchor = sequence.firstIndex(of: seed.anchorStationId) else {
            return TrainRun(id: id, lineId: seed.lineId, trainTypeId: seed.trainTypeId, destinationName: seed.destinationName, stops: seed.fallbackStops)
        }
        let ordered = seed.forward ? sequence : sequence.reversed()
        let anchorIndex = seed.forward ? anchor : sequence.count - 1 - anchor
        let stops = ordered.enumerated().map { index, stationId in
            let time = seed.anchorTime.addingTimeInterval(Double(index - anchorIndex) * seed.minutesPerStop * 60)
            let rounded = Date(timeIntervalSince1970: (time.timeIntervalSince1970 / 60).rounded() * 60)
            return StopPoint(stationId: stationId, scheduledTime: rounded, serviceDate: ServiceDate.operatingDay(containing: rounded))
        }
        return TrainRun(id: id, lineId: seed.lineId, trainTypeId: seed.trainTypeId, destinationName: seed.destinationName, stops: stops)
    }
}

/// モックの時刻表 Repository
public actor MockTimetableRepository: TimetableRepository {
    private let catalog: Catalog
    private let capabilities: CapabilitySnapshot
    private let registry: MockTrainRunRegistry
    private let latency: Duration

    public init(catalog: Catalog = MockData.catalog, capabilities: CapabilitySnapshot = MockData.capabilities(now: Date()), latency: Duration = .milliseconds(300)) {
        self.init(catalog: catalog, capabilities: capabilities, registry: MockTrainRunRegistry(), latency: latency)
    }

    init(catalog: Catalog, capabilities: CapabilitySnapshot, registry: MockTrainRunRegistry, latency: Duration) {
        self.catalog = catalog
        self.capabilities = capabilities
        self.registry = registry
        self.latency = latency
    }

    public func directions(stationID: Station.ID) async throws -> [LineDirection] {
        try await Task.sleep(for: latency)
        guard let station = catalog.station(stationID) else {
            throw APIError(code: "STATION_NOT_FOUND", message: "指定された駅が見つかりません", retryable: false)
        }
        return station.lineIds.flatMap { lineId -> [LineDirection] in
            guard let sequence = MockData.lineSequences[lineId], let index = sequence.firstIndex(of: stationID) else {
                return [
                    LineDirection(lineId: lineId, directionId: "outbound", directionName: "下り"),
                    LineDirection(lineId: lineId, directionId: "inbound", directionName: "上り"),
                ]
            }
            var result: [LineDirection] = []
            if lineId == MockID.yamanote {
                return [
                    LineDirection(lineId: lineId, directionId: "outbound", directionName: "外回り（渋谷・品川方面）"),
                    LineDirection(lineId: lineId, directionId: "inbound", directionName: "内回り（上野・東京方面）"),
                ]
            }
            if index < sequence.count - 1 {
                result.append(LineDirection(lineId: lineId, directionId: "outbound", directionName: "\(name(sequence.last))方面"))
            }
            if index > 0 {
                result.append(LineDirection(lineId: lineId, directionId: "inbound", directionName: "\(name(sequence.first))方面"))
            }
            return result
        }
    }

    public func timetable(stationID: Station.ID, lineID: Line.ID, directionID: String, dayType: DayType) async throws -> TimetableResult {
        try await Task.sleep(for: latency)
        guard capabilities.isSupported(.timetable, lineId: lineID) else {
            throw APIError(code: "FEATURE_UNAVAILABLE", message: "この路線の時刻表には対応していません", retryable: false)
        }
        let now = Date()
        let serviceDate = ServiceDate.operatingDay(containing: now)
        let dayStart = serviceDate.startDate ?? now
        let sequence = MockData.lineSequences[lineID] ?? [stationID]
        let forward = directionID != "inbound"
        let ordered = forward ? sequence : sequence.reversed()
        let position = ordered.firstIndex(of: stationID) ?? 0
        let terminal = name(ordered.last)
        let shortTurn = name(ordered.dropLast().last)
        let fastType = lineID == MockID.fukutoshin ? MockID.express : MockID.rapid

        var entries: [TimetableEntry] = []
        var seeds: [String: MockRunSeed] = [:]
        var minute = 5 * 60 + (forward ? 2 : 5)
        var count = 0
        while minute <= 24 * 60 + 30 {
            let hour = minute / 60
            let peak = (7...9).contains(hour) || (17...19).contains(hour)
            let headway: Int
            switch dayType {
            case .weekday: headway = peak ? 4 : 8
            case .saturday: headway = 8
            case .holiday: headway = 10
            }
            let time = dayStart.addingTimeInterval(TimeInterval(minute * 60))
            let isFast = count % 3 == 2 && lineID != MockID.oedo
            let isShortTurn = count % 4 == 3 && ordered.count > 2
            let destination = "\(isShortTurn ? shortTurn : terminal)行"
            let runId = "mock-tt-\(lineID)-\(directionID)-\(minute)"
            entries.append(TimetableEntry(
                departureTime: time, trainTypeId: isFast ? fastType : MockID.localStop, destinationName: destination,
                platform: forward ? "1" : "2", isOriginStation: position == 0 || count % 5 == 0, trainRunId: runId
            ))
            seeds[runId] = MockRunSeed(
                lineId: lineID, trainTypeId: isFast ? fastType : MockID.localStop, destinationName: destination,
                anchorStationId: stationID, anchorTime: time, minutesPerStop: isFast ? 2.5 : 3.0,
                forward: forward, fallbackStops: [StopPoint(stationId: stationID, scheduledTime: time, serviceDate: serviceDate)]
            )
            minute += headway
            count += 1
        }
        await registry.register(seeds)

        let directionName = try await directions(stationID: stationID).first { $0.lineId == lineID && $0.directionId == directionID }?.directionName ?? ""
        let timetable = Timetable(
            stationId: stationID, lineId: lineID, directionId: directionID, directionName: directionName,
            dayType: dayType, departures: entries, asOf: now
        )
        return TimetableResult(meta: ResponseMeta(asOf: now, sources: ["mock"], attributions: MockData.attributions), timetable: timetable)
    }

    private func name(_ stationId: String?) -> String {
        stationId.flatMap { catalog.station($0)?.name } ?? ""
    }
}

/// モックの運行情報 Repository
public struct MockOperationStatusRepository: OperationStatusRepository {
    private let capabilities: CapabilitySnapshot
    private let latency: Duration

    public init(capabilities: CapabilitySnapshot = MockData.capabilities(now: Date()), latency: Duration = .milliseconds(300)) {
        self.capabilities = capabilities
        self.latency = latency
    }

    public func statuses(region: Region) async throws -> OperationStatusList {
        try await Task.sleep(for: latency)
        let now = Date()
        return OperationStatusList(
            meta: ResponseMeta(asOf: now, sources: ["mock"], attributions: [MockData.attributions[0]]),
            statuses: MockData.statuses(region: region, now: now, capabilities: capabilities)
        )
    }

    public func status(lineID: Line.ID) async throws -> OperationStatusDetail {
        try await Task.sleep(for: latency)
        let now = Date()
        let region = MockData.catalog.line(lineID)?.region ?? .kanto
        guard let status = MockData.statuses(region: region, now: now, capabilities: capabilities).first(where: { $0.lineId == lineID }) else {
            throw APIError(code: "INVALID_REQUEST", message: "路線が見つかりません", retryable: false)
        }
        return OperationStatusDetail(meta: ResponseMeta(asOf: now, sources: ["mock"], attributions: [MockData.attributions[0]]), status: status)
    }
}

/// モックの Live Activity 登録 Repository。呼び出しを記録する
public actor MockLiveActivityRegistrationRepository: LiveActivityRegistrationRepository {
    public private(set) var registrations: [LiveActivityRegistration] = []
    public private(set) var unregisteredIDs: [String] = []
    private let routes: MockRouteRepository?
    private let shouldFail: Bool

    public init(routes: MockRouteRepository? = nil, shouldFail: Bool = false) {
        self.routes = routes
        self.shouldFail = shouldFail
    }

    public func register(_ registration: LiveActivityRegistration) async throws {
        if shouldFail { throw AppError.offline }
        if let routes, await routes.isExpired(registration.routeContext) {
            throw APIError(code: "ROUTE_CONTEXT_EXPIRED", message: "経路の情報の有効期限が切れました", retryable: false)
        }
        registrations.append(registration)
    }

    public func unregister(activityID: String) async throws {
        if shouldFail { throw AppError.offline }
        unregisteredIDs.append(activityID)
    }
}

/// モックの提供状況・出典の取得元
public struct MockCapabilitySource: CapabilitySource {
    public init() {}
    public func fetch() async throws -> CapabilitySnapshot { MockData.capabilities(now: Date()) }
}

public struct MockAttributionSource: AttributionSource {
    public init() {}
    public func fetch() async throws -> [Attribution] { MockData.attributions }
}

/// モック一式をまとめて作る（停車駅一覧の種を、経路と時刻表で共有するため）
public struct MockRepositorySet: Sendable {
    public let routes: MockRouteRepository
    public let timetables: MockTimetableRepository
    public let statuses: MockOperationStatusRepository
    public let stations: LocalStationRepository
    public let liveActivityRegistration: MockLiveActivityRegistrationRepository
    public let capabilities: CachingCapabilityRepository
    public let attributions: CachingAttributionRepository

    public init(scenario: MockScenario = .standard, latency: Duration = .milliseconds(400)) {
        let registry = MockTrainRunRegistry()
        let capabilitySnapshot = MockData.capabilities(now: Date())
        routes = MockRouteRepository(scenario: scenario, catalog: MockData.catalog, registry: registry, latency: latency)
        timetables = MockTimetableRepository(catalog: MockData.catalog, capabilities: capabilitySnapshot, registry: registry, latency: latency)
        statuses = MockOperationStatusRepository(capabilities: capabilitySnapshot, latency: latency)
        stations = LocalStationRepository(source: nil, store: .caches("mock-station-master"))
        liveActivityRegistration = MockLiveActivityRegistrationRepository(routes: routes)
        capabilities = CachingCapabilityRepository(source: MockCapabilitySource(), store: .caches("mock-capabilities"))
        attributions = CachingAttributionRepository(source: MockAttributionSource(), store: .caches("mock-attributions"))
    }
}
