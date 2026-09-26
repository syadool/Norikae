import Domain
import Foundation
import Testing

@Suite("同じ経路の照合（api-contract 4.2）")
struct RouteSignatureTests {
    let original = Fixtures.route("a", [
        Fixtures.train("F", "IK", 5, "SB", 16), Fixtures.walk("SB", 2), Fixtures.train("TY", "SB", 20, "YH", 47),
    ], context: "old")

    @Test("区間の路線・乗車駅・降車駅・出発時刻が一致すれば同じ経路")
    func matches() {
        let refreshed = Fixtures.route("b", [
            Fixtures.train("F", "IK", 5, "SB", 16), Fixtures.train("TY", "SB", 20, "YH", 47),
        ], context: "new")
        #expect(RouteSignature(route: original).findMatch(in: [refreshed])?.routeContext == RouteContext("new"))
    }

    @Test("出発時刻が違えば別の経路")
    func differentTime() {
        let later = Fixtures.route("b", [
            Fixtures.train("F", "IK", 13, "SB", 24), Fixtures.train("TY", "SB", 28, "YH", 55),
        ])
        #expect(RouteSignature(route: original).findMatch(in: [later]) == nil)
        #expect(RouteSignature(route: original).findStructuralMatch(in: [later])?.id == "b")
    }
}

@Suite("1 本後の経路の構成の変化（FR-LA-20、FR-DTL-06）")
struct AdjacentRouteChangeTests {
    @Test("同じ構成で時刻だけずれる")
    func sameStructure() {
        let a = Fixtures.route("a", [Fixtures.train("JS", "IK", 9, "YH", 43)])
        let b = Fixtures.route("b", [Fixtures.train("JS", "IK", 17, "YH", 51)])
        let change = AdjacentRouteChange(original: a, adjacent: b)
        #expect(!change.structureChanged)
        #expect(change.arrivalDeltaMinutes == 8)
    }

    @Test("乗換駅が変わる")
    func structureChanged() {
        let a = Fixtures.route("a", [Fixtures.train("JS", "IK", 9, "YH", 43)])
        let b = Fixtures.route("b", [Fixtures.train("F", "IK", 12, "SB", 23), Fixtures.train("TY", "SB", 27, "YH", 54)])
        let change = AdjacentRouteChange(original: a, adjacent: b)
        #expect(change.structureChanged)
        #expect(change.transferStationsChanged)
        #expect(change.arrivalDeltaMinutes == 11)
    }
}

@Suite("出発リマインド（FR-NTF-03、FR-NTF-05）")
struct ReminderCalculatorTests {
    @Test("発車時刻 − 歩く時間 − 余裕の時間")
    func withWalking() {
        let fire = ReminderCalculator.fireDate(
            departure: Fixtures.t(30), walkingDuration: 10 * 60, walkingSpeed: .normal, margin: .three, now: Fixtures.t(0)
        )
        #expect(fire == Fixtures.t(17))
    }

    @Test("歩く速さで補正する")
    func walkingSpeed() {
        let fire = ReminderCalculator.fireDate(
            departure: Fixtures.t(30), walkingDuration: 8 * 60, walkingSpeed: .slow, margin: .zero, now: Fixtures.t(0)
        )
        #expect(fire == Fixtures.t(20))
    }

    @Test("位置情報が取れなければ、発車時刻 − 余裕の時間")
    func withoutLocation() {
        let fire = ReminderCalculator.fireDate(departure: Fixtures.t(30), walkingDuration: nil, walkingSpeed: .normal, margin: .five, now: Fixtures.t(0))
        #expect(fire == Fixtures.t(25))
    }

    @Test("過ぎた時刻には予約しない")
    func past() {
        let fire = ReminderCalculator.fireDate(departure: Fixtures.t(5), walkingDuration: 10 * 60, walkingSpeed: .normal, margin: .three, now: Fixtures.t(0))
        #expect(fire == nil)
    }
}

@Suite("Live Activity の状態（api-contract 5.3、FR-LA-10）")
struct LiveGuidanceStateTests {
    let route = Fixtures.route("r", [
        Fixtures.train("F", "IK", 10, "SB", 21), Fixtures.walk("SB", 2), Fixtures.train("TY", "SB", 25, "YH", 52),
    ])

    @Test("ContentState は UNIX 時刻の Int。徒歩区間は数えない")
    func initialState() {
        let state = LiveRouteState(route: route, now: Fixtures.base)
        #expect(state.legs.map(\.index) == [0, 1])
        #expect(state.legs[0].scheduledDeparture == Int(Fixtures.t(10).timeIntervalSince1970))
        #expect(state.legs[1].scheduledArrival == Int(Fixtures.t(52).timeIntervalSince1970))
        #expect(state.legs.allSatisfy { $0.estimatedDeparture == nil && $0.delayMinutes == nil })
        #expect(state.updatedAt == Int(Fixtures.base.timeIntervalSince1970))
    }

    @Test("区間の進行は予定時刻で切り替える")
    func progress() {
        let state = LiveRouteState(route: route, now: Fixtures.base)
        #expect(GuidanceProgress(state: state, now: Fixtures.t(0)).phase == .waiting(legIndex: 0))
        #expect(GuidanceProgress(state: state, now: Fixtures.t(15)).phase == .riding(legIndex: 0))
        #expect(GuidanceProgress(state: state, now: Fixtures.t(22)).phase == .waiting(legIndex: 1))
        #expect(GuidanceProgress(state: state, now: Fixtures.t(30)).phase == .riding(legIndex: 1))
        #expect(GuidanceProgress(state: state, now: Fixtures.t(53)).phase == .arrived)
        #expect(GuidanceProgress(state: state, now: Fixtures.t(31)).fraction == 0.5)
    }

