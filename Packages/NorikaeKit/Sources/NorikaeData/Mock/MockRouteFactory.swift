import Domain
import Foundation

/// モックの停車駅一覧を組み立てるための種
struct MockRunSeed: Sendable {
    var lineId: String
    var trainTypeId: String
    var destinationName: String
    var anchorStationId: String
    var anchorTime: Date
    /// 1 駅あたりの分数
    var minutesPerStop: Double
    /// 駅の並びの順方向に進むか
    var forward: Bool
    var fallbackStops: [StopPoint]
}

/// モックの経路を組み立てる
struct MockRouteFactory {
    let base: Date
    let catalog: Catalog
    private(set) var runSeeds: [String: MockRunSeed] = [:]

    init(base: Date, catalog: Catalog) {
        self.base = Date(timeIntervalSince1970: (base.timeIntervalSince1970 / 60).rounded(.down) * 60)
        self.catalog = catalog
    }

    func t(_ minutes: Int) -> Date { base.addingTimeInterval(TimeInterval(minutes * 60)) }

    func stop(_ stationId: String, _ minute: Int, platform: String? = nil, delay: Int? = nil) -> StopPoint {
        let time = t(minute)
        return StopPoint(
            stationId: stationId, scheduledTime: time,
            estimatedTime: delay.map { time.addingTimeInterval(TimeInterval($0 * 60)) },
            platform: platform, serviceDate: ServiceDate.operatingDay(containing: time)
        )
    }

    mutating func train(
        _ lineId: String, _ typeId: String, destination: String, from: StopPoint, to: StopPoint,
        hasTrainRun: Bool = true, boarding: BoardingPosition? = nil, disruption: LegDisruption? = nil
    ) -> Leg {
        let sequence = MockData.lineSequences[lineId] ?? []
        let fromIndex = sequence.firstIndex(of: from.stationId)
        let toIndex = sequence.firstIndex(of: to.stationId)
        let stopCount = (fromIndex != nil && toIndex != nil) ? max(abs(toIndex! - fromIndex!) - 1, 0) : 0
        var runId: String?
        if hasTrainRun {
            let id = "mock-run-\(UUID().uuidString.prefix(8))"
            let span = Double(max(abs((toIndex ?? 1) - (fromIndex ?? 0)), 1))
            runSeeds[id] = MockRunSeed(
                lineId: lineId, trainTypeId: typeId, destinationName: destination, anchorStationId: from.stationId,
                anchorTime: from.scheduledTime, minutesPerStop: to.scheduledTime.timeIntervalSince(from.scheduledTime) / 60 / span,
                forward: (toIndex ?? 1) >= (fromIndex ?? 0), fallbackStops: [from, to]
            )
            runId = id
        }
        let legDisruption = disruption ?? MockData.disruptions[lineId].map {
            LegDisruption(status: $0.status, delayMinutes: $0.delayMinutes, summary: $0.summary)
        }
        return .train(TrainLeg(
            lineId: lineId, trainTypeId: typeId, trainRunId: runId, destinationName: destination,
            from: from, to: to, stopCount: stopCount, boardingPosition: boarding, disruption: legDisruption
        ))
    }

    func walk(_ from: String, _ to: String, _ minutes: Int) -> Leg {
        .walk(WalkLeg(fromStationId: from, toStationId: to, durationMinutes: minutes))
    }

    func route(
        _ id: String, _ legs: [Leg], fare: Fare, availability: DataAvailability = .available, warnings: [RouteWarning] = []
    ) -> Route {
        let trains = legs.compactMap { leg -> TrainLeg? in
            if case .train(let train) = leg { return train }
            return nil
        }
        let departure = trains.first?.from.scheduledTime ?? base
        let arrival = trains.last?.to.effectiveTime ?? base
        return Route(
            id: id, departureTime: departure, arrivalTime: arrival,
            durationMinutes: Int((arrival.timeIntervalSince(departure) / 60).rounded()),
            transferCount: max(trains.count - 1, 0), fare: fare, legs: legs,
            hasServiceDisruption: trains.contains { $0.disruption?.status.isDisrupted == true },
            availability: availability, warnings: warnings,
            routeContext: RouteContext("mock:\(UUID().uuidString)")
        )
    }

    static func fare(ic: Int, ticket: Int? = nil) -> Fare {
        Fare(fareType: .exact, icTotal: ic, ticketTotal: ticket ?? ((ic + 9) / 10 * 10))
    }

    // MARK: - 池袋 → 横浜（design-spec のモックと同じ内容）

