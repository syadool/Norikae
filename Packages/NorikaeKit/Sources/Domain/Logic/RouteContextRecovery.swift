import Foundation

/// `routeContext` の期限切れへの対応（api-contract 4.2）。画面ごとに重複させないためのユースケース
///
/// 1. 手元の `routeContext` で処理する
/// 2. `ROUTE_CONTEXT_EXPIRED`（または `ROUTE_CONTEXT_MISMATCH`）なら、保存した検索条件で API-01 を呼び直す
/// 3. 元の経路と同じ経路（区間の路線・乗車駅・降車駅・出発時刻が一致）を探し、見つかれば新しい `routeContext` で続ける
/// 4. 見つからなければ `AppError.routeNoLongerAvailable` を投げ、新しい検索結果で選び直してもらう
public struct RouteContextRecovery: Sendable {
    public let repository: any RouteRepository

    public init(repository: any RouteRepository) {
        self.repository = repository
    }

    /// 経路を最新の `routeContext` に取り直す
    public func refreshedRoute(_ route: Route, query: RouteSearchQuery) async throws -> (route: Route, result: RouteSearchResult) {
        let result = try await repository.searchRoutes(query)
        guard let match = RouteSignature(route: route).findMatch(in: result.routes) else {
            throw AppError.routeNoLongerAvailable(result)
        }
        return (match, result)
    }

    /// `routeContext` を使う処理を、期限切れなら 1 回だけ取り直して実行する
    ///
    /// - Returns: 処理の結果と、実際に使った経路（取り直した場合は新しい `routeContext` を持つ）
    public func perform<T: Sendable>(
        route: Route,
        query: RouteSearchQuery,
        refreshOn codes: Set<APIErrorCode> = [.routeContextExpired],
        _ operation: @Sendable (Route) async throws -> T
    ) async throws -> (value: T, route: Route) {
        do {
            return (try await operation(route), route)
        } catch {
            guard let code = AppError.wrap(error).apiCode, codes.contains(code) else { throw error }
            let refreshed = try await refreshedRoute(route, query: query)
            return (try await operation(refreshed.route), refreshed.route)
        }
    }

    /// 1 本前・1 本後の経路（API-02）。期限切れなら取り直す
    public func adjacentRoute(from route: Route, query: RouteSearchQuery, direction: AdjacentDirection) async throws -> AdjacentRouteResult {
        let repository = self.repository
        return try await perform(route: route, query: query) { current in
            try await repository.adjacentRoute(context: current.routeContext, direction: direction)
        }.value
    }
}
