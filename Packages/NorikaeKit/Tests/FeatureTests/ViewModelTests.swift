import DesignSystem
import Domain
@testable import Feature
import Foundation
import NorikaeData
import Testing

@MainActor
func makeDependencies(scenario: MockScenario = .standard, online: Bool = true) async -> AppDependencies {
    let network = NetworkMonitor(monitoring: false)
    network.setOnline(online)
    let settings = AppSettings(defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!)
    settings.region = .kanto
    let dependencies = AppDependencies.mock(
        scenario: scenario, settings: settings, userData: InMemoryUserDataStore(), latency: .zero, network: network,
        location: FixedLocationProvider(coordinate: nil, authorization: .denied),
        reminders: RecordingReminderScheduler(), guidanceSessionStore: InMemoryGuidanceSessionStore()
    )
    await dependencies.bootstrap()
    return dependencies
}

let sampleQuery = RouteSearchQuery(fromStationId: MockID.ikebukuro, toStationId: MockID.yokohama, dateTime: Date())

@Suite("縦比較の ViewModel")
@MainActor
struct RouteResultsModelTests {
    @Test("検索結果を読み込み、アプリ内で並べ替える（FR-CND-04）")
    func loadAndSort() async {
        let model = RouteResultsModel(query: sampleQuery, dependencies: await makeDependencies())
        await model.load()
        #expect(model.phase == .loaded)
        #expect(model.columns.count == 5)
        let fastest = model.columns.map(\.route.durationMinutes)
        #expect(fastest == fastest.sorted())

        model.sortOrder = .cheapest
        let fares = model.columns.compactMap(\.fare.value)
        #expect(fares == fares.sorted())
        #expect(model.columns.first?.badges.contains(.cheapest) == true)
    }

    @Test("検索条件・縦比較で選んだ運賃種別を、次の画面に引き継ぐ")
    func fareKindCarriesOver() async throws {
        let dependencies = await makeDependencies()
        dependencies.settings.fareKind = .ic
        let model = RouteResultsModel(query: sampleQuery, fareKind: .ticket, dependencies: dependencies)
        #expect(model.fareKind == .ticket)
        await model.load()

        model.fareKind = .ic
        let selection = try #require(model.selection(for: model.columns[0].id))
        #expect(selection.fareKind == .ic)
        dependencies.settings.fareKind = .ticket
        #expect(RouteDetailModel(selection: selection, dependencies: dependencies).fareKind == .ic)
    }

    @Test("0 件は空の状態（ROUTE_NOT_FOUND）")
    func empty() async {
        let model = RouteResultsModel(query: sampleQuery, dependencies: await makeDependencies(scenario: .empty))
        await model.load()
        #expect(model.phase == .empty)
    }

    @Test("再試行ボタンは retryable のときだけ（10.3）")
    func retryable() async {
        let retryable = RouteResultsModel(query: sampleQuery, dependencies: await makeDependencies(scenario: .retryableError))
        await retryable.load()
        guard case .failed(let error) = retryable.phase else { Issue.record("エラーになるはず"); return }
        #expect(error.retryable)

        let nonRetryable = RouteResultsModel(query: sampleQuery, dependencies: await makeDependencies(scenario: .nonRetryableError))
        await nonRetryable.load()
        guard case .failed(let error2) = nonRetryable.phase else { Issue.record("エラーになるはず"); return }
        #expect(!error2.retryable)
    }

    @Test("FEATURE_UNAVAILABLE なら条件を外して再検索する導線を出す（FR-CND-02）")
    func featureUnavailable() async {
        var query = sampleQuery
        query.viaStationIds = [MockID.shibuya]
        let model = RouteResultsModel(query: query, dependencies: await makeDependencies(scenario: .featureUnavailable))
        await model.load()
        guard case .featureUnavailable(_, let removable) = model.phase else { Issue.record("非対応になるはず"); return }
        #expect(removable == [.viaStations])
        await model.searchRemoving(.viaStations)
        #expect(model.phase == .loaded)
        #expect(model.query.viaStationIds.isEmpty)
    }