    mutating func ikebukuroToYokohama() -> [Route] {
        let I = MockID.ikebukuro, S = MockID.shibuya, Q = MockID.shinagawa, Y = MockID.yokohama, T = MockID.tokyo
        // 引数の中で mutating な train(...) を呼ぶと self へのアクセスが重なるため、区間を先に作る
        let legs1 = [
            train(MockID.shonanShinjuku, MockID.rapid, destination: "小田原行", from: stop(I, 9, platform: "3"), to: stop(Y, 43, platform: "9")),
        ]
        let legs2 = [
            train(
                MockID.fukutoshin, MockID.express, destination: "元町・中華街行", from: stop(I, 5, platform: "3"), to: stop(S, 16, platform: "5"),
                boarding: BoardingPosition(carNumber: 8, carCount: 10, purpose: .transfer, note: "渋谷での乗換に便利")
            ),
            walk(S, S, 2),
            train(MockID.toyoko, MockID.limitedExpress, destination: "元町・中華街行", from: stop(S, 20, platform: "4"), to: stop(Y, 47, platform: "2")),
        ]
        let legs3 = [
            train(MockID.yamanote, MockID.localStop, destination: "外回り", from: stop(I, 4, platform: "7", delay: 3), to: stop(Q, 32, platform: "2", delay: 3)),
            walk(Q, Q, 3),
            train(MockID.tokaido, MockID.local, destination: "小田原行", from: stop(Q, 37, platform: "13"), to: stop(Y, 54, platform: "7")),
        ]
        // #16：trainRunId がない区間
        let legs4 = [
            train(MockID.marunouchi, MockID.localStop, destination: "荻窪行", from: stop(I, 7, platform: "1"), to: stop(T, 30, platform: "2")),
            walk(T, T, 6),
            train(MockID.tokaido, MockID.local, destination: "熱海行", from: stop(T, 38), to: stop(Y, 65), hasTrainRun: false),
        ]
        let legs5 = [
            train(MockID.shonanShinjuku, MockID.rapid, destination: "小田原行", from: stop(I, 24, platform: "3"), to: stop(Y, 58, platform: "9")),
        ]
        return [
            route("r1", legs1, fare: Self.fare(ic: 836, ticket: 850)),
            route("r2", legs2, fare: Self.fare(ic: 684, ticket: 690)),
            route("r3", legs3, fare: Self.fare(ic: 916, ticket: 920)),
            route("r4", legs4, fare: Self.fare(ic: 780, ticket: 790)),
            route("r5", legs5, fare: Self.fare(ic: 836, ticket: 850)),
        ]
    }

    /// #5：乗換 3 回の経路
    mutating func threeTransfers() -> Route {
        let I = MockID.ikebukuro, J = MockID.shinjuku, T = MockID.tokyo, Q = MockID.shinagawa, Y = MockID.yokohama
        let legs = [
            train(MockID.saikyo, MockID.local, destination: "大崎行", from: stop(I, 3, platform: "5"), to: stop(J, 8, platform: "3")),
            walk(J, J, 3),
            train(MockID.chuoRapid, MockID.rapid, destination: "東京行", from: stop(J, 12, platform: "7"), to: stop(T, 26, platform: "1")),
            walk(T, T, 3),
            train(MockID.keihinTohoku, MockID.localStop, destination: "大船行", from: stop(T, 30, platform: "6"), to: stop(Q, 41, platform: "3")),
            walk(Q, Q, 2),
            train(MockID.tokaido, MockID.local, destination: "平塚行", from: stop(Q, 45, platform: "13"), to: stop(Y, 62, platform: "7")),
        ]
        return route("r-3transfers", legs, fare: Self.fare(ic: 572, ticket: 580))
    }

    /// #11：路線記号・路線色がない路線
    mutating func noSymbolRoute() -> Route {
        let I = MockID.ikebukuro, K = MockID.musashiKosugi, H = MockID.hazawa, Y = MockID.yokohama
        let legs = [
            train(MockID.shonanShinjuku, MockID.rapid, destination: "逗子行", from: stop(I, 6, platform: "3"), to: stop(K, 30)),
            walk(K, K, 4),
            train(MockID.sotetsuDirect, MockID.local, destination: "海老名行", from: stop(K, 36), to: stop(H, 44), hasTrainRun: false),
            walk(H, H, 3),
            train(MockID.noSymbol, MockID.local, destination: "横浜行", from: stop(H, 49), to: stop(Y, 58), hasTrainRun: false),
        ]
        return route("r-nosymbol", legs, fare: Self.fare(ic: 740))
    }

    // MARK: - 任意の駅の組み合わせ

