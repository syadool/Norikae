import Foundation

/// 対象地域（api-contract 3.1）
public enum Region: String, Codable, Sendable, CaseIterable, Hashable {
    case kanto
    case kansai
}

/// 緯度・経度
public struct Coordinate: Codable, Sendable, Hashable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    /// 2 点間の距離（メートル）。最寄り駅の検索に使う（haversine）
    public func distance(to other: Coordinate) -> Double {
        let earthRadius = 6_371_000.0
        let lat1 = latitude * .pi / 180
        let lat2 = other.latitude * .pi / 180
        let dLat = (other.latitude - latitude) * .pi / 180
        let dLon = (other.longitude - longitude) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return earthRadius * 2 * atan2(a.squareRoot(), (1 - a).squareRoot())
    }
}

/// 運行日（`YYYY-MM-DD`、api-contract 2 章）
public struct ServiceDate: Codable, Sendable, Hashable, Comparable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    /// 日本時間の日付から作る
    public init(date: Date) {
        let components = JapanCalendar.calendar.dateComponents([.year, .month, .day], from: date)
        self.rawValue = String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    public init(from decoder: any Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    /// その時刻が属する運行日。深夜（`cutoffHour` 時より前）は前日の運行日とみなす
    public static func operatingDay(containing date: Date, cutoffHour: Int = 4) -> ServiceDate {
        let calendar = JapanCalendar.calendar
        let hour = calendar.component(.hour, from: date)
        let day = hour < cutoffHour ? (calendar.date(byAdding: .day, value: -1, to: date) ?? date) : date
        return ServiceDate(date: day)
    }

    /// 日本時間のその日の 0 時
    public var startDate: Date? {
        let parts = rawValue.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return JapanCalendar.calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    public var description: String { rawValue }

    public static func < (lhs: ServiceDate, rhs: ServiceDate) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// 日本時間の暦
public enum JapanCalendar {
    public static let timeZone = TimeZone(identifier: "Asia/Tokyo") ?? TimeZone(secondsFromGMT: 9 * 3600)!

    public static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.locale = Locale(identifier: "ja_JP")
        return calendar
    }
}

/// 出典（api-contract 2.2）
public struct Attribution: Codable, Sendable, Hashable {
    public var provider: String
    public var displayText: String
    public var licenseUrl: String?

    public init(provider: String, displayText: String, licenseUrl: String? = nil) {
        self.provider = provider
        self.displayText = displayText
        self.licenseUrl = licenseUrl
    }
}

/// 共通メタデータ（api-contract 2.1）
public struct ResponseMeta: Codable, Sendable, Hashable {
    public var asOf: Date
    public var partialResult: Bool
    public var isStale: Bool
    public var sources: [String]
    public var attributions: [Attribution]

    public init(asOf: Date, partialResult: Bool = false, isStale: Bool = false, sources: [String] = [], attributions: [Attribution] = []) {
        self.asOf = asOf
        self.partialResult = partialResult
        self.isStale = isStale
        self.sources = sources
        self.attributions = attributions
    }
}

/// データの充足状況（api-contract 3.14）
public enum DataAvailability: String, Codable, Sendable, Hashable {
    case available
    case partial
    case stale
    case unavailable

    /// 未知の値は、推測せずに `unavailable` として扱う
    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = DataAvailability(rawValue: raw) ?? .unavailable
    }

    /// 機能を使えるか（`unavailable` 以外）
    public var isUsable: Bool { self != .unavailable }
}
