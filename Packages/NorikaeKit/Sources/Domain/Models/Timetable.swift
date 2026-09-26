import Foundation

/// 曜日区分（api-contract 3.12）
public enum DayType: String, Codable, Sendable, Hashable, CaseIterable {
    case weekday
    case saturday
    case holiday

    /// 運行日の曜日区分。日曜と祝日（振替休日・国民の休日を含む）は `holiday`
    public init(serviceDate: ServiceDate) {
        guard let date = serviceDate.startDate else {
            self = .weekday
            return
        }
        let calendar = JapanCalendar.calendar
        if JapaneseHolidays.isHoliday(date) {
            self = .holiday
            return
        }
        switch calendar.component(.weekday, from: date) {
        case 1: self = .holiday
        case 7: self = .saturday
        default: self = .weekday
        }
    }
}

/// 駅の路線・方面（API-04）
public struct LineDirection: Codable, Sendable, Hashable, Identifiable {
    public var lineId: String
    public var directionId: String
    public var directionName: String

    public init(lineId: String, directionId: String, directionName: String) {
        self.lineId = lineId
        self.directionId = directionId
        self.directionName = directionName
    }

    /// 方面の ID は路線をまたいで一意とは限らないため、路線と組み合わせる
    public var id: String { "\(lineId)/\(directionId)" }
}

/// 時刻表（api-contract 3.12）
public struct Timetable: Codable, Sendable, Hashable {
    public var stationId: String
    public var lineId: String
    public var directionId: String
    public var directionName: String
    public var dayType: DayType
    public var departures: [TimetableEntry]
    public var asOf: Date

    public init(stationId: String, lineId: String, directionId: String, directionName: String, dayType: DayType, departures: [TimetableEntry], asOf: Date) {
        self.stationId = stationId
        self.lineId = lineId
        self.directionId = directionId
        self.directionName = directionName
        self.dayType = dayType
        self.departures = departures
        self.asOf = asOf
    }
}

/// 時刻表の 1 本
public struct TimetableEntry: Codable, Sendable, Hashable, Identifiable {
    public var departureTime: Date
    public var trainTypeId: String
    public var destinationName: String
    public var platform: String?
    public var isOriginStation: Bool
    public var trainRunId: String

    public var id: String { "\(trainRunId)@\(departureTime.timeIntervalSince1970)" }

    public init(departureTime: Date, trainTypeId: String, destinationName: String, platform: String? = nil, isOriginStation: Bool, trainRunId: String) {
        self.departureTime = departureTime
        self.trainTypeId = trainTypeId
        self.destinationName = destinationName
        self.platform = platform
        self.isOriginStation = isOriginStation
        self.trainRunId = trainRunId
    }
}

/// 時刻表の応答（`meta` 付き）
public struct TimetableResult: Codable, Sendable, Hashable {
    public var meta: ResponseMeta
    public var timetable: Timetable

    public init(meta: ResponseMeta, timetable: Timetable) {
        self.meta = meta
        self.timetable = timetable
    }
}

/// 停車駅一覧の応答（`meta` 付き）
public struct TrainRunResult: Sendable, Hashable {
    public var meta: ResponseMeta
    public var trainRun: TrainRun

    public init(meta: ResponseMeta, trainRun: TrainRun) {
        self.meta = meta
        self.trainRun = trainRun
    }
}

/// 日本の祝日（内閣府の規則に基づく計算。1980〜2099 年を想定）
public enum JapaneseHolidays {
    public static func isHoliday(_ date: Date) -> Bool {
        let calendar = JapanCalendar.calendar
        let c = calendar.dateComponents([.year, .month, .day, .weekday], from: date)
        guard let year = c.year, let month = c.month, let day = c.day else { return false }
        if isNamedHoliday(year: year, month: month, day: day) { return true }

        // 振替休日：祝日が日曜なら、その後の最初の祝日でない日
        if c.weekday != 1 {
            var cursor = date
            while let previous = calendar.date(byAdding: .day, value: -1, to: cursor) {
                let p = calendar.dateComponents([.year, .month, .day, .weekday], from: previous)
                guard let py = p.year, let pm = p.month, let pd = p.day, isNamedHoliday(year: py, month: pm, day: pd) else { break }
                if p.weekday == 1 { return true }
                cursor = previous
            }
        }

        // 国民の休日：前日と翌日が祝日の平日
        if let before = calendar.date(byAdding: .day, value: -1, to: date),
           let after = calendar.date(byAdding: .day, value: 1, to: date),
           c.weekday != 1 {
            let b = calendar.dateComponents([.year, .month, .day], from: before)
            let a = calendar.dateComponents([.year, .month, .day], from: after)
            if let by = b.year, let bm = b.month, let bd = b.day, let ay = a.year, let am = a.month, let ad = a.day,
               isNamedHoliday(year: by, month: bm, day: bd), isNamedHoliday(year: ay, month: am, day: ad) {
                return true
            }
        }
        return false
    }

    static func isNamedHoliday(year: Int, month: Int, day: Int) -> Bool {
        switch month {
        case 1: return day == 1 || day == nthMonday(2, year: year, month: 1)
        case 2: return day == 11 || (year >= 2020 && day == 23)
        case 3: return day == vernalEquinoxDay(year)
        case 4: return day == 29
        case 5: return day == 3 || day == 4 || day == 5
        case 7:
            if year == 2020 { return day == 23 || day == 24 }
            if year == 2021 { return day == 22 || day == 23 }
            return day == nthMonday(3, year: year, month: 7)
        case 8:
            if year == 2020 { return day == 10 }
            if year == 2021 { return day == 8 }
            return year >= 2016 && day == 11
        case 9: return day == nthMonday(3, year: year, month: 9) || day == autumnalEquinoxDay(year)
        case 10:
            if year == 2020 || year == 2021 { return false }
            return day == nthMonday(2, year: year, month: 10)
        case 11: return day == 3 || day == 23
        default: return false
        }
    }

    private static func nthMonday(_ n: Int, year: Int, month: Int) -> Int {
        let calendar = JapanCalendar.calendar
        guard let first = calendar.date(from: DateComponents(year: year, month: month, day: 1)) else { return 0 }
        let weekday = calendar.component(.weekday, from: first) // 1 = 日曜
        let firstMonday = 1 + (9 - weekday) % 7
        return firstMonday + (n - 1) * 7
    }

    private static func vernalEquinoxDay(_ year: Int) -> Int {
        Int(20.8431 + 0.242194 * Double(year - 1980)) - (year - 1980) / 4
    }

    private static func autumnalEquinoxDay(_ year: Int) -> Int {
        Int(23.2488 + 0.242194 * Double(year - 1980)) - (year - 1980) / 4
    }
}
