import Domain
import SwiftUI

/// 運行状況の見た目（design-spec 3.5、NFR-A11Y-05：アイコン・色・文字の 3 つで表す）
public struct OperationStatusStyle: Sendable {
    public var title: String
    public var systemImage: String
    public var colors: NKColorPair

    public init(kind: OperationStatusKind, summary: String? = nil) {
        switch kind {
        case .normal:
            title = String(localized: "平常運転", bundle: .module)
            systemImage = "checkmark.circle"
            colors = NKStatusColor.normal
        case .delayed:
            title = String(localized: "遅延", bundle: .module)
            systemImage = "exclamationmark.triangle.fill"
            colors = NKStatusColor.delayed
        case .suspended:
            title = String(localized: "見合わせ", bundle: .module)
            systemImage = "minus.circle.fill"
            colors = NKStatusColor.suspended
        case .partial:
            title = String(localized: "一部運休", bundle: .module)
            systemImage = "exclamationmark.circle.fill"
            colors = NKStatusColor.partial
        case .other:
            title = summary ?? String(localized: "お知らせ", bundle: .module)
            systemImage = "info.circle.fill"
            colors = NKStatusColor.other
        case .unknown:
            // 「平常」と明確に区別する（FR-STS-03）。アイコン・文字とも平常と別のもの
            title = String(localized: "情報なし", bundle: .module)
            systemImage = "questionmark.circle"
            colors = NKStatusColor.other
        }
    }
}

/// 運行状況の札（design-spec 7.3）
public struct OperationStatusLabel: View {
    private let style: OperationStatusStyle
    private let isNormal: Bool
    @ScaledMetric(relativeTo: .caption) private var height: CGFloat = 24

    public init(_ kind: OperationStatusKind, summary: String? = nil) {
        style = OperationStatusStyle(kind: kind, summary: summary)
        isNormal = kind == .normal
    }

    public var body: some View {
        HStack(spacing: 4) {
            Image(systemName: style.systemImage)
                .font(.footnote)
            Text(style.title)
                .font(.caption.weight(isNormal ? .medium : .bold))
                .lineLimit(1)
        }
        .foregroundStyle(style.colors.foreground)
        .padding(.horizontal, 8)
        .frame(minHeight: height)
        .background(style.colors.fill ?? .clear, in: Capsule())
        .fixedSize()
        .accessibilityElement(children: .combine)
    }
}
