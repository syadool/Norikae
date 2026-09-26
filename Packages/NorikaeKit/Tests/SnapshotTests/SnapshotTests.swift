import DesignSystem
import Domain
import LiveGuidance
import NorikaeData
import SnapshotTesting
import SwiftUI
import XCTest

/// スナップショットテスト（frontend.md 12.1）
///
/// 初回の実行では参照画像を記録して失敗する（swift-snapshot-testing の仕様）。記録した `__Snapshots__` をコミットして 2 回目から比較する。
/// iPhone 16 のシミュレーター（iOS 18）で記録すること。
@MainActor
final class SnapshotTests: XCTestCase {
    /// 2026-09-26 08:05 JST（モックの経路の基準）
    private let base: Date = {
        var components = DateComponents()
        components.year = 2026
        components.month = 9
        components.day = 26
        components.hour = 8
        components.minute = 5
        return JapanCalendar.calendar.date(from: components)!
    }()

    private let catalog = MockData.catalog

    private func routes(_ scenario: MockScenario = .standard) async throws -> RouteSearchResult {
        let query = RouteSearchQuery(fromStationId: MockID.ikebukuro, toStationId: MockID.yokohama, dateTime: base)
        return try await MockRouteRepository(scenario: scenario, latency: .zero).searchRoutes(query)
    }

    private func columns(_ result: RouteSearchResult, fareKind: FareKind = .ic) -> [CompareColumn] {
        let badges = RouteRanking.badges(for: result.routes, fareKind: fareKind)
        return RouteRanking.sorted(result.routes, by: .fastest, fareKind: fareKind).map {
            CompareColumn(route: $0, badges: badges[$0.id] ?? [], fare: $0.fare.display(preferred: fareKind))
        }
    }

    private static let appearances: [(String, UIUserInterfaceStyle, UIContentSizeCategory)] = [
        ("light", .light, .large),
        ("dark", .dark, .large),
        ("light-xxxl", .light, .extraExtraExtraLarge),
        ("light-ax3", .light, .accessibilityExtraExtraLarge),
    ]

    /// - Parameter accessibilityHeight: アクセシビリティサイズで使う高さ。内容が縦に伸びて `height` に収まらない画面で指定する
    private func assertScreens<V: View>(
        _ view: V, height: CGFloat = 700, accessibilityHeight: CGFloat? = nil, named name: String,
        file: StaticString = #filePath, testName: String = #function, line: UInt = #line
    ) {
        for (label, style, size) in Self.appearances {
            let traits = UITraitCollection { traits in
                traits.userInterfaceStyle = style
                traits.preferredContentSizeCategory = size
            }
            let screenHeight = size.isAccessibilityCategory ? accessibilityHeight ?? height : height
            let screen = view
                .frame(width: 390, height: screenHeight)
                .background(NKColor.background)
            assertSnapshot(
                of: screen, as: .image(layout: .fixed(width: 390, height: screenHeight), traits: traits),
                named: "\(name)-\(label)", file: file, testName: testName, line: line
            )
        }
    }

    // MARK: 縦比較

    func testCompareStandard() async throws {
        let result = try await routes()
        assertScreens(RouteCompareView(columns: columns(result), catalog: catalog) { _ in }.padding(16), named: "compare")
    }

    func testCompareFareVariantsAndNoSymbol() async throws {
        assertScreens(RouteCompareView(columns: columns(try await routes(.fareVariants)), catalog: catalog) { _ in }.padding(16), named: "compare-fares")
        let noSymbol = try await routes(.noSymbolLine)
        let merged = catalog.merging(noSymbol.includes)
        assertScreens(RouteCompareView(columns: columns(noSymbol), catalog: merged) { _ in }.padding(16), named: "compare-no-symbol")
    }

    func testCompareWideSpreadAndTransfers() async throws {
        assertScreens(RouteCompareView(columns: columns(try await routes(.wideSpread)), catalog: catalog) { _ in }.padding(16), named: "compare-wide")
        assertScreens(RouteCompareView(columns: columns(try await routes(.manyTransfers)), catalog: catalog) { _ in }.padding(16), named: "compare-transfers")
    }

