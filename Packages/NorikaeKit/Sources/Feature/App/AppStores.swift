import Domain
import Foundation
@preconcurrency import Network
import Observation

/// 提供状況（capabilities）を画面に配る（FR-CAP-01）
@MainActor
@Observable
public final class CapabilityStore {
    public private(set) var snapshot: CapabilitySnapshot
    private let repository: any CapabilityRepository

    public init(repository: any CapabilityRepository, initial: CapabilitySnapshot = .assumeAllAvailable) {
        self.repository = repository
        self.snapshot = initial
    }

    /// 起動時。キャッシュが新しければそれを、古ければ取り直す
    public func load() async {
        snapshot = await repository.capabilities()
    }

    /// 1 日 1 回の更新（アプリが前面に戻ったとき）
    public func refreshIfNeeded(now: Date = Date()) async {
        guard snapshot.needsRefresh(now: now) else { return }
        snapshot = await repository.capabilities()
    }
}

/// 通信できるか（FR-OFF-06、FR-LA-21）
@MainActor
@Observable
public final class NetworkMonitor {
    public private(set) var isOnline = true
    private let monitor: NWPathMonitor?

    /// - Parameter monitoring: `false` ならテスト用に状態を固定する
    public init(monitoring: Bool = true) {
        guard monitoring else {
            monitor = nil
            return
        }
        let monitor = NWPathMonitor()
        self.monitor = monitor
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in self?.isOnline = online }
        }
        monitor.start(queue: DispatchQueue(label: "norikae.network-monitor"))
    }

    /// テスト用
    public func setOnline(_ online: Bool) {
        isOnline = online
    }
}

/// 画面内のエラー表示の内容（frontend.md 10.3、api-contract 2.3）
public struct ErrorPresentation: Equatable, Sendable {
    public var message: String
    /// 再試行ボタンを出してよいか
    public var retryable: Bool

    public init(message: String, retryable: Bool) {
        self.message = message
        self.retryable = retryable
    }
}

extension AppError {
    /// エラーコードごとの扱い（api-contract 2.3 の表）
    public var presentation: ErrorPresentation {
        switch self {
        case .api(let error):
            switch error.code {
            case .attestationFailed:
                return ErrorPresentation(message: String(localized: "通信できませんでした", bundle: .module), retryable: false)
            case .rateLimited, .providerQuotaExceeded, .providerUnavailable, .internalError, .authenticationRequired:
                return ErrorPresentation(message: error.message, retryable: true)
            case .featureUnavailable:
                return ErrorPresentation(message: String(localized: "この区間・条件には対応していません", bundle: .module), retryable: false)
            case .stationNotFound:
                return ErrorPresentation(message: String(localized: "\(error.message)。駅を選び直してください", bundle: .module), retryable: false)
            case .invalidRequest, .routeNotFound, .routeContextExpired, .routeContextMismatch:
                return ErrorPresentation(message: error.message, retryable: false)
            case .unknown:
                // 表にないコードは retryable に従う
                return ErrorPresentation(message: error.message, retryable: error.retryable)
            }
        case .offline:
            return ErrorPresentation(message: String(localized: "オフラインです。通信できる状態で再試行してください", bundle: .module), retryable: true)
        case .network:
            return ErrorPresentation(message: String(localized: "通信できませんでした", bundle: .module), retryable: true)
        case .decoding:
            return ErrorPresentation(message: String(localized: "データを読み込めませんでした", bundle: .module), retryable: true)
        case .routeNoLongerAvailable:
            return ErrorPresentation(message: String(localized: "同じ経路が見つかりませんでした。検索結果から選び直してください", bundle: .module), retryable: false)
        case .unexpected:
            return ErrorPresentation(message: String(localized: "エラーが発生しました", bundle: .module), retryable: true)
        }
    }
}

/// オフラインのため実行できないときのエラー表示（FR-OFF-06）
extension ErrorPresentation {
    static var offlineAction: ErrorPresentation {
        ErrorPresentation(message: String(localized: "オフラインのため実行できません", bundle: .module), retryable: false)
    }
}
