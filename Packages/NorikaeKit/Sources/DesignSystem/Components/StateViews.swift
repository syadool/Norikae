import Domain
import SwiftUI

// MARK: - 非対応（FR-CAP-02、FR-CAP-04）

/// 非対応の表示の文言。画面間でそろえるため、ここだけで定義する（frontend.md 14 章 #7 の案）
public enum UnsupportedText {
    /// 短い札の文言
    public static func label(_ feature: CapabilityFeature) -> String {
        switch feature {
        case .viaStations: String(localized: "経由駅非対応", bundle: .module)
        case .firstLastTrain: String(localized: "始発・終電非対応", bundle: .module)
        case .timetable: String(localized: "時刻表非対応", bundle: .module)
        case .stopList: String(localized: "停車駅一覧非対応", bundle: .module)
        case .operationAlerts: String(localized: "運行情報非対応", bundle: .module)
        case .boardingPosition: String(localized: "乗車位置非対応", bundle: .module)
        case .tripUpdates: String(localized: "時刻表どおりの表示", bundle: .module)
        case .platform: String(localized: "番線非対応", bundle: .module)
        case .fare: String(localized: "運賃非対応", bundle: .module)
        case .routeSearch: String(localized: "経路検索非対応", bundle: .module)
        case .vehiclePositions: String(localized: "非対応", bundle: .module)
        }
    }

    /// 説明文
    public static func explanation(_ feature: CapabilityFeature) -> String {
        switch feature {
        case .viaStations: String(localized: "この地域では、経由駅を指定した検索に対応していません。", bundle: .module)
        case .firstLastTrain: String(localized: "この地域では、始発・終電の検索に対応していません。", bundle: .module)
        case .timetable: String(localized: "この路線の時刻表には対応していません。", bundle: .module)
        case .stopList: String(localized: "この列車の停車駅一覧には対応していません。", bundle: .module)
        case .operationAlerts: String(localized: "この路線の運行情報には対応していません。", bundle: .module)
        case .boardingPosition: String(localized: "この路線の乗車位置の情報には対応していません。", bundle: .module)
        case .tripUpdates: String(localized: "リアルタイムの情報に対応していない区間です。遅れがあっても反映されません。", bundle: .module)
        case .platform: String(localized: "この路線の番線の情報には対応していません。", bundle: .module)
        case .fare: String(localized: "この路線の運賃には対応していません。", bundle: .module)
        case .routeSearch: String(localized: "この路線の経路検索には対応していません。", bundle: .module)
        case .vehiclePositions: String(localized: "この機能には対応していません。", bundle: .module)
        }
    }
}

/// 非対応の札。ボタンを隠さずに、選べない状態と一緒に使う
public struct UnsupportedBadge: View {
    private let feature: CapabilityFeature

    public init(_ feature: CapabilityFeature) {
        self.feature = feature
    }

    public var body: some View {
        Label {
            Text(UnsupportedText.label(feature))
        } icon: {
            Image(systemName: "circle.slash")
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(NKColor.textTertiary)
        .labelStyle(.titleAndIcon)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(NKColor.fillPill, in: Capsule())
        .fixedSize()
    }
}

/// 非対応の説明（札＋説明文）
public struct UnsupportedNotice: View {
    private let feature: CapabilityFeature

