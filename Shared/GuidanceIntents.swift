// アプリ本体と Widget Extension の両方でコンパイルする（project.yml で両方のターゲットに含める）。
// LiveActivityIntent はアプリ本体のプロセスで実行されるため、処理は GuidanceIntentBridge 経由でアプリの GuidanceController が行う。

import AppIntents
import LiveGuidance

/// 「1本後に変更」（FR-LA-20）
struct ShiftToLaterTrainIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "1本後に変更"
    static let isDiscoverable = false

    @Parameter(title: "案内の ID")
    var activityID: String

    init() {}

    init(activityID: String) {
        self.activityID = activityID
    }

    func perform() async throws -> some IntentResult {
        await GuidanceIntentBridge.shiftToLaterTrain(activityID: activityID)
        return .result()
    }
}

/// 「案内終了」（FR-LA-22）
struct EndGuidanceIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "案内終了"
    static let isDiscoverable = false

    @Parameter(title: "案内の ID")
    var activityID: String

    init() {}

    init(activityID: String) {
        self.activityID = activityID
    }

    func perform() async throws -> some IntentResult {
        await GuidanceIntentBridge.endGuidance(activityID: activityID)
        return .result()
    }
}
