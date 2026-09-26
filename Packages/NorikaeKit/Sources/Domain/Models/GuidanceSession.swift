import Foundation

/// 案内中の経路（App Group の共有領域に保存する、frontend.md 8.1）
///
/// `routeContext` は期限切れを前提に扱い、必ず検索条件も一緒に持つ（api-contract 4.2）。
public struct GuidanceSession: Codable, Sendable, Hashable {
    public var activityId: String
    public var route: Route
    public var query: RouteSearchQuery
    public var summary: GuidanceSummary
    public var startedAt: Date
    /// 最後に登録（API-09）したプッシュトークン。未登録なら `nil`（通信が戻ったら再試行する、FR-LA-14）
    public var registeredPushToken: String?
    /// 取得済みで未登録のプッシュトークン
    public var pendingPushToken: String?

    public init(
        activityId: String, route: Route, query: RouteSearchQuery, summary: GuidanceSummary, startedAt: Date,
        registeredPushToken: String? = nil, pendingPushToken: String? = nil
    ) {
        self.activityId = activityId
        self.route = route
        self.query = query
        self.summary = summary
        self.startedAt = startedAt
        self.registeredPushToken = registeredPushToken
        self.pendingPushToken = pendingPushToken
    }

    /// 登録が済んでいないか
    public var needsRegistration: Bool {
        guard let pendingPushToken else { return false }
        return pendingPushToken != registeredPushToken
    }
}