    @Test("一部欠損・古い情報を上部に表示する（FR-CMP-12）")
    func partialStale() async {
        let model = RouteResultsModel(query: sampleQuery, dependencies: await makeDependencies(scenario: .partialStale))
        await model.load()
        #expect(model.notices.contains(.partial))
        #expect(model.notices.contains { if case .stale = $0 { true } else { false } })
    }

    @Test("オフラインではキャッシュを取得時刻つきで出す（FR-OFF-01、FR-OFF-02）")
    func offlineCache() async {
        let dependencies = await makeDependencies()
        let online = RouteResultsModel(query: sampleQuery, dependencies: dependencies)
        await online.load()

        dependencies.network.setOnline(false)
        let offline = RouteResultsModel(query: sampleQuery, dependencies: dependencies)
        await offline.load()
        #expect(offline.phase == .loaded)
        #expect(offline.cachedAt != nil)
        #expect(offline.notices.contains { if case .cached = $0 { true } else { false } })
        // キャッシュから開いた経路は、案内開始などの前に再検索する（FR-OFF-06）
        let selection = offline.selection(for: offline.columns[0].id)
        #expect(selection?.isFromCache == true)
    }

    @Test("オフラインでキャッシュもなければ、再試行できるエラー")
    func offlineWithoutCache() async {
        let model = RouteResultsModel(query: sampleQuery, dependencies: await makeDependencies(online: false))
        await model.load()
        guard case .failed(let error) = model.phase else { Issue.record("エラーになるはず"); return }
        #expect(error.retryable)
    }

    @Test("お気に入りから開いたときは、同じ乗り方の経路を返す（FR-DTL-03）")
    func preferred() async throws {
        let dependencies = await makeDependencies()
        let first = RouteResultsModel(query: sampleQuery, dependencies: dependencies)
        await first.load()
        let target = try #require(first.columns.first { $0.route.transferCount == 1 }?.route)

        let model = RouteResultsModel(query: sampleQuery, preferred: RouteSignature(route: target), dependencies: dependencies)
        await model.load()
        #expect(model.takePreferredSelection().map { RouteStructure(route: $0.route) } == RouteStructure(route: target))
        #expect(model.takePreferredSelection() == nil)
    }
}

@Suite("経路詳細の ViewModel")
@MainActor
struct RouteDetailModelTests {
    private func selection(_ dependencies: AppDependencies, scenario: MockScenario = .standard) async throws -> RouteSelection {
        let results = RouteResultsModel(query: sampleQuery, dependencies: dependencies)
        await results.load()
        return try #require(results.selection(for: results.columns[0].id))
    }

    @Test("1 本後に切り替える。同じ構成なら到着の変化だけを伝える（FR-DTL-06）")
    func adjacent() async throws {
        let dependencies = await makeDependencies()
        let model = RouteDetailModel(selection: try await selection(dependencies), dependencies: dependencies)
        let before = model.route
        await model.loadAdjacent(.next)
        #expect(model.adjacentState == .idle)
        #expect(model.route.departureTime > before.departureTime)
        #expect(model.adjacentChange?.structureChanged == false)
        #expect(model.adjacentChangeText != nil)
    }

