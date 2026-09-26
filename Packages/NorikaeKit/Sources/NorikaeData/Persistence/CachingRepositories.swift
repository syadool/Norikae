import Domain
import Foundation

/// 提供状況の取得元（API またはモック）
public protocol CapabilitySource: Sendable {
    func fetch() async throws -> CapabilitySnapshot
}

/// 出典の取得元（API またはモック）
public protocol AttributionSource: Sendable {
    func fetch() async throws -> [Attribution]
}

/// 提供状況の Repository（FR-CAP-01、FR-CAP-03）
///
/// 起動時と 1 日 1 回取得して端末にキャッシュする。取れなければ直前のキャッシュ、それもなければ全機能を利用可能とみなす。
public actor CachingCapabilityRepository: CapabilityRepository {
    private let source: any CapabilitySource
    private let store: JSONFileStore
    private var cached: CapabilitySnapshot?

    public init(source: any CapabilitySource, store: JSONFileStore = .applicationSupport("capabilities")) {
        self.source = source
        self.store = store
    }

    public func capabilities() async -> CapabilitySnapshot {
        let current = await cachedSnapshot()
        if let current, !current.needsRefresh(now: Date()) { return current }
        do {
            return try await refresh()
        } catch {
            return current ?? .assumeAllAvailable
        }
    }

    public func refresh() async throws -> CapabilitySnapshot {
        var snapshot = try await source.fetch()
        if snapshot.fetchedAt == nil { snapshot.fetchedAt = Date() }
        cached = snapshot
        await store.save(snapshot, key: "snapshot")
        return snapshot
    }

    private func cachedSnapshot() async -> CapabilitySnapshot? {
        if let cached { return cached }
        cached = await store.load(CapabilitySnapshot.self, key: "snapshot")
        return cached
    }
}

/// 出典の Repository（FR-MY-08）。取得できない場合は直前のキャッシュを返す
public actor CachingAttributionRepository: AttributionRepository {
    private let source: any AttributionSource
    private let store: JSONFileStore

    public init(source: any AttributionSource, store: JSONFileStore = .applicationSupport("attributions")) {
        self.source = source
        self.store = store
    }

    public func attributions() async throws -> [Attribution] {
        do {
            let list = try await source.fetch()
            await store.save(list, key: "all")
            return list
        } catch {
            if let cached = await store.load([Attribution].self, key: "all") { return cached }
            throw error
        }
    }
}