    @Test("見込み時刻があれば、到着の自動終了を延長する（FR-LA-03）")
    func delayedEnd() throws {
        var state = LiveRouteState(route: route, now: Fixtures.base)
        state.legs[1].estimatedArrival = Int(Fixtures.t(57).timeIntervalSince1970)
        #expect(GuidanceProgress.endDate(for: state) == Fixtures.t(57))
        #expect(GuidanceProgress(state: state, now: Fixtures.t(54)).phase == .riding(legIndex: 1))
    }

    @Test("表示を描き直す時刻")
    func transitionDates() {
        let state = LiveRouteState(route: route, now: Fixtures.base)
        #expect(GuidanceProgress.transitionDates(for: state, after: Fixtures.t(20)) == [Fixtures.t(21), Fixtures.t(25), Fixtures.t(52)])
    }

    @Test("既定の JSONDecoder で api-contract 5.3 の例を読める")
    func decodesContractExample() throws {
        let json = """
        {
          "legs": [
            {
              "index": 0, "platform": "3",
              "scheduledDeparture": 1790378100, "estimatedDeparture": 1790378400,
              "scheduledArrival": 1790379120, "estimatedArrival": 1790379420,
              "delayMinutes": 5, "isCancelled": false
            }
          ],
          "disruptionSummary": "人身事故の影響で遅れ",
          "updatedAt": 1790378040
        }
        """
        let state = try JSONDecoder().decode(LiveRouteState.self, from: Data(json.utf8))
        #expect(state.legs.first?.delayMinutes == 5)
        #expect(state.legs.first?.departureDate == Date(timeIntervalSince1970: 1790378400))
        #expect(state.disruptionSummary == "人身事故の影響で遅れ")
        #expect(state.localNotice == nil)
    }
}

@Suite("routeContext の期限切れ（api-contract 4.2）")
struct RouteContextRecoveryTests {
    actor StubRepository: RouteRepository {
        var searchResult: RouteSearchResult
        var expiredContexts: Set<RouteContext>
        private(set) var searchCount = 0

        init(searchResult: RouteSearchResult, expiredContexts: Set<RouteContext>) {
            self.searchResult = searchResult
            self.expiredContexts = expiredContexts
        }

        func searchRoutes(_ query: RouteSearchQuery) async throws -> RouteSearchResult {
            searchCount += 1
            return searchResult
        }

        func adjacentRoute(context: RouteContext, direction: AdjacentDirection) async throws -> AdjacentRouteResult {
            if expiredContexts.contains(context) {
                throw APIError(code: "ROUTE_CONTEXT_EXPIRED", message: "期限切れ", retryable: false)
            }
            return AdjacentRouteResult(route: Fixtures.route("next", [Fixtures.train("A", "S", 20, "G", 50)], context: "next-\(context.rawValue)"))
        }

        func trainRun(id: TrainRun.ID, serviceDate: ServiceDate) async throws -> TrainRunResult {
            throw APIError(code: "INVALID_REQUEST", message: "", retryable: false)
        }
    }

    let query = RouteSearchQuery(fromStationId: "S", toStationId: "G", dateTime: Fixtures.base)
    let original = Fixtures.route("a", [Fixtures.train("A", "S", 10, "G", 40)], context: "old")

    @Test("期限切れなら同じ条件で再検索し、同じ経路の新しい routeContext で続ける")
    func recovers() async throws {
        let fresh = Fixtures.route("a2", [Fixtures.train("A", "S", 10, "G", 40)], context: "fresh")
        let repository = StubRepository(
            searchResult: RouteSearchResult(meta: ResponseMeta(asOf: Fixtures.base), routes: [fresh]),
            expiredContexts: [RouteContext("old")]
        )
        let result = try await RouteContextRecovery(repository: repository).adjacentRoute(from: original, query: query, direction: .next)
        #expect(result.route.routeContext == RouteContext("next-fresh"))
        #expect(await repository.searchCount == 1)
    }

    @Test("同じ経路が見つからなければ、新しい検索結果で選び直してもらう")
    func notFound() async {
        let other = Fixtures.route("b", [Fixtures.train("A", "S", 15, "G", 45)], context: "other")
        let repository = StubRepository(
            searchResult: RouteSearchResult(meta: ResponseMeta(asOf: Fixtures.base), routes: [other]),
            expiredContexts: [RouteContext("old")]
        )
        await #expect(throws: AppError.self) {
            try await RouteContextRecovery(repository: repository).adjacentRoute(from: original, query: query, direction: .next)
        }
    }

    @Test("期限切れでなければ再検索しない")
    func noRecoveryNeeded() async throws {
        let repository = StubRepository(searchResult: RouteSearchResult(meta: ResponseMeta(asOf: Fixtures.base), routes: []), expiredContexts: [])
        _ = try await RouteContextRecovery(repository: repository).adjacentRoute(from: original, query: query, direction: .next)
        #expect(await repository.searchCount == 0)
    }
}
