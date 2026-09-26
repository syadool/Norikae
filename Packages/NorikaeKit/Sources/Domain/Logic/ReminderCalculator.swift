import Foundation

/// 出発リマインドの時刻の計算（FR-NTF-03、FR-NTF-05）
public enum ReminderCalculator {
    /// 「発車時刻 − 歩く時間 − 余裕の時間」。歩く時間が分からなければ「発車時刻 − 余裕の時間」
    ///
    /// - Parameters:
    ///   - departure: 最初の列車の発車時刻（見込みがあれば見込み）
    ///   - walkingDuration: MapKit で求めた、現在地から出発駅までの徒歩時間（秒）。取れなければ `nil`
    ///   - walkingSpeed: 歩く速さの設定。徒歩時間に補正を掛ける
    ///   - margin: 余裕の時間
    ///   - now: 現在時刻。これより前になる場合は `nil`（予約しない）
    public static func fireDate(
        departure: Date, walkingDuration: TimeInterval?, walkingSpeed: WalkingSpeed, margin: ReminderMargin, now: Date
    ) -> Date? {
        var seconds = TimeInterval(margin.rawValue * 60)
        if let walkingDuration {
            seconds += walkingDuration * walkingSpeed.durationFactor
        }
        // 秒は切り捨てて、分の頭にそろえる
        let raw = departure.addingTimeInterval(-seconds)
        let aligned = Date(timeIntervalSince1970: (raw.timeIntervalSince1970 / 60).rounded(.down) * 60)
        return aligned > now ? aligned : nil
    }
}
