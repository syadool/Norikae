import Domain
import Foundation

/// 時刻・所要時間・運賃の表示（日本時間）
public enum NKFormat {
    private static let locale = Locale(identifier: "ja_JP")

    /// 「8:14」
    public static func time(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, calendar: JapanCalendar.calendar, timeZone: JapanCalendar.timeZone))
    }

    /// VoiceOver 用の「8時14分」
    public static func spokenTime(_ date: Date) -> String {
        let c = JapanCalendar.calendar.dateComponents([.hour, .minute], from: date)
        let hour = c.hour ?? 0, minute = c.minute ?? 0
        return String(localized: "\(hour)時\(minute)分", bundle: .module)
    }

    /// 「9月26日(土)」
    public static func date(_ date: Date) -> String {
        let c = JapanCalendar.calendar.dateComponents([.month, .day, .weekday], from: date)
        let weekday = JapanCalendar.calendar.veryShortWeekdaySymbols[(c.weekday ?? 1) - 1]
        return String(localized: "\(c.month ?? 0)月\(c.day ?? 0)日(\(weekday))", bundle: .module)
    }

    /// 「9/25(金)」
    public static func shortDate(_ date: Date) -> String {
        let c = JapanCalendar.calendar.dateComponents([.month, .day, .weekday], from: date)
        let weekday = JapanCalendar.calendar.veryShortWeekdaySymbols[(c.weekday ?? 1) - 1]
        return "\(c.month ?? 0)/\(c.day ?? 0)(\(weekday))"
    }

    /// 「34分」「1時間5分」
    public static func duration(minutes: Int) -> String {
        if minutes < 60 { return String(localized: "\(minutes)分", bundle: .module) }
        let hours = minutes / 60, rest = minutes % 60
        if rest == 0 { return String(localized: "\(hours)時間", bundle: .module) }
        return String(localized: "\(hours)時間\(rest)分", bundle: .module)
    }

    /// 「乗換0回」
    public static func transfers(_ count: Int) -> String {
        String(localized: "乗換\(count)回", bundle: .module)
    }

    /// 運賃（api-contract 3.8 の表示ルール）
    ///
    /// - 設定した種別：「836円」
    /// - もう一方の種別：「切符 850円」のように種別を併記
    /// - 概算：「約840円」
    /// - 不明：「運賃不明」
    public static func fare(_ display: FareDisplay) -> String {
        switch display {
        case .amount(let value, let kind, let isPreferred):
            let amount = value.formatted()
            if isPreferred { return String(localized: "\(amount)円", bundle: .module) }
            return String(localized: "\(fareKindName(kind)) \(amount)円", bundle: .module)
        case .estimated(let value):
            return String(localized: "約\(value.formatted())円", bundle: .module)
        case .unavailable:
            return String(localized: "運賃不明", bundle: .module)
        }
    }

    public static func fareKindName(_ kind: FareKind) -> String {
        switch kind {
        case .ic: String(localized: "IC", bundle: .module)
        case .ticket: String(localized: "切符", bundle: .module)
        }
    }

    /// 「IC運賃」「切符運賃」
    public static func fareKindLabel(_ kind: FareKind) -> String {
        switch kind {
        case .ic: String(localized: "IC運賃", bundle: .module)
        case .ticket: String(localized: "切符運賃", bundle: .module)
        }
    }

    /// 「8:04 時点の情報」（FR-OFF-02）
    public static func asOf(_ date: Date) -> String {
        String(localized: "\(time(date)) 時点の情報", bundle: .module)
    }

    /// 「3分遅れ」
    public static func delay(minutes: Int) -> String {
        String(localized: "\(minutes)分遅れ", bundle: .module)
    }
}
