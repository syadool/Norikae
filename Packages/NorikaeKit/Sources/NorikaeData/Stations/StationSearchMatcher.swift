import Domain
import Foundation

/// 駅名の候補検索（FR-SRC-02〜04）
///
/// - 漢字表記と読み（ひらがな）の両方で、前方一致・部分一致を探す
/// - カタカナ・全角英数・空白の違いは吸収する
/// - 並び順：完全一致 → 前方一致 → 部分一致。同じ一致の中では主に使う地域の駅を優先する
public enum StationSearchMatcher {
    public enum MatchKind: Int, Comparable, Sendable {
        case exact = 0
        case prefix = 1
        case partial = 2

        public static func < (lhs: MatchKind, rhs: MatchKind) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    public static func normalize(_ text: String) -> String {
        var value = text.precomposedStringWithCompatibilityMapping // 全角英数・半角カナをそろえる
        value = value.applyingTransform(.hiraganaToKatakana, reverse: true) ?? value // カタカナ → ひらがな
        value = value.lowercased()
        value.removeAll { $0.isWhitespace || $0 == "・" || $0 == "･" }
        // 「ヶ」「ケ」の表記ゆれ
        value = value.replacingOccurrences(of: "ヶ", with: "け").replacingOccurrences(of: "ケ", with: "け")
        // 末尾の「駅」は無視する
        if value.count > 1, value.hasSuffix("駅") { value.removeLast() }
        return value
    }

    public static func match(_ station: Station, normalizedQuery: String) -> MatchKind? {
        guard !normalizedQuery.isEmpty else { return nil }
        let candidates = [normalize(station.name), normalize(station.reading)]
        if candidates.contains(normalizedQuery) { return .exact }
        if candidates.contains(where: { $0.hasPrefix(normalizedQuery) }) { return .prefix }
        if candidates.contains(where: { $0.contains(normalizedQuery) }) { return .partial }
        return nil
    }

    public static func search(_ text: String, in stations: [Station], preferredRegion: Region, limit: Int = 30) -> [Station] {
        let query = normalize(text)
        guard !query.isEmpty else { return [] }
        let matched: [(Station, MatchKind)] = stations.compactMap { station in
            match(station, normalizedQuery: query).map { (station, $0) }
        }
        return matched.sorted { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
            let lp = lhs.0.region == preferredRegion, rp = rhs.0.region == preferredRegion
            if lp != rp { return lp }
            if lhs.0.lineIds.count != rhs.0.lineIds.count { return lhs.0.lineIds.count > rhs.0.lineIds.count }
            if lhs.0.reading != rhs.0.reading { return lhs.0.reading < rhs.0.reading }
            return lhs.0.id < rhs.0.id
        }
        .prefix(limit)
        .map(\.0)
    }

    public static func nearest(to coordinate: Coordinate, in stations: [Station], limit: Int) -> [Station] {
        stations
            .map { ($0, $0.coordinate.distance(to: coordinate)) }
            .sorted { $0.1 < $1.1 }
            .prefix(limit)
            .map(\.0)
    }
}
