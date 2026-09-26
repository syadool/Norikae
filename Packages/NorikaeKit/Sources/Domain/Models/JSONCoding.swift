import Foundation

/// API の JSON を読み書きするための設定（api-contract 2 章）
///
/// - 日時は ISO 8601、タイムゾーン付き。書き出しは日本時間（`+09:00`）
/// - Live Activity の `ContentState` は ActivityKit が既定の `JSONDecoder` で読むため、この設定は使わない（5.3）
public enum NorikaeJSON {
    public static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            if let date = parseDate(text) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "ISO 8601 の日時ではありません: \(text)")
        }
        return decoder
    }

    public static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(formatDate(date))
        }
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    public static func parseDate(_ text: String) -> Date? {
        let strategies = [
            Date.ISO8601FormatStyle(timeZoneSeparator: .colon),
            Date.ISO8601FormatStyle(timeZoneSeparator: .colon, includingFractionalSeconds: true),
            Date.ISO8601FormatStyle(),
            Date.ISO8601FormatStyle(includingFractionalSeconds: true),
        ]
        for strategy in strategies {
            if let date = try? strategy.parse(text) { return date }
        }
        // 念のため、Foundation の従来の実装でも読む
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: text)
    }

    /// 例：`2026-09-26T08:15:00+09:00`
    public static func formatDate(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = JapanCalendar.timeZone
        return formatter.string(from: date)
    }
}

/// 変動するデータの応答の外側（api-contract 2.1）
public struct Envelope<Payload: Decodable & Sendable>: Decodable, Sendable {
    public var meta: ResponseMeta
    public var data: Payload
}

/// エラー応答の外側（api-contract 2.3）
public struct ErrorEnvelope: Decodable, Sendable {
    public var error: APIError
}
