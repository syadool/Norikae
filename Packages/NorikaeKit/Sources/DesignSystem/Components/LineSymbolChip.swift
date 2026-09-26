import Domain
import SwiftUI

/// 路線記号チップ（design-spec 7.1）
///
/// 地は `surface`、枠は 2pt の路線色、文字は `textPrimary` の太字。VoiceOver では路線名を読む。
public struct LineSymbolChip: View {
    public enum Size: Sendable {
        /// 縦比較（高さ 18）
        case compare
        /// 経路詳細（高さ 20）
        case detail
        /// 運行情報（高さ 22）
        case status

        var height: CGFloat {
            switch self {
            case .compare: 18
            case .detail: 20
            case .status: 22
            }
        }

        var font: Font {
            switch self {
            case .compare: .caption2.weight(.bold)
            case .detail, .status: .caption.weight(.bold)
            }
        }
    }

    private let appearance: LineAppearance
    private let size: Size
    private let surface: Color
    private let foreground: Color
    @ScaledMetric private var scaledHeight: CGFloat

    public init(_ appearance: LineAppearance, size: Size = .detail, surface: Color = NKColor.surface, foreground: Color = NKColor.textPrimary) {
        self.appearance = appearance
        self.size = size
        self.surface = surface
        self.foreground = foreground
        _scaledHeight = ScaledMetric(wrappedValue: size.height, relativeTo: .caption2)
    }

    public var body: some View {
        Text(appearance.label)
            .font(size.font.monospacedDigit())
            .foregroundStyle(foreground)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 3)
            .frame(minWidth: scaledHeight + 8, minHeight: scaledHeight)
            .background(surface, in: RoundedRectangle(cornerRadius: NKRadius.chip, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: NKRadius.chip, style: .continuous)
                    .strokeBorder(appearance.color, lineWidth: 2)
            }
            .fixedSize()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(appearance.name))
    }
}

/// 番線の札（design-spec 3.1 `fillPill`、角丸 `sm`）。番線がなければ呼び出し側で出さない
public struct PlatformPill: View {
    private let platform: String
    private let fill: Color
    private let foreground: Color

    public init(_ platform: String, fill: Color = NKColor.fillPill, foreground: Color = NKColor.textSecondary) {
        self.platform = platform
        self.fill = fill
        self.foreground = foreground
    }

    public var body: some View {
        Text("\(platform)番線", bundle: .module)
            .font(.caption.weight(.semibold).monospacedDigit())
            .foregroundStyle(foreground)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(fill, in: RoundedRectangle(cornerRadius: NKRadius.sm, style: .continuous))
            .fixedSize()
    }
}
