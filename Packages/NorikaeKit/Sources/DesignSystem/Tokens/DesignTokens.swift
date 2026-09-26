// DesignTokens.swift
//
// デザイン仕様書（docs/design/design-spec.md）の色・角丸・余白・文字を SwiftUI で使える形にしたもの。
// docs/design/DesignTokens.swift を DesignSystem モジュールへ移したもの（値は同じ）。
// 値を変えるときは design-spec.md と docs 側の控えも合わせて直すこと。

import SwiftUI

#if canImport(UIKit) && !os(watchOS)
import UIKit
#endif

// MARK: - 色

public enum NKColor {
    // 地・面・線（design-spec 3.1）
    public static let background = Color(light: 0xF4F3EF, dark: 0x0F1115)
    public static let surface = Color(light: 0xFFFFFF, dark: 0x1C1E24)
    public static let surfaceRaised = Color(light: 0xFFFFFF, dark: 0x3A3E48)
    public static let fillTrack = Color(light: 0xE6E4DD, dark: 0x2A2D35)
    public static let fillPill = Color(light: 0xF1F0EB, dark: 0x2A2D35)
    public static let fillSubtle = Color(light: 0xF6F5F1, dark: 0x24262D)
    public static let fillCarInactive = Color(light: 0xE1DED5, dark: 0x3A3E48)
    public static let separator = Color(light: 0xECEAE4, dark: 0x2E3139)
    public static let gridline = Color(light: 0xEFEDE7, dark: 0x2A2D34)
    public static let border = Color(light: 0xDCD9D0, dark: 0x3A3E48)
    public static let connectorDotted = Color(light: 0xB8B5AC, dark: 0x5A5F69)

    // 文字・アイコン（3.2）
    public static let textPrimary = Color(light: 0x15171C, dark: 0xECEDEF)
    public static let textSecondary = Color(light: 0x4A4F59, dark: 0xB3B8C2)
    public static let textTertiary = Color(light: 0x6B7079, dark: 0x9499A3)
    public static let iconChevron = Color(light: 0x9A9EA6, dark: 0x6E737D)
    public static let connectorTransfer = Color(light: 0x8A8F98, dark: 0x7C818B)

    // 操作色（3.3）
    public static let accent = Color(light: 0x1747A6, dark: 0x8AB4FF)
    public static let accentFill = Color(light: 0x1747A6, dark: 0x2F6BE0)
    public static let onAccent = Color(hex: 0xFFFFFF)

    // 本文中の遅延・種別の文字（3.5）
    public static let delayText = Color(light: 0xA15C00, dark: 0xFFB547)
    public static let trainTypeFallback = Color(light: 0xB42318, dark: 0xFF8577)

    // 以下は design-spec にない実装上の追加
    /// 路線色がない路線の既定色（api-contract 3.2、FR-CMP-05）
    public static let lineFallback = Color(light: 0x8A8F98, dark: 0x7C818B)
    /// スケルトン表示の地（FR-CMP-11）
    public static let skeleton = Color(light: 0xE6E4DD, dark: 0x2A2D35)
}

/// 地と文字の色の組。バッジや札に使う。
public struct NKColorPair: Sendable {
    public let fill: Color?
    public let foreground: Color
}

// MARK: - バッジ（3.4）

public enum NKBadgeColor {
    public static let fast = NKColorPair(fill: Color(light: 0x1747A6, dark: 0x2F6BE0), foreground: Color(hex: 0xFFFFFF))
    public static let easy = NKColorPair(fill: Color(hex: 0x1E7F4F), foreground: Color(hex: 0xFFFFFF))
    public static let cheap = NKColorPair(fill: Color(light: 0xFCEBC8, dark: 0x4A3508), foreground: Color(light: 0x7A4B00, dark: 0xFFD27A))
    public static let disruption = NKColorPair(fill: Color(light: 0xFDE7E4, dark: 0x4A1C18), foreground: Color(light: 0xB42318, dark: 0xFF9B8F))
}

// MARK: - 運行状況（3.5）