    func testCompareSkeleton() {
        assertScreens(RouteCompareSkeleton().padding(16), named: "compare-skeleton")
    }

    // MARK: 縦タイムライン

    func testTimeline() async throws {
        let result = try await routes()
        let capabilities = MockData.capabilities(now: base)
        for route in result.routes.prefix(4) {
            let view = ScrollView {
                RouteTimelineView(route: route, catalog: catalog, capabilities: capabilities, onSelectStopList: { _ in }, onShowStationMap: { _ in })
                    .padding(16)
            }
            assertScreens(view, height: 900, named: "timeline-\(route.id)")
        }
    }

    // MARK: 非対応・情報なし

    func testUnsupportedAndUnknown() {
        let view = VStack(alignment: .leading, spacing: 12) {
            ForEach(OperationStatusKind.allCases, id: \.self) { kind in
                OperationStatusLabel(kind, summary: "お知らせ")
            }
            UnsupportedNotice(.viaStations)
            UnsupportedNotice(.timetable)
            UnsupportedBadge(.operationAlerts)
            ScheduledTimeNote()
            DataNoticeBanner(.cached(asOf: base))
            DataNoticeBanner(.partial)
            ErrorStateView(message: "通信できませんでした", retryable: true) {}
        }
        .padding(16)
        assertScreens(view, height: 820, accessibilityHeight: 1800, named: "states")
    }

    // MARK: Live Activity

    private func display(scenario: MockScenario = .standard, routeIndex: Int, minutesAfterBase: Int, notice: LiveRouteState.LocalNotice? = nil) async throws -> GuidanceDisplay {
        let result = try await routes(scenario)
        let route = result.routes[routeIndex]
        let summary = GuidanceSummary(
            route: route, catalog: catalog, capabilities: MockData.capabilities(now: base),
            fallbackStationName: "駅名不明", fallbackTrainTypeName: ""
        )
        var state = LiveRouteState(route: route, now: base)
        state.localNotice = notice
        return GuidanceDisplay(summary: summary, state: state, now: base.addingTimeInterval(TimeInterval(minutesAfterBase * 60)))
    }

    private func assertLiveActivity<V: View>(_ view: V, width: CGFloat, height: CGFloat, named name: String, testName: String = #function) {
        assertSnapshot(
            of: view.frame(width: width, height: height).background(Color.black),
            as: .image(layout: .fixed(width: width, height: height)),
            named: name, testName: testName
        )
    }

    func testLiveActivityLockScreen() async throws {
        // 副都心線（リアルタイム対応）→ 東横線（非対応：時刻表どおりの表示）
        let transfer = try await display(routeIndex: 1, minutesAfterBase: 1)
        assertLiveActivity(GuidanceLockScreenView(display: transfer) { actions }, width: 370, height: 330, named: "lock-transfer")

        // 遅延を含む経路（山手線 3 分遅れ）
        let delayed = try await display(routeIndex: 2, minutesAfterBase: 0)
        assertLiveActivity(GuidanceLockScreenView(display: delayed) { actions }, width: 370, height: 340, named: "lock-delayed")

        // オフラインで「1本後に変更」したとき
        let offline = try await display(routeIndex: 0, minutesAfterBase: 2, notice: .offlineChangeFailed)
        assertLiveActivity(GuidanceLockScreenView(display: offline) { actions }, width: 370, height: 340, named: "lock-offline")
    }

    func testDynamicIslandAndWatch() async throws {
        let display = try await display(routeIndex: 1, minutesAfterBase: 1)
        assertLiveActivity(GuidanceIslandExpandedBottom(display: display).padding(16), width: 370, height: 170, named: "island-expanded")
        assertLiveActivity(HStack { GuidanceCompactLeading(display: display); Spacer(); GuidanceCompactTrailing(display: display) }.padding(8), width: 200, height: 40, named: "island-compact")
        assertLiveActivity(GuidanceMinimal(display: display), width: 36, height: 36, named: "island-minimal")
        assertLiveActivity(GuidanceWatchView(display: display).background(NKLiveActivityColor.surface), width: 184, height: 110, named: "watch")
    }

    private var actions: some View {
        HStack(spacing: 8) {
            GuidanceActionLabel.later()
            GuidanceActionLabel.end()
        }
    }
}
