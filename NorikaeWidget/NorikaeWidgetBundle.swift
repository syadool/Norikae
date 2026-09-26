import ActivityKit
import DesignSystem
import Domain
import LiveGuidance
import SwiftUI
import WidgetKit

@main
struct NorikaeWidgetBundle: WidgetBundle {
    var body: some Widget {
        NavigationLiveActivityWidget()
    }
}

/// 案内の Live Activity（frontend.md 6 章、design-spec 7.8）
struct NavigationLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: NavigationActivityAttributes.self) { context in
            LockScreenOrWatchView(context: context)
                .activityBackgroundTint(NKLiveActivityColor.surface)
                .activitySystemActionForegroundColor(NKLiveActivityColor.textPrimary)
        } dynamicIsland: { context in
            let display = GuidanceDisplay(summary: context.attributes.summary, state: context.state, isStale: context.isStale)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    if let appearance = display.appearance {
                        HStack(spacing: 6) {
                            LineSymbolChip(appearance, size: .detail, surface: NKLiveActivityColor.subSurface, foreground: NKLiveActivityColor.textPrimary)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(display.currentInfo?.trainTypeName ?? "")
                                    .font(.system(size: 13, weight: .bold))
                                Text(display.currentInfo?.destinationName ?? "")
                                    .font(.system(size: 11))
                                    .foregroundStyle(NKLiveActivityColor.textSecondary)
                            }
                            .lineLimit(1)
                        }
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if let platform = display.currentState?.platform {
                        PlatformPill(platform, fill: NKLiveActivityColor.subSurface, foreground: NKLiveActivityColor.textPrimary)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 8) {
                        GuidanceIslandExpandedBottom(display: display)
                        GuidanceActions(activityID: context.activityID)
                    }
                }
            } compactLeading: {
                GuidanceCompactLeading(display: display)
            } compactTrailing: {
                GuidanceCompactTrailing(display: display)
            } minimal: {
                GuidanceMinimal(display: display)
            }
            .keylineTint(display.appearance?.colorOnDarkSurface ?? NKLiveActivityColor.textSecondary)
        }
        // Apple Watch のスマートスタックに出す（FR-WCH-01）
        .supplementalActivityFamilies([.small])
    }
}

/// ロック画面と Watch（`.small`）の出し分け
struct LockScreenOrWatchView: View {
    let context: ActivityViewContext<NavigationActivityAttributes>
    @Environment(\.activityFamily) private var activityFamily

    var body: some View {
        let display = GuidanceDisplay(summary: context.attributes.summary, state: context.state, isStale: context.isStale)
        switch activityFamily {
        case .small:
            GuidanceWatchView(display: display)
        default:
            GuidanceLockScreenView(display: display) {
                GuidanceActions(activityID: context.activityID)
            }
        }
    }
}

/// 「1本後に変更」「案内終了」（LiveActivityIntent、FR-LA-20・22）
struct GuidanceActions: View {
    let activityID: String

    var body: some View {
        HStack(spacing: 8) {
            Button(intent: ShiftToLaterTrainIntent(activityID: activityID)) {
                GuidanceActionLabel.later()
            }
            .buttonStyle(.plain)
            Button(intent: EndGuidanceIntent(activityID: activityID)) {
                GuidanceActionLabel.end()
            }
            .buttonStyle(.plain)
        }
    }
}
