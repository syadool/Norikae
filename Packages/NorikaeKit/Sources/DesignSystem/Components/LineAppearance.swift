import Domain
import SwiftUI

public extension Color {
    init(rgb: RGBColor) {
        self.init(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue, opacity: 1)
    }
}

/// 路線の見た目（色・記号）。記号・色がない路線の代替表示を含む（FR-CMP-05、NFR-A11Y-04）
public struct LineAppearance: Sendable, Hashable {
    /// 記号の欄に出す文字（`symbol` → `displayCode` → `name`）
    public var label: String
    /// VoiceOver で読む路線名
    public var name: String
    /// 公式の路線色（ない場合は `nil`）
    public var rgb: RGBColor?

    public init(label: String, name: String, rgb: RGBColor?) {
        self.label = label
        self.name = name
        self.rgb = rgb
    }

    public init(line: Line?, fallbackID: String) {
        self.init(label: line?.label ?? fallbackID, name: line?.name ?? fallbackID, rgb: line?.rgbColor)
    }

    public init(summary: GuidanceSummary.LegInfo) {
        self.init(label: summary.lineLabel, name: summary.lineName, rgb: summary.lineColorHex.flatMap(RGBColor.init(hex:)))
    }

    /// 帯・チップの枠の色。路線色がなければ既定色
    public var color: Color {
        rgb.map(Color.init(rgb:)) ?? NKColor.lineFallback
    }

    /// Live Activity などの暗い面で細い線に使う色（コントラスト 3:1 未満なら明るくする、design-spec 3.6）
    public var colorOnDarkSurface: Color {
        let base = rgb ?? RGBColor(hex: 0x8A8F98)
        return Color(rgb: base.brightened(against: .liveActivitySurface))
    }

    /// 記号が長い（路線名で代替している）か。チップの幅の調整に使う
    public var isLongLabel: Bool { label.count > 3 }
}

/// 種別の文字色（design-spec 3.5）。API に種別色があればそれを使う
public func trainTypeColor(_ type: TrainType?) -> Color {
    if let hex = type?.color, let rgb = RGBColor(hex: hex) { return Color(rgb: rgb) }
    guard let type else { return NKColor.textSecondary }
    // 普通・各駅停車は通常の文字色、それ以外は強調色
    return ["普", "各"].contains(type.shortName) ? NKColor.textSecondary : NKColor.trainTypeFallback
}