    public init(_ feature: CapabilityFeature) {
        self.feature = feature
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            UnsupportedBadge(feature)
            Text(UnsupportedText.explanation(feature))
                .font(.caption)
                .foregroundStyle(NKColor.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

/// リアルタイム非対応の区間の印（FR-DTL-11：「定刻」と表示しない）
public struct ScheduledTimeNote: View {
    private let compact: Bool

    public init(compact: Bool = false) {
        self.compact = compact
    }

    public var body: some View {
        Label {
            if compact {
                Text("時刻表上の時刻", bundle: .module)
            } else {
                Text("時刻表上の時刻（遅れは反映されません）", bundle: .module)
            }
        } icon: {
            Image(systemName: "clock.badge.questionmark")
        }
        .font(.caption)
        .foregroundStyle(NKColor.textTertiary)
    }
}

// MARK: - 情報の鮮度（FR-CMP-12、FR-OFF-02、10.3）

/// キャッシュ・古い情報・一部欠損の表示。エラー表示と見た目をそろえる
public struct DataNoticeBanner: View {
    public enum Kind: Hashable, Sendable {
        /// キャッシュを表示している（オフラインなど）
        case cached(asOf: Date)
        /// `isStale: true` の応答
        case stale(asOf: Date)
        /// `partialResult: true` の応答
        case partial
        /// オフライン
        case offline
    }

    private let kind: Kind

    public init(_ kind: Kind) {
        self.kind = kind
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(NKColor.delayText)
            Text(message)
                .font(.footnote)
                .foregroundStyle(NKColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(NKStatusColor.delayed.fill ?? NKColor.fillPill, in: RoundedRectangle(cornerRadius: NKRadius.md, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var icon: String {
        switch kind {
        case .cached, .stale: "clock.arrow.circlepath"
        case .partial: "exclamationmark.circle"
        case .offline: "wifi.slash"
        }
    }

    private var message: String {
        switch kind {
        case .cached(let date):
            String(localized: "\(NKFormat.time(date)) 時点の情報を表示しています", bundle: .module)
        case .stale(let date):
            String(localized: "\(NKFormat.time(date)) 時点の情報です。最新ではない可能性があります", bundle: .module)
        case .partial:
            String(localized: "一部の情報を取得できませんでした", bundle: .module)
        case .offline:
            String(localized: "オフラインです", bundle: .module)
        }
    }
}

// MARK: - エラー・空の状態・読み込み中（10.3）

/// 画面内のエラー表示。アラートは使わない。再試行ボタンは `retryable` のときだけ出す
public struct ErrorStateView: View {
    private let message: String
    private let retryable: Bool
    private let retry: () -> Void

    public init(message: String, retryable: Bool, retry: @escaping () -> Void) {
        self.message = message
        self.retryable = retryable
        self.retry = retry
    }

    public var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.bubble")
                .font(.title)
                .foregroundStyle(NKColor.textTertiary)
                .accessibilityHidden(true)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(NKColor.textPrimary)
                .multilineTextAlignment(.center)
            if retryable {
                Button {
                    retry()
                } label: {
                    Label {
                        Text("再試行", bundle: .module)
                    } icon: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .buttonStyle(NKSecondaryButtonStyle())
                .frame(maxWidth: 200)
                .accessibilityIdentifier("retryButton")
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .nkCard()
    }
}

/// 空の状態。案内文と、行動を促すボタン
public struct EmptyStateView: View {
    private let systemImage: String
    private let title: String
    private let message: String?
    private let actionTitle: String?
    private let action: (() -> Void)?

    public init(systemImage: String, title: String, message: String? = nil, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.largeTitle)
                .foregroundStyle(NKColor.textTertiary)
                .accessibilityHidden(true)
            Text(title)
                .font(.headline)
                .foregroundStyle(NKColor.textPrimary)
                .multilineTextAlignment(.center)
            if let message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(NKColor.textSecondary)
                    .multilineTextAlignment(.center)
            }
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(NKSecondaryButtonStyle())
                    .frame(maxWidth: 240)
                    .padding(.top, 4)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
    }
}

/// スケルトンの角丸の四角（スピナーは使わない）
public struct SkeletonBlock: View {
    private let width: CGFloat?
    private let height: CGFloat
    private let radius: CGFloat

    public init(width: CGFloat? = nil, height: CGFloat, radius: CGFloat = 6) {
        self.width = width
        self.height = height
        self.radius = radius
    }

    public var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(NKColor.skeleton)
            .frame(width: width, height: height)
            .accessibilityHidden(true)
    }
}

// MARK: - 出典（FR-CMP-13 など）

/// 画面下部の出典
public struct AttributionFooter: View {
    private let attributions: [Attribution]

    public init(_ attributions: [Attribution]) {
        self.attributions = attributions
    }

    public var body: some View {
        if !attributions.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(attributions, id: \.self) { attribution in
                    if let urlString = attribution.licenseUrl, let url = URL(string: urlString) {
                        Link(destination: url) {
                            Text(attribution.displayText).underline()
                        }
                    } else {
                        Text(attribution.displayText)
                    }
                }
            }
            .font(.caption2)
            .foregroundStyle(NKColor.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
            .accessibilityElement(children: .contain)
        }
    }
}
