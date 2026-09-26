import Domain
import Foundation

#if canImport(ActivityKit) && os(iOS)
import ActivityKit

/// 案内の Live Activity（frontend.md 6 章、api-contract 5.3）
///
/// - `ContentState`：プッシュで送られる動的な情報。日時は UNIX 時刻の `Int`（`LiveRouteState`、Domain に置く）
/// - 属性：開始後に変わらない情報（出発駅・到着駅、区間ごとの路線・種別・行き先、リアルタイム情報の有無）
public struct NavigationActivityAttributes: ActivityAttributes {
    public typealias ContentState = LiveRouteState

    public var summary: GuidanceSummary

    public init(summary: GuidanceSummary) {
        self.summary = summary
    }
}
#endif

/// `LiveActivityIntent`（「1本後に変更」「案内終了」）をアプリ本体の処理につなぐ
///
/// インテントの型はアプリと Widget Extension の両方でコンパイルするが、`LiveActivityIntent` はアプリ本体のプロセスで実行される
/// （frontend.md 9.2）。アプリは起動時に `handler` を登録する。
@MainActor
public protocol GuidanceIntentHandling: AnyObject {
    func shiftToLaterTrain(activityID: String) async
    func endGuidance(activityID: String) async
}

@MainActor
public final class GuidanceIntentBridge {
    public static let shared = GuidanceIntentBridge()
    public weak var handler: (any GuidanceIntentHandling)?

    private init() {}

    public static func shiftToLaterTrain(activityID: String) async {
        await shared.handler?.shiftToLaterTrain(activityID: activityID)
    }

    public static func endGuidance(activityID: String) async {
        await shared.handler?.endGuidance(activityID: activityID)
    }
}
