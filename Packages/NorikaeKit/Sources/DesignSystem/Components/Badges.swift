import Domain
import SwiftUI

/// 「早」「楽」「安」バッジ（design-spec 7.2）
public struct RouteBadgeView: View {
    private let badge: RouteBadge
    @ScaledMetric(relativeTo: .caption2) private var size: CGFloat = 20

    public init(_ badge: RouteBadge) {
        self.badge = badge
    }

    public var body: some View {
        let colors = Self.colors(for: badge)
        Text(Self.title(for: badge))
            .font(.caption2.weight(.bold))
            .foregroundStyle(colors.foreground)
            .frame(width: size, height: size)
            .background(colors.fill ?? .clear, in: RoundedRectangle(cornerRadius: NKRadius.badge, style: .continuous))
            .accessibilityLabel(Text(Self.accessibilityText(for: badge)))
    }

    public nonisolated static func title(for badge: RouteBadge) -> String {
        switch badge {
        case .fastest: String(localized: "早", bundle: .module)
        case .fewestTransfers: String(localized: "楽", bundle: .module)
        case .cheapest: String(localized: "安", bundle: .module)
        }
    }

    public nonisolated static func accessibilityText(for badge: RouteBadge) -> String {
        switch badge {
        case .fastest: String(localized: "所要時間が最短", bundle: .module)
        case .fewestTransfers: String(localized: "乗換が最少", bundle: .module)
        case .cheapest: String(localized: "運賃が最安", bundle: .module)
        }
    }

    static func colors(for badge: RouteBadge) -> NKColorPair {
        switch badge {
        case .fastest: NKBadgeColor.fast
        case .fewestTransfers: NKBadgeColor.easy
        case .cheapest: NKBadgeColor.cheap
        }
    }
}

/// 遅延バッジ（`Route.hasServiceDisruption`、FR-CMP-08）
public struct DisruptionBadge: View {
    @ScaledMetric(relativeTo: .caption2) private var height: CGFloat = 20

    public init() {}

    public var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption2)
            Text("遅延", bundle: .module)
                .font(.caption2.weight(.bold))
        }
        .foregroundStyle(NKBadgeColor.disruption.foreground)
        .padding(.horizontal, 7)
        .frame(height: height)
        .background(NKBadgeColor.disruption.fill ?? .clear, in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("遅延の影響あり", bundle: .module))
    }
}

/// バッジの行
public struct RouteBadgeRow: View {
    private let badges: [RouteBadge]
    private let hasDisruption: Bool

    public init(badges: [RouteBadge], hasDisruption: Bool) {
        self.badges = badges
        self.hasDisruption = hasDisruption
    }

    public var body: some View {
        HStack(spacing: 4) {
            ForEach(badges, id: \.self) { RouteBadgeView($0) }
            if hasDisruption { DisruptionBadge() }
        }
    }
}
