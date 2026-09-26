import Domain
import Foundation
@testable import NorikaeData
import Testing

@Suite("駅名の候補検索（FR-SRC-02〜04）")
struct StationSearchTests {
    let stations = StationMasterSnapshot.bundled().stations

    @Test("漢字・ひらがな・カタカナで前方一致")
    func prefix() {
        for text in ["池袋", "いけぶ", "イケブクロ", "池袋駅"] {
            #expect(StationSearchMatcher.search(text, in: stations, preferredRegion: .kanto).first?.name == "池袋", "\(text)")
        }
    }

    @Test("部分一致も出す（前方一致より後）")
    func partial() {
        let names = StationSearchMatcher.search("しん", in: stations, preferredRegion: .kanto).map(\.name)
        #expect(names.contains("新宿"))
        #expect(names.contains("新宿三丁目"))
        // 「しながわ」は前方一致しないので含まない
        #expect(!names.contains("品川"))
        let partial = StationSearchMatcher.search("三丁目", in: stations, preferredRegion: .kanto).map(\.name)
        #expect(partial == ["新宿三丁目"])
    }

    @Test("同じ名前の駅は、主に使う地域を先に出す")
    func preferredRegion() {
        let kanto = StationSearchMatcher.search("日本橋", in: stations, preferredRegion: .kanto)
        #expect(kanto.map(\.prefecture) == ["東京都", "大阪府"])
        let kansai = StationSearchMatcher.search("日本橋", in: stations, preferredRegion: .kansai)
        #expect(kansai.map(\.prefecture) == ["大阪府", "東京都"])
    }

    @Test("最寄り駅")
    func nearest() {
        // 渋谷駅のそば
        let result = StationSearchMatcher.nearest(to: Coordinate(latitude: 35.6590, longitude: 139.7010), in: stations, limit: 1)
        #expect(result.first?.name == "渋谷")
    }
}

@Suite("駅マスタの差分と ID の移行（FR-SRC-09）")
struct StationMigrationTests {
    @Test("統合は移行先へ、移行先のない廃止は利用できない駅として返す")
    func migration() {
        let changes = MasterDataChanges(version: 12, removed: [
            .init(kind: .station, id: "old-a", replacedById: "new-a"),
            .init(kind: .station, id: "gone"),
            .init(kind: .line, id: "old-line", replacedById: "new-line"),
        ])
        let migration = StationMigration(changes: changes)
        #expect(migration.replacements == ["old-a": "new-a"])
        #expect(migration.removedWithoutReplacement == ["gone"])
        #expect(migration.lineReplacements == ["old-line": "new-line"])
    }

    @Test("お気に入り・履歴・マイ路線の ID を置き換える")
    @MainActor
    func userData() {
        let store = InMemoryUserDataStore()
        let query = RouteSearchQuery(fromStationId: "old-a", toStationId: "b", dateTime: Date())
        store.addFavorite(.station(stationId: "old-a"))
        store.addHistory(query)
        store.addMyLine(lineId: "old-line")
        store.migrateIDs(stations: ["old-a": "new-a"], lines: ["old-line": "new-line"])
        #expect(store.favorites().first?.item == .station(stationId: "new-a"))
        #expect(store.history().first?.query.fromStationId == "new-a")
        #expect(store.myLines().first?.lineId == "new-line")
    }
}

@Suite("お気に入り・履歴（SwiftData）")
@MainActor
struct UserDataStoreTests {
    @Test("お気に入りの追加・重複の防止・並べ替え・削除（FR-MY-01）")
    func favorites() throws {
        let store = SwiftDataUserDataStore(container: try UserDataContainer.make(cloudSync: false, inMemory: true))
        store.addFavorite(.station(stationId: "a"))
        store.addFavorite(.station(stationId: "b"))
        store.addFavorite(.station(stationId: "a"))
        #expect(store.favorites().map(\.item) == [.station(stationId: "a"), .station(stationId: "b")])
        store.moveFavorites(from: [1], to: 0)
        #expect(store.favorites().map(\.item) == [.station(stationId: "b"), .station(stationId: "a")])
        store.removeFavorite(id: store.favorites()[0].id)
        #expect(store.favorites().map(\.item) == [.station(stationId: "a")])
    }

