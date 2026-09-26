import Domain
import Foundation
import Testing

@Suite("時間軸（FR-CMP-03、FR-CMP-10）")
struct TimeAxisTests {
    @Test("軸の範囲は、全経路の最も早い出発から最も遅い到着まで")
    func range() throws {
        let routes = [
            Fixtures.route("a", [Fixtures.train("L", "A", 9, "B", 43)]),
            Fixtures.route("b", [Fixtures.train("L", "A", 4, "B", 59)]),
        ]
        let axis = try #require(TimeAxis(routes: routes))
        #expect(axis.start == Fixtures.t(4))
        #expect(axis.end == Fixtures.t(59))
        #expect(axis.totalMinutes == 55)
    }

    @Test("1 分あたりの高さは、(本体の高さ − 上下の余白) ÷ 軸の分数")
    func pointsPerMinute() {
        let axis = TimeAxis(start: Fixtures.t(0), end: Fixtures.t(52))
        // モックでは 52 分を 452pt に収めて 8pt/分（design-spec 7.4）
        #expect(axis.pointsPerMinute(contentHeight: 476, verticalPadding: 12) == 452.0 / 52.0)
        #expect(axis.y(for: Fixtures.t(0), pointsPerMinute: 8, verticalPadding: 12) == 12)
        #expect(axis.y(for: Fixtures.t(10), pointsPerMinute: 8, verticalPadding: 12) == 92)
    }

    @Test("目盛りの間隔は、隣との間が 40pt 以上になる最小の候補", arguments: [
        (8.0, 5), (5.0, 10), (3.0, 15), (1.5, 30), (0.5, 60), (0.1, 60),
    ])
    func tickInterval(pointsPerMinute: Double, expected: Int) {
        #expect(TimeAxis.tickInterval(pointsPerMinute: pointsPerMinute, minimumSpacing: 40, candidates: [5, 10, 15, 30, 60]) == expected)
    }

    @Test("目盛りは時計の分にそろう")
    func ticksAligned() {
        let axis = TimeAxis(start: Fixtures.t(4), end: Fixtures.t(59))
        let ticks = axis.ticks(intervalMinutes: 10, pointsPerMinute: 8, verticalPadding: 0)
        let minutes = ticks.map { JapanCalendar.calendar.component(.minute, from: $0) }
        #expect(minutes == [10, 20, 30, 40, 50])
    }

    @Test("日付をまたぐ経路でも、時間軸が連続する")
    func overnight() throws {
        // 23:50 発 → 翌 0:30 着
        let routes = [Fixtures.route("late", [Fixtures.train("L", "A", 950, "B", 990)])]
        let axis = try #require(TimeAxis(routes: routes))
        #expect(axis.totalMinutes == 40)
        let midnight = Fixtures.t(960)
        #expect(JapanCalendar.calendar.component(.hour, from: midnight) == 0)
        let y = axis.y(for: midnight, pointsPerMinute: 10, verticalPadding: 0)
        #expect(y == 100)
        // 運行日は前日のまま
        let leg = try #require(routes[0].trainLegs.last)
        #expect(leg.to.serviceDate == leg.from.serviceDate)
    }
}

@Suite("縦比較の配置")
struct CompareLayoutTests {
    @Test("乗換駅の着と発が 32pt 未満なら、発の駅名を省く")
    func collapseStationName() throws {
        let route = Fixtures.route("r", [
            Fixtures.train("F", "IK", 10, "SB", 21),
            Fixtures.walk("SB", 2),
            Fixtures.train("TY", "SB", 25, "YH", 52),
        ])
        let axis = TimeAxis(start: Fixtures.t(10), end: Fixtures.t(52))
        let layout = CompareColumnLayout(route: route, axis: axis, pointsPerMinute: 6, verticalPadding: 12)
        #expect(layout.labels.count == 4)
        // 8:21 渋谷（着）と 8:25（発）：24pt 差
        #expect(layout.labels[1].role == .arrival)
        #expect(layout.labels[1].showsStationName)
        #expect(layout.labels[2].role == .departure)
        #expect(!layout.labels[2].showsStationName)
        #expect(layout.connectors.count == 1)
        #expect(layout.bands.count == 2)
    }

    @Test("それでも重なるときは、発車の時刻を優先する")
    func preferDeparture() {
        let route = Fixtures.route("r", [
            Fixtures.train("F", "IK", 10, "SB", 21),
            Fixtures.train("TY", "SB", 22, "YH", 52),
        ])
        let axis = TimeAxis(start: Fixtures.t(10), end: Fixtures.t(52))
        let layout = CompareColumnLayout(route: route, axis: axis, pointsPerMinute: 6, verticalPadding: 12)
        #expect(layout.labels.count == 3)
        #expect(layout.labels.map(\.role) == [.departure, .departure, .arrival])
    }

