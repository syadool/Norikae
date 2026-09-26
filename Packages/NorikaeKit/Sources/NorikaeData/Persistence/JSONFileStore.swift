import CryptoKit
import Domain
import Foundation

/// 端末内の JSON ファイルによる保存（キャッシュ・提供状況・出典・駅マスタの差分）
public actor JSONFileStore {
    private let directory: URL

    public init(directory: URL) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// アプリの Caches 配下
    public static func caches(_ name: String) -> JSONFileStore {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        return JSONFileStore(directory: base.appending(path: name, directoryHint: .isDirectory))
    }

    /// アプリの Application Support 配下
    public static func applicationSupport(_ name: String) -> JSONFileStore {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        return JSONFileStore(directory: base.appending(path: name, directoryHint: .isDirectory))
    }

    public func load<T: Decodable & Sendable>(_ type: T.Type, key: String) -> T? {
        guard let data = try? Data(contentsOf: url(for: key)) else { return nil }
        return try? NorikaeJSON.makeDecoder().decode(T.self, from: data)
    }

    public func save<T: Encodable & Sendable>(_ value: T, key: String) {
        guard let data = try? NorikaeJSON.makeEncoder().encode(value) else { return }
        try? data.write(to: url(for: key), options: .atomic)
    }

    public func remove(key: String) {
        try? FileManager.default.removeItem(at: url(for: key))
    }

    private func url(for key: String) -> URL {
        directory.appending(path: "\(key).json")
    }
}

/// 端末をまたいで変わらないハッシュ（キャッシュのキーに使う）
enum StableHash {
    static func of<T: Encodable>(_ value: T) -> String {
        let data = (try? NorikaeJSON.makeEncoder().encode(value)) ?? Data()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