    @Test("構成が変わった場合は、その旨を表示する")
    func adjacentStructureChange() async throws {
        let dependencies = await makeDependencies(scenario: .adjacentStructureChange)
        let results = RouteResultsModel(query: sampleQuery, dependencies: dependencies)
        await results.load()
        let direct = try #require(results.columns.first { $0.route.transferCount == 0 })
        let model = RouteDetailModel(selection: try #require(results.selection(for: direct.id)), dependencies: dependencies)
        await model.loadAdjacent(.next)
        #expect(model.adjacentChange?.structureChanged == true)
    }

    @Test("オフラインでは「オフラインのため実行できません」（FR-OFF-06）")
    func offline() async throws {
        let dependencies = await makeDependencies()
        let model = RouteDetailModel(selection: try await selection(dependencies), dependencies: dependencies)
        dependencies.network.setOnline(false)
        await model.loadAdjacent(.next)
        #expect(model.adjacentState == .failed(.offlineAction))
    }

    @Test("お気に入りの登録と解除（FR-DTL-03）")
    func favorite() async throws {
        let dependencies = await makeDependencies()
        let model = RouteDetailModel(selection: try await selection(dependencies), dependencies: dependencies)
        #expect(!model.isFavorite)
        model.toggleFavorite()
        #expect(model.isFavorite)
        guard case .route(let saved) = dependencies.userData.favorites().first?.item else {
            Issue.record("経路のお気に入りになるはず")
            return
        }
        // routeContext ではなく検索条件を保存する（api-contract 4.2）
        #expect(saved.query == sampleQuery)
        model.toggleFavorite()
        #expect(!model.isFavorite)
    }

    @Test("共有するテキストに発着と路線を含める（FR-DTL-04）")
    func share() async throws {
        let dependencies = await makeDependencies()
        let model = RouteDetailModel(selection: try await selection(dependencies), dependencies: dependencies)
        #expect(model.shareText.contains("池袋 → 横浜"))
        #expect(model.shareText.contains("横浜"))
    }
}

@Suite("検索フォーム")
@MainActor
struct SearchFormModelTests {
    @Test("初期値は設定に従い、入れ替えられる（FR-CND-06、FR-SRC-07）")
    func form() async throws {
        let dependencies = await makeDependencies()
        dependencies.settings.fareKind = .ticket
        dependencies.settings.useShinkansen = true
        let form = SearchFormModel(settings: dependencies.settings)
        #expect(form.fareKind == .ticket)
        #expect(form.useShinkansen)
        #expect(!form.canSearch)

        form.from = dependencies.catalog.station(MockID.ikebukuro)
        form.to = dependencies.catalog.station(MockID.yokohama)
        #expect(form.canSearch)
        form.swap()
        let query = try #require(form.makeQuery())
        #expect(query.fromStationId == MockID.yokohama)
        #expect(query.useShinkansen)
    }

    @Test("非対応の地域では経由駅・始発終電を外す（FR-CND-01・02）")
    func removeUnsupported() async {
        let dependencies = await makeDependencies()
        let form = SearchFormModel(settings: dependencies.settings)
        form.from = dependencies.catalog.station("jp.station.osaka")
        form.via = [dependencies.catalog.station("jp.station.shin-osaka")].compactMap { $0 }
        form.searchType = .lastTrain
        form.removeUnsupported(capabilities: dependencies.capabilities.snapshot, region: .kansai)
        #expect(form.via.isEmpty)
        #expect(form.searchType == .departure)
    }
}

@Suite("エラーの見せ方（api-contract 2.3）")
struct ErrorPresentationTests {
    @Test("コードごとの再試行の可否", arguments: [
        ("RATE_LIMITED", true), ("PROVIDER_QUOTA_EXCEEDED", true), ("PROVIDER_UNAVAILABLE", true), ("INTERNAL_ERROR", true),
        ("INVALID_REQUEST", false), ("ATTESTATION_FAILED", false), ("FEATURE_UNAVAILABLE", false),
    ])
    func retryable(code: String, expected: Bool) {
        let error = AppError.api(APIError(code: code, message: "メッセージ", retryable: !expected))
        #expect(error.presentation.retryable == expected)
    }

    @Test("表にないコードは retryable に従う")
    func unknownCode() {
        #expect(AppError.api(APIError(code: "NEW", message: "m", retryable: true)).presentation.retryable)
        #expect(!AppError.api(APIError(code: "NEW", message: "m", retryable: false)).presentation.retryable)
    }

    @Test("ATTESTATION_FAILED は「通信できませんでした」")
    func attestation() {
        #expect(AppError.api(APIError(code: "ATTESTATION_FAILED", message: "x", retryable: false)).presentation.message == "通信できませんでした")
    }
}