    @Test("乗換 0 回と 3 回")
    func transferCounts() {
        let direct = Fixtures.route("d", [Fixtures.train("A", "S1", 0, "S2", 30)])
        let many = Fixtures.route("m", [
            Fixtures.train("A", "S1", 0, "S2", 5), Fixtures.walk("S2", 2),
            Fixtures.train("B", "S2", 8, "S3", 20), Fixtures.walk("S3", 2),
            Fixtures.train("C", "S3", 24, "S4", 30), Fixtures.walk("S4", 1),
            Fixtures.train("D", "S4", 33, "S5", 50),
        ])
        #expect(direct.transferCount == 0)
        #expect(direct.transfers.isEmpty)
        #expect(many.transferCount == 3)
        #expect(many.transfers.map(\.totalMinutes) == [3, 4, 3])
        #expect(many.transfers.map(\.walkMinutes) == [2, 2, 1])
    }
}

@Suite("早・楽・安（FR-CMP-07）")
struct RouteRankingTests {
    let fast = Fixtures.route("fast", [Fixtures.train("A", "S", 9, "G", 43)], fare: Fare(fareType: .exact, icTotal: 836, ticketTotal: 850))
    let cheap = Fixtures.route("cheap", [
        Fixtures.train("B", "S", 5, "X", 16), Fixtures.train("C", "X", 20, "G", 47),
    ], fare: Fare(fareType: .exact, icTotal: 684, ticketTotal: 690))
    let slow = Fixtures.route("slow", [
        Fixtures.train("D", "S", 4, "Y", 32), Fixtures.train("E", "Y", 37, "G", 54),
    ], fare: Fare(fareType: .exact, icTotal: 916, ticketTotal: 920), disruption: true)

    @Test("早・楽・安がそれぞれ付く。1 つの経路に複数付いてもよい")
    func badges() {
        let badges = RouteRanking.badges(for: [fast, cheap, slow], fareKind: .ic)
        #expect(badges["fast"] == [.fastest, .fewestTransfers])
        #expect(badges["cheap"] == [.cheapest])
        #expect(badges["slow"] == nil)
    }

    @Test("種別が混在する場合は「安」を付けない")
    func mixedFareKinds() {
        var estimated = cheap
        estimated.fare = Fare(fareType: .estimated, estimatedTotal: 600)
        let badges = RouteRanking.badges(for: [fast, estimated, slow], fareKind: .ic)
        #expect(badges.values.allSatisfy { !$0.contains(.cheapest) })
    }

    @Test("運賃が不明な経路があれば「安」を付けない")
    func unavailableFare() {
        var unknown = slow
        unknown.fare = .unavailable
        let badges = RouteRanking.badges(for: [fast, cheap, unknown], fareKind: .ic)
        #expect(badges.values.allSatisfy { !$0.contains(.cheapest) })
    }

    @Test("設定した種別がなく、もう一方で全経路がそろうなら比べられる")
    func otherKindConsistent() {
        var a = fast, b = cheap
        a.fare = Fare(fareType: .exact, ticketTotal: 850)
        b.fare = Fare(fareType: .exact, ticketTotal: 690)
        let badges = RouteRanking.badges(for: [a, b], fareKind: .ic)
        #expect(badges["cheap"]?.contains(.cheapest) == true)
    }

    @Test("並び替え：早い順・乗換が少ない順・安い順")
    func sorting() {
        let routes = [slow, cheap, fast]
        #expect(RouteRanking.sorted(routes, by: .fastest, fareKind: .ic).map(\.id) == ["fast", "cheap", "slow"])
        #expect(RouteRanking.sorted(routes, by: .fewestTransfers, fareKind: .ic).map(\.id) == ["fast", "cheap", "slow"])
        #expect(RouteRanking.sorted(routes, by: .cheapest, fareKind: .ic).map(\.id) == ["cheap", "fast", "slow"])
    }

    @Test("安い順では、運賃不明を最後にする")
    func sortingUnknownFareLast() {
        var unknown = cheap
        unknown.fare = .unavailable
        #expect(RouteRanking.sorted([unknown, slow, fast], by: .cheapest, fareKind: .ic).map(\.id) == ["fast", "slow", "cheap"])
    }
}
