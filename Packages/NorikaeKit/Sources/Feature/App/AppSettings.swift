import Domain
import Foundation
import Observation

/// 設定値（frontend.md 5.8、8.1）。UserDefaults に保存する
@MainActor
@Observable
public final class AppSettings {
    private let defaults: UserDefaults

    /// 主に使う地域。未設定ならオンボーディングを出す（FR-ONB-01）
    public var region: Region? {
        didSet { defaults.set(region?.rawValue, forKey: Keys.region) }
    }

    // 検索条件の初期値（FR-MY-04、FR-CND-06）
    public var fareKind: FareKind {
        didSet { defaults.set(fareKind.rawValue, forKey: Keys.fareKind) }
    }
    public var useShinkansen: Bool {
        didSet { defaults.set(useShinkansen, forKey: Keys.useShinkansen) }
    }
    public var usePaidExpress: Bool {
        didSet { defaults.set(usePaidExpress, forKey: Keys.usePaidExpress) }
    }
    public var sortOrder: RouteSortOrder {
        didSet { defaults.set(sortOrder.rawValue, forKey: Keys.sortOrder) }
    }

    // リマインド（FR-MY-05）
    public var reminderMargin: ReminderMargin {
        didSet { defaults.set(reminderMargin.rawValue, forKey: Keys.reminderMargin) }
    }
    public var walkingSpeed: WalkingSpeed {
        didSet { defaults.set(walkingSpeed.rawValue, forKey: Keys.walkingSpeed) }
    }

    /// iCloud 同期（FR-MY-06）。切り替えはアプリの再起動後に反映する
    public var iCloudSync: Bool {
        didSet { defaults.set(iCloudSync, forKey: Keys.iCloudSync) }
    }

    /// 起動時の iCloud 同期の設定（再起動が必要かの判定に使う）
    public let iCloudSyncAtLaunch: Bool

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        region = defaults.string(forKey: Keys.region).flatMap(Region.init(rawValue:))
        fareKind = defaults.string(forKey: Keys.fareKind).flatMap(FareKind.init(rawValue:)) ?? .ic
        useShinkansen = defaults.object(forKey: Keys.useShinkansen) as? Bool ?? false
        usePaidExpress = defaults.object(forKey: Keys.usePaidExpress) as? Bool ?? false
        sortOrder = defaults.string(forKey: Keys.sortOrder).flatMap(RouteSortOrder.init(rawValue:)) ?? .fastest
        reminderMargin = ReminderMargin(rawValue: defaults.object(forKey: Keys.reminderMargin) as? Int ?? 3) ?? .three
        walkingSpeed = defaults.string(forKey: Keys.walkingSpeed).flatMap(WalkingSpeed.init(rawValue:)) ?? .normal
        let sync = defaults.object(forKey: Keys.iCloudSync) as? Bool ?? true
        iCloudSync = sync
        iCloudSyncAtLaunch = sync
    }

    /// 主に使う地域（未設定なら首都圏）
    public var preferredRegion: Region { region ?? .kanto }

    /// 設定画面で選ぶ地域（FR-MY-07）
    public var selectedRegion: Region {
        get { preferredRegion }
        set { region = newValue }
    }

    public var needsRestartForSync: Bool { iCloudSync != iCloudSyncAtLaunch }

    enum Keys {
        static let region = "settings.region"
        static let fareKind = "settings.fareKind"
        static let useShinkansen = "settings.useShinkansen"
        static let usePaidExpress = "settings.usePaidExpress"
        static let sortOrder = "settings.sortOrder"
        static let reminderMargin = "settings.reminderMargin"
        static let walkingSpeed = "settings.walkingSpeed"
        static let iCloudSync = "settings.iCloudSync"
    }
}