public enum NKStatusColor {
    public static let normal = NKColorPair(fill: nil, foreground: Color(light: 0x1E6B43, dark: 0x5FD39A))
    public static let delayed = NKColorPair(fill: Color(light: 0xFFF1DB, dark: 0x43300F), foreground: Color(light: 0x8F5100, dark: 0xFFC061))
    public static let suspended = NKColorPair(fill: Color(hex: 0xB42318), foreground: Color(hex: 0xFFFFFF))
    public static let partial = NKColorPair(fill: Color(light: 0xEFE7FA, dark: 0x36264D), foreground: Color(light: 0x5B2E91, dark: 0xD2B8F7))
    public static let other = NKColorPair(fill: NKColor.fillPill, foreground: NKColor.textSecondary)
}

// MARK: - Live Activity・Watch（3.7、常に暗い面）

public enum NKLiveActivityColor {
    public static let surface = Color(hex: 0x1B1E25)
    public static let islandBackground = Color(hex: 0x000000)
    public static let subSurface = Color(hex: 0x2E333D)
    public static let textPrimary = Color(hex: 0xFFFFFF)
    public static let textSecondary = Color(hex: 0xB9BEC8)
    public static let delayText = Color(hex: 0xFFC061)
    public static let delayFill = Color(hex: 0x3D2F12)
}

// MARK: - 角丸（4 章）

public enum NKRadius {
    /// 「早・楽・安」バッジ（20×20）
    public static let badge: CGFloat = 10
    /// 路線記号チップ
    public static let chip: CGFloat = 9
    /// 番線の札、乗車位置の枠
    public static let sm: CGFloat = 10
    /// ボタン
    public static let md: CGFloat = 14
    /// 縦比較の経路カード、セグメントピッカーの溝
    public static let lg: CGFloat = 18
    /// 大きいカード
    public static let xl: CGFloat = 22
    // 帯・遅延バッジ・運行状況の札は Capsule() を使う
}

// MARK: - 余白・寸法（6 章）

public enum NKSpacing {
    public static let screenHorizontal: CGFloat = 16
    public static let cardPadding: CGFloat = 16
    public static let cardGap: CGFloat = 12
    public static let sectionTitleGap: CGFloat = 8
    public static let minTapTarget: CGFloat = 44
}

/// 縦比較の寸法（7.4）
public enum NKCompareMetrics {
    public static let axisGutterWidth: CGFloat = 38
    public static let columnWidth: CGFloat = 110
    public static let visibleColumnCount = 3
    public static let headerCardSize: CGFloat = 104
    public static let bandLeading: CGFloat = 10
    public static let bandWidth: CGFloat = 22
    public static let labelLeading: CGFloat = 40
    public static let transferLineWidth: CGFloat = 2
    public static let axisVerticalPadding: CGFloat = 12
    /// 目盛りどうしの最小の間隔。これを下回らない最小の間隔（分）を tickIntervalCandidates から選ぶ
    public static let minTickSpacing: CGFloat = 40
    public static let tickIntervalCandidates = [5, 10, 15, 30, 60]
    /// 乗換駅の「着」と「発」のラベルがこれより近いときは、2 つ目の駅名を省く
    public static let labelCollapseDistance: CGFloat = 32
}

/// 縦タイムラインの寸法（7.5）
public enum NKTimelineMetrics {
    public static let timeColumnWidth: CGFloat = 60
    public static let railColumnWidth: CGFloat = 26
    public static let railWidth: CGFloat = 6
    public static let nodeDiameter: CGFloat = 14
    public static let nodeBorderWidth: CGFloat = 3
    public static let terminalNodeDiameter: CGFloat = 16
    public static let stationRowHeight: CGFloat = 40
    public static let transferRowHeight: CGFloat = 44
    public static let carSize = CGSize(width: 18, height: 10)
    public static let carSpacing: CGFloat = 2
}

// MARK: - 文字（5 章）

public extension Font {
    /// 時刻など、桁をそろえたい数字（design-spec 5.1 の案 A）
    static func nkNumeric(_ style: Font.TextStyle, weight: Font.Weight = .semibold) -> Font {
        .system(style, weight: weight).monospacedDigit()
    }
}

// MARK: - 色の補助

public extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }

    /// ライトとダークで値が変わる色。watchOS は常に暗い面なので dark の値を使う。
    init(light: UInt32, dark: UInt32) {
        #if canImport(UIKit) && !os(watchOS)
        self.init(uiColor: UIColor { traits in
            UIColor(Color(hex: traits.userInterfaceStyle == .dark ? dark : light))
        })
        #else
        self.init(hex: dark)
        #endif
    }
}
