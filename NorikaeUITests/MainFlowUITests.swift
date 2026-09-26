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
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("いけぶくろ")
        let ikebukuro = app.buttons["stationRow-池袋"]
        XCTAssertTrue(ikebukuro.waitForExistence(timeout: 5))
        ikebukuro.tap()

        // 到着駅
        app.buttons["toStationField"].tap()
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("よこはま")
        let yokohama = app.buttons["stationRow-横浜"]
        XCTAssertTrue(yokohama.waitForExistence(timeout: 5))
        yokohama.tap()

        // 検索 → 縦比較
        app.buttons["searchButton"].tap()
        let firstColumn = app.buttons["compareColumn-0"]
        XCTAssertTrue(firstColumn.waitForExistence(timeout: 10))
        firstColumn.tap()

        // 経路詳細 → 案内開始
        let start = app.buttons["startGuidanceButton"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()

        // 案内中になると「案内終了」に変わる。
        // シミュレーターで通知の許可ダイアログが出た場合は許可する。
        addUIInterruptionMonitor(withDescription: "通知の許可") { alert in
            alert.buttons.element(boundBy: 1).tap()
            return true
        }
        app.tap()
        XCTAssertTrue(app.buttons["endGuidanceButton"].waitForExistence(timeout: 10))
    }
}
