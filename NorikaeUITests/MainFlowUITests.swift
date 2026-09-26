import XCTest

/// 主要な流れ 1 本：検索 → 縦比較 → 経路詳細 → 案内開始（frontend.md 12.1）
///
/// モックの Repository で動かす（`-UseMockData`）。
final class MainFlowUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testSearchCompareDetailAndStartGuidance() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UseMockData", "-ResetUserData", "-Region", "kanto", "-MockScenario", "standard"]
        app.launch()

        // 出発駅
        app.buttons["fromStationField"].tap()
        let field = app.textFields["stationSearchField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "駅の検索欄が出ない（出発）")
        field.typeText("いけぶくろ")
        let ikebukuro = app.buttons["stationRow-池袋"]
        XCTAssertTrue(ikebukuro.waitForExistence(timeout: 5), "候補に池袋が出ない")
        ikebukuro.tap()

        // 到着駅
        app.buttons["toStationField"].tap()
        XCTAssertTrue(field.waitForExistence(timeout: 5), "駅の検索欄が出ない（到着）")
        field.typeText("よこはま")
        let yokohama = app.buttons["stationRow-横浜"]
        XCTAssertTrue(yokohama.waitForExistence(timeout: 5), "候補に横浜が出ない")
        yokohama.tap()

        // 検索 → 縦比較
        app.buttons["searchButton"].tap()
        let firstColumn = app.buttons["compareColumn-0"]
        XCTAssertTrue(firstColumn.waitForExistence(timeout: 10), "縦比較の列が出ない")
        firstColumn.tap()

        // 経路詳細 → 案内開始
        let start = app.buttons["startGuidanceButton"]
        XCTAssertTrue(start.waitForExistence(timeout: 5), "「案内開始」が出ない")
        start.tap()

        // 案内中になると「案内終了」に変わる。
        // 開始時に通知（続けて位置情報）の許可ダイアログが出る。iOS 17 以降は addUIInterruptionMonitor が
        // 発火しないことがあるので、SpringBoard のダイアログを直接押す（2 番目のボタン＝許可）
        let end = app.buttons["endGuidanceButton"]
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        var attempts = 0
        while !end.exists, attempts < 5 {
            attempts += 1
            let alert = springboard.alerts.firstMatch
            if alert.waitForExistence(timeout: 3) {
                alert.buttons.element(boundBy: 1).tap()
            }
        }
        XCTAssertTrue(end.waitForExistence(timeout: 10), "「案内終了」に変わらない")
    }
}
