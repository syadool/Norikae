import DesignSystem
import Domain
import SwiftUI

/// Live Activity の表示に必要な値をまとめたもの（ロック画面・Dynamic Island・Watch で共通）
public struct GuidanceDisplay: Sendable {
    public var summary: GuidanceSummary
    public var state: LiveRouteState
    public var now: Date
    /// `stale-date` を過ぎた（ActivityKit の `context.isStale`）
    public var isStale: Bool
    public var progress: GuidanceProgress

    public init(summary: GuidanceSummary, state: LiveRouteState, now: Date = Date(), isStale: Bool = false) {
        self.summary = summary
        self.state = state
        self.now = now
        self.isStale = isStale
        self.progress = GuidanceProgress(state: state, now: now)
    }

    /// 次に乗る（乗っている）区間。到着後は最後の区間
    public var currentIndex: Int {
        progress.currentLegIndex ?? max(summary.legs.count - 1, 0)
    }

    public var currentInfo: GuidanceSummary.LegInfo? {
        summary.legs.indices.contains(currentIndex) ? summary.legs[currentIndex] : nil
    }

    public var currentState: LiveRouteState.LegState? {
        state.legs.first { $0.index == currentIndex }
    }

    public var appearance: LineAppearance? {
        currentInfo.map(LineAppearance.init(summary:))
    }

    /// 発車まで（乗車中は到着まで）のカウントダウンの終わり
    public var countdownTarget: Date? { progress.nextEventDate }

    public var isRiding: Bool {
        if case .riding = progress.phase { return true }
        return false
    }

    public var hasArrived: Bool { progress.phase == .arrived }

    /// 次の乗換（駅名と到着時刻）
    public var nextTransfer: (stationName: String, time: Date)? {
        guard currentIndex < summary.legs.count - 1, let leg = currentState else { return nil }
        return (summary.legs[currentIndex].toStationName, leg.arrivalDate)
    }

    public var finalArrival: Date? { state.finalArrival }

    /// 最後の区間の遅延（分）。リアルタイム情報がなければ `nil`
    public var arrivalDelay: Int? { state.legs.last?.delayMinutes }

    /// 今の区間がリアルタイム情報に対応していない（「時刻表どおりの表示」と示す）
    public var isScheduleOnly: Bool { !(currentInfo?.hasRealtime ?? false) }
}

// MARK: - 共通部品

enum LA {
    static let surface = NKLiveActivityColor.surface
    static let subSurface = NKLiveActivityColor.subSurface
    static let primary = NKLiveActivityColor.textPrimary
    static let secondary = NKLiveActivityColor.textSecondary
    static let delay = NKLiveActivityColor.delayText
    static let delayFill = NKLiveActivityColor.delayFill
}

/// カウントダウン（`Text(timerInterval:)` で端末だけで進める、FR-LA-10）
public struct GuidanceCountdown: View {
    private let target: Date?
    private let now: Date
    private let size: CGFloat

    public init(target: Date?, now: Date, size: CGFloat) {
        self.target = target
        self.now = now
        self.size = size
    }

    public var body: some View {
        Group {
            if let target, target > now {
                Text(timerInterval: now...target, countsDown: true, showsHours: false)
            } else {
                Text("0:00", bundle: .module)
            }
        }
        .font(.system(size: size, weight: .bold).monospacedDigit())
        .foregroundStyle(LA.primary)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }
}

/// 進み具合のバー（区間ごとに路線色で区切り、現在地に白い丸）
public struct GuidanceProgressBar: View {
    private let display: GuidanceDisplay
    private let height: CGFloat
    private let showsLabels: Bool

    public init(display: GuidanceDisplay, height: CGFloat = 6, showsLabels: Bool = true) {
        self.display = display
        self.height = height
        self.showsLabels = showsLabels
    }