    @Test("履歴：同じ移動は新しいものに置き換え、全件削除できる（FR-MY-02）")
    func history() throws {
        let store = SwiftDataUserDataStore(container: try UserDataContainer.make(cloudSync: false, inMemory: true))
        store.addHistory(RouteSearchQuery(fromStationId: "a", toStationId: "b", dateTime: Date(timeIntervalSince1970: 0)))
        store.addHistory(RouteSearchQuery(fromStationId: "c", toStationId: "d", dateTime: Date()))
        store.addHistory(RouteSearchQuery(fromStationId: "a", toStationId: "b", dateTime: Date()))
        #expect(store.history().map(\.query.fromStationId) == ["a", "c"])
        store.clearHistory()
        #expect(store.history().isEmpty)
    }
}

@Suite("検索結果のキャッシュ（FR-OFF-01）")
struct SearchResultCacheTests {
    @Test("同じ駅・条件の最新を返し、20 件を超えたら古いものから消す")
    func capacity() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "cache-test-\(UUID().uuidString)")
        let cache = SearchResultCache(store: JSONFileStore(directory: directory))
        let result = RouteSearchResult(meta: ResponseMeta(asOf: Date()), routes: [])
        for index in 0..<25 {
            await cache.save(result, for: RouteSearchQuery(fromStationId: "s\(index)", toStationId: "g", dateTime: Date()))
        }
        #expect(await cache.latest(matching: RouteSearchQuery(fromStationId: "s24", toStationId: "g", dateTime: .distantPast)) != nil)
        #expect(await cache.latest(matching: RouteSearchQuery(fromStationId: "s0", toStationId: "g", dateTime: Date())) == nil)

        // 読み直しても残っている
        let reloaded = SearchResultCache(store: JSONFileStore(directory: directory))
        #expect(await reloaded.latest(matching: RouteSearchQuery(fromStationId: "s10", toStationId: "g", dateTime: Date())) != nil)
    }
}

@Suite("モックの場面（api-contract 7 章）")
struct MockScenarioTests {
    let query = RouteSearchQuery(fromStationId: MockID.ikebukuro, toStationId: MockID.yokohama, dateTime: Date())

    @Test("#1 #2：5 本の経路。「早・楽・安」と遅延を含む")
    func standard() async throws {
        let repository = MockRouteRepository(scenario: .standard, latency: .zero)
        let result = try await repository.searchRoutes(query)
        #expect(result.routes.count == 5)
        #expect(result.routes.contains { $0.hasServiceDisruption })
        let badges = RouteRanking.badges(for: result.routes, fareKind: .ic)
        #expect(badges.values.contains { $0.contains(.cheapest) })
        // #16：trainRunId がない区間
        #expect(result.routes.contains { $0.trainLegs.contains { $0.trainRunId == nil } })
    }

    @Test("#9：0 件は ROUTE_NOT_FOUND")
    func empty() async {
        let repository = MockRouteRepository(scenario: .empty, latency: .zero)
        await #expect(throws: APIError.self) { try await repository.searchRoutes(query) }
    }

    @Test("#12：概算・不明・種別の混在では「安」を付けない")
    func fareVariants() async throws {
        let result = try await MockRouteRepository(scenario: .fareVariants, latency: .zero).searchRoutes(query)
        let badges = RouteRanking.badges(for: result.routes, fareKind: .ic)
        #expect(badges.values.allSatisfy { !$0.contains(.cheapest) })
    }

