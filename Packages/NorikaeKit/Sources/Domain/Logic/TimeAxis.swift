import Foundation

/// 縦比較の共通の時間軸（FR-CMP-03、FR-CMP-10、design-spec 7.4）
///
/// 範囲は全経路の最も早い出発から最も遅い到着まで。日付をまたぐ場合も `Date` の差で計算する。
public struct TimeAxis: Sendable, Hashable {
    public let start: Date
    public let end: Date

    public init(start: Date, end: Date) {
        self.start = min(start, end)
        self.end = max(start, end)
    }

    /// 経路の集まりから軸を作る。経路がなければ `nil`
    public init?(routes: [Route]) {
        var earliest: Date?
        var latest: Date?
        for route in routes {
            var times = [route.departureTime, route.arrivalTime]
            for leg in route.trainLegs {
                times.append(leg.from.scheduledTime)
                times.append(leg.to.scheduledTime)
            }
            for time in times {
                earliest = min(earliest ?? time, time)
                latest = max(latest ?? time, time)
            }
        }
        guard let earliest, let latest else { return nil }
        self.init(start: earliest, end: latest)
    }

    /// 軸の長さ（分）。0 分にはしない
    public var totalMinutes: Double {
        max(end.timeIntervalSince(start) / 60, 1)
    }

    /// 1 分あたりの高さ：(本体の高さ − 上下の余白) ÷ 軸の分数
    public func pointsPerMinute(contentHeight: Double, verticalPadding: Double) -> Double {
        max(contentHeight - verticalPadding * 2, 1) / totalMinutes
    }

    /// その時刻の縦位置
    public func y(for date: Date, pointsPerMinute: Double, verticalPadding: Double) -> Double {
        verticalPadding + date.timeIntervalSince(start) / 60 * pointsPerMinute
    }

    /// 目盛りの間隔（分）。隣との間が `minimumSpacing` 以上になる最小の候補
    public static func tickInterval(pointsPerMinute: Double, minimumSpacing: Double, candidates: [Int]) -> Int {
        let sorted = candidates.sorted()
        return sorted.first { Double($0) * pointsPerMinute >= minimumSpacing } ?? sorted.last ?? 60
    }

    /// 目盛りの時刻。間隔の倍数（日本時間の時計の分）にそろえ、上下の余白の範囲まで含める
    public func ticks(intervalMinutes: Int, pointsPerMinute: Double, verticalPadding: Double) -> [Date] {
        guard intervalMinutes > 0 else { return [] }
        let paddingSeconds = pointsPerMinute > 0 ? verticalPadding / pointsPerMinute * 60 : 0
        let lower = start.timeIntervalSince1970 - paddingSeconds
        let upper = end.timeIntervalSince1970 + paddingSeconds
        let step = Double(intervalMinutes * 60)
        // 日本時間は UTC から整数時間ずれているので、60 分以下の間隔は UNIX 時刻の倍数でそろう
        var tick = (lower / step).rounded(.up) * step
        var result: [Date] = []
        while tick <= upper {
            result.append(Date(timeIntervalSince1970: tick))
            tick += step
        }
        return result
    }
}
