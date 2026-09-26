import Domain
import Foundation

/// 案内中の経路の保存先（App Group の共有領域、frontend.md 8.1・9.2）
///
/// 同時に案内できる経路は 1 つだけ（FR-LA-02）なので、1 件だけ保存する。
public protocol GuidanceSessionStoring: Sendable {
    func load() -> GuidanceSession?
    func save(_ session: GuidanceSession?)
}

public struct AppGroupGuidanceSessionStore: GuidanceSessionStoring {
    /// App Group の ID（project.yml の entitlements と合わせる）
    public static let defaultAppGroup = "group.com.example.norikae"

    private let fileURL: URL?

    public init(appGroup: String = AppGroupGuidanceSessionStore.defaultAppGroup) {
        let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        fileURL = container?.appending(path: "guidance-session.json")
    }

    public func load() -> GuidanceSession? {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? NorikaeJSON.makeDecoder().decode(GuidanceSession.self, from: data)
    }

    public func save(_ session: GuidanceSession?) {
        guard let fileURL else { return }
        guard let session else {
            try? FileManager.default.removeItem(at: fileURL)
            return
        }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? NorikaeJSON.makeEncoder().encode(session) {
            try? data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }
}

/// メモリ版（テスト用）
public final class InMemoryGuidanceSessionStore: GuidanceSessionStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var session: GuidanceSession?

    public init(session: GuidanceSession? = nil) {
        self.session = session
    }

    public func load() -> GuidanceSession? {
        lock.withLock { session }
    }

    public func save(_ session: GuidanceSession?) {
        lock.withLock { self.session = session }
    }
}