    public var body: some View {
        VStack(spacing: 4) {
            GeometryReader { geometry in
                let segments = segmentFractions
                let gap: CGFloat = 3
                let usable = max(geometry.size.width - gap * CGFloat(max(segments.count - 1, 0)), 1)
                ZStack(alignment: .leading) {
                    HStack(spacing: gap) {
                        ForEach(Array(segments.enumerated()), id: \.offset) { index, fraction in
                            Capsule()
                                .fill(color(at: index))
                                .frame(width: max(usable * fraction, height))
                        }
                    }
                    Circle()
                        .fill(Color.white)
                        .frame(width: 14, height: 14)
                        .offset(x: min(max(geometry.size.width * display.progress.fraction - 7, 0), geometry.size.width - 14))
                }
                .frame(height: 14)
            }
            .frame(height: 14)
            if showsLabels {
                HStack {
                    Text(display.summary.originName)
                    Spacer(minLength: 4)
                    if display.summary.legs.count == 2 {
                        Text(display.summary.legs[0].toStationName)
                        Spacer(minLength: 4)
                    }
                    Text(display.summary.destinationName)
                }
                .font(.system(size: 11))
                .foregroundStyle(LA.secondary)
                .lineLimit(1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("進み具合 \(Int(display.progress.fraction * 100))パーセント", bundle: .module))
    }

    private var segmentFractions: [CGFloat] {
        let legs = display.state.legs
        guard let start = legs.first?.scheduledDepartureDate, let end = legs.last?.scheduledArrivalDate, end > start else {
            return Array(repeating: 1 / CGFloat(max(legs.count, 1)), count: max(legs.count, 1))
        }
        let total = end.timeIntervalSince(start)
        return legs.map { CGFloat(max($0.scheduledArrivalDate.timeIntervalSince($0.scheduledDepartureDate), 60) / total) }
    }

    private func color(at index: Int) -> Color {
        guard display.summary.legs.indices.contains(index) else { return LA.secondary }
        return LineAppearance(summary: display.summary.legs[index]).colorOnDarkSurface
    }
}

/// 暗い面に置く番線の札
struct LAPlatformPill: View {
    let platform: String?

    var body: some View {
        if let platform {
            PlatformPill(platform, fill: LA.subSurface, foreground: LA.primary)
        }
    }
}

/// 注意の行（遅延・運休・未確認・古い情報・時刻表どおりの表示）
struct GuidanceNotices: View {
    let display: GuidanceDisplay
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let notice = display.state.localNotice {
                HStack(spacing: 6) {
                    Text("未確認", bundle: .module)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(LA.delay)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(LA.delayFill, in: Capsule())
                    Text(noticeText(notice))
                        .font(.system(size: 12))
                        .foregroundStyle(LA.delay)
                }
            }
            if display.currentState?.isCancelled == true {
                label(String(localized: "この列車は運休です", bundle: .module), icon: "xmark.octagon.fill")
            }
            if let summary = display.state.disruptionSummary {
                label(summary, icon: "exclamationmark.triangle.fill")
            }
            if display.isStale {
                label(String(localized: "情報が古い可能性があります", bundle: .module), icon: "clock.arrow.circlepath")
            } else if display.isScheduleOnly, !compact {
                // リアルタイム情報がない区間では「遅延なし」と見せない（FR-LA-12）
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                    Text("時刻表どおりの表示", bundle: .module)
                }
                .font(.system(size: 12))
                .foregroundStyle(LA.secondary)
            }
        }
        .lineLimit(2)
    }

    private func label(_ text: String, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            Text(text)
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(LA.delay)
    }

    private func noticeText(_ notice: LiveRouteState.LocalNotice) -> String {
        switch notice {
        case .offlineChangeFailed: String(localized: "オフラインのため変更できません", bundle: .module)
        case .changeFailed: String(localized: "1本後の経路を取得できませんでした", bundle: .module)
        case .reopenAppToChange: String(localized: "経路が変わるため、アプリを開いて案内し直してください", bundle: .module)
        }
    }
}

/// 「到着 8:54 +2分」
struct ArrivalText: View {
    let display: GuidanceDisplay
    var size: CGFloat = 13