    /// 駅マスタの路線の並びから経路を組み立てる
    mutating func generic(from: String, to: String) -> [Route] {
        var routes: [Route] = []
        var offset = 4
        let sequences = MockData.lineSequences.sorted { $0.key < $1.key }

        // 同じ路線での直通
        for (lineId, sequence) in sequences where sequence.contains(from) && sequence.contains(to) && routes.count < 2 {
            let minutes = legMinutes(from, to, lineId: lineId)
            let legs = [
                train(lineId, trainType(for: lineId), destination: destinationName(lineId: lineId, from: from, to: to),
                      from: stop(from, offset, platform: "1"), to: stop(to, offset + minutes, platform: "2")),
            ]
            routes.append(route("g\(routes.count + 1)", legs, fare: Self.fare(ic: fareFor(from, to))))
            offset += 5
        }

        // 1 回乗換
        outer: for (lineA, seqA) in sequences where seqA.contains(from) {
            for (lineB, seqB) in sequences where seqB.contains(to) && lineA != lineB {
                guard let hub = seqA.first(where: { $0 != from && $0 != to && seqB.contains($0) }) else { continue }
                let first = legMinutes(from, hub, lineId: lineA)
                let second = legMinutes(hub, to, lineId: lineB)
                let departure = offset
                let legs = [
                    train(lineA, trainType(for: lineA), destination: destinationName(lineId: lineA, from: from, to: hub),
                          from: stop(from, departure, platform: "2"), to: stop(hub, departure + first, platform: "4")),
                    walk(hub, hub, 3),
                    train(lineB, trainType(for: lineB), destination: destinationName(lineId: lineB, from: hub, to: to),
                          from: stop(hub, departure + first + 5, platform: "6"), to: stop(to, departure + first + 5 + second, platform: "1")),
                ]
                routes.append(route("g\(routes.count + 1)", legs, fare: Self.fare(ic: fareFor(from, to) + 60)))
                offset += 3
                if routes.count >= 4 { break outer }
            }
        }

        // 組み立てられないときは、出発駅の路線で到着駅へ行くものとして作る（運賃は概算）
        if routes.isEmpty, let lineId = catalog.station(from)?.lineIds.first {
            let minutes = max(legMinutes(from, to, lineId: lineId), 8)
            let legs = [
                train(lineId, trainType(for: lineId), destination: "\(catalog.station(to)?.name ?? "")方面",
                      from: stop(from, 5), to: stop(to, 5 + minutes), hasTrainRun: false),
            ]
            routes.append(route("g1", legs, fare: Fare(fareType: .estimated, estimatedTotal: fareFor(from, to))))
        }

        // 3 本に満たなければ、後の列車を足す
        while routes.count < 3, let first = routes.first {
            let next = shifted(first, byMinutes: 12 * routes.count, id: "g\(routes.count + 1)")
            routes.append(next)
        }
        return routes
    }

    /// 同じ構成のまま時刻をずらした経路（1 本前・1 本後）
    mutating func shifted(_ route: Route, byMinutes minutes: Int, id: String) -> Route {
        let delta = TimeInterval(minutes * 60)
        func shift(_ point: StopPoint) -> StopPoint {
            var copy = point
            copy.scheduledTime = point.scheduledTime.addingTimeInterval(delta)
            copy.estimatedTime = point.estimatedTime?.addingTimeInterval(delta)
            copy.serviceDate = ServiceDate.operatingDay(containing: copy.scheduledTime)
            return copy
        }
        var legs: [Leg] = []
        for leg in route.legs {
            switch leg {
            case .train(let train):
                legs.append(self.train(
                    train.lineId, train.trainTypeId, destination: train.destinationName, from: shift(train.from), to: shift(train.to),
                    hasTrainRun: train.trainRunId != nil, boarding: train.boardingPosition, disruption: train.disruption
                ))
            case .walk:
                legs.append(leg)
            }
        }
        return self.route(id, legs, fare: route.fare, availability: route.availability, warnings: route.warnings)
    }

    // MARK: - 補助

    private func legMinutes(_ from: String, _ to: String, lineId: String) -> Int {
        guard let a = catalog.station(from), let b = catalog.station(to) else { return 10 }
        let km = a.coordinate.distance(to: b.coordinate) / 1000
        let factor = trainType(for: lineId) == MockID.rapid ? 1.3 : 1.8
        return max(Int(km * factor) + 2, 3)
    }

    private func fareFor(_ from: String, _ to: String) -> Int {
        guard let a = catalog.station(from), let b = catalog.station(to) else { return 200 }
        return 140 + Int(a.coordinate.distance(to: b.coordinate) / 1000 * 18)
    }

    private func trainType(for lineId: String) -> String {
        switch lineId {
        case MockID.shonanShinjuku, MockID.chuoRapid: MockID.rapid
        case MockID.kyoto: MockID.specialRapid
        case MockID.toyoko, MockID.hankyuKobe: MockID.express
        case MockID.yamanote, MockID.keihinTohoku, MockID.ginza, MockID.marunouchi, MockID.fukutoshin, MockID.oedo, MockID.midosuji, MockID.sennichimae:
            MockID.localStop
        default: MockID.local
        }
    }

    private func destinationName(lineId: String, from: String, to: String) -> String {
        guard let sequence = MockData.lineSequences[lineId],
              let fromIndex = sequence.firstIndex(of: from), let toIndex = sequence.firstIndex(of: to) else { return "" }
        if lineId == MockID.yamanote { return toIndex > fromIndex ? "外回り" : "内回り" }
        let terminal = toIndex > fromIndex ? sequence.last : sequence.first
        return "\(terminal.flatMap { catalog.station($0)?.name } ?? "")行"
    }
}
