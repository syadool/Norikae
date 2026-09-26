import Foundation

/// 「早・楽・安」バッジ（FR-CMP-07）。並び順は 早 → 楽 → 安
public enum RouteBadge: Int, Sendable, Hashable, CaseIterable, Comparable {
    case fastest
    case fewestTransfers
    case cheapest

    public static func < (lhs: RouteBadge, rhs: RouteBadge) -> Bool { lhs.rawValue < rhs.rawValue }
}

public enum RouteRanking {
    /// 経路ごとのバッジを判定する
    ///
    /// - 早：所要時間が最短
    /// - 楽：乗換回数が最少
    /// - 安：運賃が最安。全経路の表示運賃が同じ種別のときだけ付ける（種別の混在や運賃不明があれば付けない）
    public static func badges(for routes: [Route], fareKind: FareKind) -> [Route.ID: [RouteBadge]] {
        guard !routes.isEmpty else { return [:] }
        var result: [Route.ID: Set<RouteBadge>] = [:]

        if let minDuration = routes.map(\.durationMinutes).min() {
            for route in routes where route.durationMinutes == minDuration {
                result[route.id, default: []].insert(.fastest)
            }
        }
        if let minTransfers = routes.map(\.transferCount).min() {
            for route in routes where route.transferCount == minTransfers {
                result[route.id, default: []].insert(.fewestTransfers)
            }
        }
        if canCompareFares(routes, fareKind: fareKind) {
            let fares = routes.compactMap { route in route.fare.display(preferred: fareKind).value.map { (route.id, $0) } }
            if let minFare = fares.map(\.1).min() {
                for (id, value) in fares where value == minFare {
                    result[id, default: []].insert(.cheapest)
                }
            }
        }
        return result.mapValues { $0.sorted() }
    }

    /// 「安」を判定できるか（全経路の表示運賃が同じ種別で、運賃不明がない）
    public static func canCompareFares(_ routes: [Route], fareKind: FareKind) -> Bool {
        let kinds = routes.map { $0.fare.display(preferred: fareKind).comparisonKind }
        guard let first = kinds.first, let firstKind = first else { return false }
        return kinds.allSatisfy { $0 == firstKind }
    }

    /// 並び替え（FR-CND-04）。サーバーの返す順番は保証されないため、アプリ内で決める
    public static func sorted(_ routes: [Route], by order: RouteSortOrder, fareKind: FareKind) -> [Route] {
        routes.sorted { lhs, rhs in
            let keys: [(Int, Int)]
            switch order {
            case .fastest:
                keys = [
                    (lhs.durationMinutes, rhs.durationMinutes),
                    (Int(lhs.arrivalTime.timeIntervalSince1970), Int(rhs.arrivalTime.timeIntervalSince1970)),
                    (lhs.transferCount, rhs.transferCount),
                ]
            case .fewestTransfers:
                keys = [
                    (lhs.transferCount, rhs.transferCount),
                    (lhs.durationMinutes, rhs.durationMinutes),
                    (Int(lhs.arrivalTime.timeIntervalSince1970), Int(rhs.arrivalTime.timeIntervalSince1970)),
                ]
            case .cheapest:
                // 運賃不明は最後
                let lf = lhs.fare.display(preferred: fareKind).value ?? Int.max
                let rf = rhs.fare.display(preferred: fareKind).value ?? Int.max
                keys = [
                    (lf, rf),
                    (lhs.durationMinutes, rhs.durationMinutes),
                    (lhs.transferCount, rhs.transferCount),
                ]
            }
            for (l, r) in keys where l != r {
                return l < r
            }
            return Int(lhs.departureTime.timeIntervalSince1970) < Int(rhs.departureTime.timeIntervalSince1970)
        }
    }
}