    var body: some View {
        if let arrival = display.finalArrival {
            HStack(spacing: 4) {
                Text("到着", bundle: .module).foregroundStyle(LA.secondary)
                Text(NKFormat.time(arrival)).foregroundStyle(LA.primary).fontWeight(.semibold)
                if let delay = display.arrivalDelay, delay > 0 {
                    Text("+\(delay)分", bundle: .module).foregroundStyle(LA.delay).fontWeight(.bold)
                }
            }
            .font(.system(size: size).monospacedDigit())
        }
    }
}

// MARK: - ロック画面・展開した Dynamic Island

/// ロック画面（design-spec 7.8）
public struct GuidanceLockScreenView<Actions: View>: View {
    private let display: GuidanceDisplay
    private let actions: Actions

    public init(display: GuidanceDisplay, @ViewBuilder actions: () -> Actions) {
        self.display = display
        self.actions = actions()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GuidanceLegHeader(display: display)

            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(countdownLabel)
                        .font(.system(size: 12))
                        .foregroundStyle(LA.secondary)
                    if display.hasArrived {
                        Text("到着しました", bundle: .module)
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(LA.primary)
                    } else {
                        GuidanceCountdown(target: display.countdownTarget, now: display.now, size: 48)
                    }
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 4) {
                    if let transfer = display.nextTransfer {
                        HStack(spacing: 4) {
                            Text("乗換", bundle: .module).foregroundStyle(LA.secondary)
                            Text(transfer.stationName).foregroundStyle(LA.primary).fontWeight(.semibold)
                            Text(NKFormat.time(transfer.time)).foregroundStyle(LA.primary)
                        }
                        .font(.system(size: 13).monospacedDigit())
                    }
                    ArrivalText(display: display)
                }
                .lineLimit(1)
            }

            GuidanceProgressBar(display: display)
            GuidanceNotices(display: display)
            actions
        }
        .padding(16)
        .background(LA.surface)
    }

    private var countdownLabel: String {
        if display.hasArrived { return "" }
        return display.isRiding ? String(localized: "到着まで", bundle: .module) : String(localized: "発車まで", bundle: .module)
    }
}

/// 路線記号チップ｜「副都心線 急行」｜行き先｜番線
public struct GuidanceLegHeader: View {
    private let display: GuidanceDisplay

    public init(display: GuidanceDisplay) {
        self.display = display
    }

    public var body: some View {
        HStack(spacing: 8) {
            if let appearance = display.appearance, let info = display.currentInfo {
                LineSymbolChip(appearance, size: .detail, surface: LA.subSurface, foreground: LA.primary)
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(info.lineName) \(info.trainTypeName)", bundle: .module)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(LA.primary)
                    Text(info.destinationName)
                        .font(.system(size: 12))
                        .foregroundStyle(LA.secondary)
                }
                .lineLimit(1)
            }
            Spacer(minLength: 4)
            LAPlatformPill(platform: display.currentState?.platform)
        }
    }
}

/// 「1本後に変更」「案内終了」の見た目（ボタンの中身）
public struct GuidanceActionLabel: View {
    private let title: String
    private let systemImage: String

    public init(title: String, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
    }

    public static func later() -> GuidanceActionLabel {
        GuidanceActionLabel(title: String(localized: "1本後に変更", bundle: .module), systemImage: "arrow.forward.circle")
    }

    public static func end() -> GuidanceActionLabel {
        GuidanceActionLabel(title: String(localized: "案内終了", bundle: .module), systemImage: "xmark.circle")
    }

    public var body: some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(LA.primary)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(LA.subSurface, in: RoundedRectangle(cornerRadius: NKRadius.md, style: .continuous))
    }
}

// MARK: - Dynamic Island

/// 展開：中央〜下の部分
public struct GuidanceIslandExpandedBottom: View {
    private let display: GuidanceDisplay