    @Test("#17：経由駅つきの FEATURE_UNAVAILABLE。関西圏の経由駅も非対応")
    func featureUnavailable() async throws {
        var withVia = query
        withVia.viaStationIds = [MockID.shibuya]
        let repository = MockRouteRepository(scenario: .featureUnavailable, latency: .zero)
        do {
            _ = try await repository.searchRoutes(withVia)
            Issue.record("FEATURE_UNAVAILABLE になるはず")
        } catch {
            #expect(AppError.wrap(error).apiCode == .featureUnavailable)
        }
        #expect(try await repository.searchRoutes(withVia.removing(.viaStations)).routes.isEmpty == false)

        let kansai = RouteSearchQuery(fromStationId: "jp.station.osaka", toStationId: "jp.station.kyoto", viaStationIds: ["jp.station.shin-osaka"], dateTime: Date())
        await #expect(throws: APIError.self) { try await MockRouteRepository(latency: .zero).searchRoutes(kansai) }
    }

    @Test("#17：最初の routeContext は期限切れ。取り直せば使える")
    func contextExpired() async throws {
        let repository = MockRouteRepository(scenario: .contextExpired, latency: .zero)
        let first = try await repository.searchRoutes(query)
        let route = try #require(first.routes.first)
        let recovered = try await RouteContextRecovery(repository: repository).adjacentRoute(from: route, query: query, direction: .next)
        #expect(recovered.route.departureTime > route.departureTime)
    }

    @Test("#18：1 本後で構成が変わる場合・変わらない場合")
    func adjacentStructure() async throws {
        let changing = MockRouteRepository(scenario: .adjacentStructureChange, latency: .zero)
        let direct = try #require(try await changing.searchRoutes(query).routes.first { $0.trainLegs.count == 1 })
        let next = try await changing.adjacentRoute(context: direct.routeContext, direction: .next)
        #expect(AdjacentRouteChange(original: direct, adjacent: next.route).structureChanged)

        let same = MockRouteRepository(scenario: .standard, latency: .zero)
        let original = try #require(try await same.searchRoutes(query).routes.first)
        let later = try await same.adjacentRoute(context: original.routeContext, direction: .next)
        #expect(!AdjacentRouteChange(original: original, adjacent: later.route).structureChanged)
        #expect(later.route.departureTime == original.departureTime.addingTimeInterval(8 * 60))
    }

    @Test("#4：終電は日付をまたぐ")
    func overnight() async throws {
        var lastTrain = query
        lastTrain.searchType = .lastTrain
        let result = try await MockRouteRepository(scenario: .overnight, latency: .zero).searchRoutes(lastTrain)
        let crossing = result.routes.contains { route in
            JapanCalendar.calendar.component(.day, from: route.arrivalTime) != JapanCalendar.calendar.component(.day, from: route.departureTime)
        }
        #expect(crossing)
    }

    @Test("停車駅一覧を組み立てられる")
    func trainRun() async throws {
        let repository = MockRouteRepository(latency: .zero)
        let route = try #require(try await repository.searchRoutes(query).routes.first)
        let leg = try #require(route.trainLegs.first { $0.trainRunId != nil })
        let run = try await repository.trainRun(id: try #require(leg.trainRunId), serviceDate: leg.from.serviceDate)
        #expect(run.trainRun.stops.contains { $0.stationId == leg.from.stationId })
        #expect(run.trainRun.stops.contains { $0.stationId == leg.to.stationId })
    }

    @Test("#14 #15：関西圏の運行情報は非対応（unknown）、時刻表の非対応路線は FEATURE_UNAVAILABLE")
    func capabilities() async throws {
        let statuses = try await MockOperationStatusRepository(latency: .zero).statuses(region: .kansai)
        #expect(statuses.statuses.allSatisfy { $0.status == .unknown })
        let timetables = MockTimetableRepository(latency: .zero)
        await #expect(throws: APIError.self) {
            try await timetables.timetable(stationID: MockID.ikebukuro, lineID: MockID.yamanote, directionID: "outbound", dayType: .weekday)
        }
        let supported = try await timetables.timetable(stationID: MockID.ikebukuro, lineID: MockID.fukutoshin, directionID: "outbound", dayType: .weekday)
        #expect(!supported.timetable.departures.isEmpty)
    }
}
