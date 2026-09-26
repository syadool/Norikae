import Foundation

/// sRGB の色（0〜1）。路線色の読み取りと、暗い面でのコントラスト調整に使う（design-spec 3.6）
public struct RGBColor: Sendable, Hashable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    /// `#RRGGBB` を読む。形式が違えば `nil`
    public init?(hex text: String) {
        var body = Substring(text)
        if body.hasPrefix("#") { body = body.dropFirst() }
        guard body.count == 6, let value = UInt32(body, radix: 16) else { return nil }
        self.init(hex: value)
    }

    public var hexString: String {
        let r = Int((red * 255).rounded()), g = Int((green * 255).rounded()), b = Int((blue * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    /// WCAG の相対輝度
    public var relativeLuminance: Double {
        func channel(_ value: Double) -> Double {
            value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
    }

    /// WCAG のコントラスト比
    public func contrastRatio(with other: RGBColor) -> Double {
        let l1 = relativeLuminance, l2 = other.relativeLuminance
        return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    }

    /// 白を混ぜる（0〜1）
    public func mixedWithWhite(_ amount: Double) -> RGBColor {
        let t = min(max(amount, 0), 1)
        return RGBColor(red: red + (1 - red) * t, green: green + (1 - green) * t, blue: blue + (1 - blue) * t)
    }

    /// 暗い面に細い線で描くとき、面とのコントラストが `minimumRatio` 未満なら明るくする
    ///
    /// 色味を保つため、白を少しずつ混ぜて最初に基準を満たした色を返す（design-spec 9 章 #4 の実装案）。
    public func brightened(against surface: RGBColor, minimumRatio: Double = 3.0) -> RGBColor {
        guard contrastRatio(with: surface) < minimumRatio else { return self }
        var amount = 0.0
        while amount < 1 {
            amount += 0.02
            let candidate = mixedWithWhite(amount)
            if candidate.contrastRatio(with: surface) >= minimumRatio { return candidate }
        }
        return mixedWithWhite(1)
    }

    /// Live Activity・Watch の面（design-spec 3.7 の `laSurface`）
    public static let liveActivitySurface = RGBColor(hex: 0x1B1E25)
}