    public init(display: GuidanceDisplay) {
        self.display = display
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .lastTextBaseline) {
                if display.hasArrived {
                    Text("到着しました", bundle: .module)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(LA.primary)
                } else {
                    GuidanceCountdown(target: display.countdownTarget, now: display.now, size: 40)
                        .frame(maxWidth: 150, alignment: .leading)
                    Text(display.isRiding ? String(localized: "で到着", bundle: .module) : String(localized: "で発車", bundle: .module))
                        .font(.system(size: 13))
                        .foregroundStyle(LA.secondary)
                }
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 2) {
                    if let transfer = display.nextTransfer {
                        Text("乗換 \(transfer.stationName) \(NKFormat.time(transfer.time))", bundle: .module)
                            .font(.system(size: 12).monospacedDigit())
                            .foregroundStyle(LA.primary)
                    }
                    ArrivalText(display: display, size: 12)
                }
                .lineLimit(1)
            }
            GuidanceProgressBar(display: display, height: 5, showsLabels: false)
            GuidanceNotices(display: display, compact: true)
        }
    }
}

/// コンパクト：左（路線色の丸に記号の頭文字）
public struct GuidanceCompactLeading: View {
    private let display: GuidanceDisplay

    public init(display: GuidanceDisplay) {
        self.display = display
    }

    public var body: some View {
        let appearance = display.appearance
        ZStack {
            Circle().fill(appearance?.colorOnDarkSurface ?? LA.secondary)
            Text(String(appearance?.label.prefix(1) ?? ""))
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: 22, height: 22)
        .accessibilityLabel(Text(appearance?.name ?? ""))
    }
}

/// コンパクト：右（カウントダウン）
public struct GuidanceCompactTrailing: View {
    private let display: GuidanceDisplay

    public init(display: GuidanceDisplay) {
        self.display = display
    }

    public var body: some View {
        GuidanceCountdown(target: display.countdownTarget, now: display.now, size: 16)
            .frame(maxWidth: 52)
    }
}

/// 最小：黒い丸に路線色の輪（3pt）、中に残り時間
public struct GuidanceMinimal: View {
    private let display: GuidanceDisplay

    public init(display: GuidanceDisplay) {
        self.display = display
    }

    public var body: some View {
        ZStack {
            Circle().fill(NKLiveActivityColor.islandBackground)
            Circle().strokeBorder(display.appearance?.colorOnDarkSurface ?? LA.secondary, lineWidth: 3)
            if let target = display.countdownTarget, target > display.now {
                Text(timerInterval: display.now...target, countsDown: true, showsHours: false)
                    .font(.system(size: 8, weight: .bold).monospacedDigit())
                    .foregroundStyle(LA.primary)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.5)
                    .padding(4)
            }
        }
    }
}

// MARK: - Apple Watch（スマートスタック）

/// Watch のスマートスタック（design-spec 7.8：チップ＋種別／番線、カウントダウン 36、行き先と到着時刻 11）
public struct GuidanceWatchView: View {
    private let display: GuidanceDisplay

    public init(display: GuidanceDisplay) {
        self.display = display
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                if let appearance = display.appearance {
                    LineSymbolChip(appearance, size: .compare, surface: LA.subSurface, foreground: LA.primary)
                }
                Text(display.currentInfo?.trainTypeName ?? "")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(LA.primary)
                Spacer(minLength: 2)
                if let platform = display.currentState?.platform {
                    Text("\(platform)番線", bundle: .module)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(LA.secondary)
                }
            }
            if display.hasArrived {
                Text("到着しました", bundle: .module)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(LA.primary)
            } else {
                GuidanceCountdown(target: display.countdownTarget, now: display.now, size: 36)
            }
            HStack(spacing: 4) {
                Text(display.currentInfo?.destinationName ?? "")
                Spacer(minLength: 2)
                if let arrival = display.finalArrival {
                    Text("着 \(NKFormat.time(arrival))", bundle: .module)
                }
            }
            .font(.system(size: 11).monospacedDigit())
            .foregroundStyle(LA.secondary)
            .lineLimit(1)
            if display.isScheduleOnly {
                Text("時刻表どおりの表示", bundle: .module)
                    .font(.system(size: 10))
                    .foregroundStyle(LA.secondary)
            }
        }
        .padding(8)
    }
}
