@preconcurrency import CoreLocation
import Domain
import Foundation
@preconcurrency import MapKit
@preconcurrency import UserNotifications

// MARK: - 位置情報（「使用中のみ」、frontend.md 7.2）

public enum LocationAuthorization: Sendable, Equatable {
    case notDetermined
    case authorized
    case denied
}

public enum LocationError: Error, Sendable {
    case denied
    case unavailable
}

/// 位置情報。権限は機能を初めて使うときに要求する（FR-ONB-03）
@MainActor
public protocol LocationProviding: AnyObject {
    var authorization: LocationAuthorization { get }
    func requestAuthorizationIfNeeded() async -> LocationAuthorization
    /// 現在地。権限がなければ要求し、拒否されていれば `LocationError.denied`
    func currentLocation() async throws -> Coordinate
}

@MainActor
public final class LocationService: NSObject, LocationProviding {
    private let manager = CLLocationManager()
    private var authorizationWaiters: [CheckedContinuation<LocationAuthorization, Never>] = []
    private var locationWaiters: [CheckedContinuation<Coordinate, any Error>] = []

    public override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    public var authorization: LocationAuthorization {
        Self.map(manager.authorizationStatus)
    }

    public func requestAuthorizationIfNeeded() async -> LocationAuthorization {
        guard manager.authorizationStatus == .notDetermined else { return authorization }
        return await withCheckedContinuation { continuation in
            authorizationWaiters.append(continuation)
            manager.requestWhenInUseAuthorization()
        }
    }

    public func currentLocation() async throws -> Coordinate {
        guard await requestAuthorizationIfNeeded() == .authorized else { throw LocationError.denied }
        return try await withCheckedThrowingContinuation { continuation in
            locationWaiters.append(continuation)
            manager.requestLocation()
        }
    }

    fileprivate func didChangeAuthorization(_ status: CLAuthorizationStatus) {
        guard status != .notDetermined else { return }
        let waiters = authorizationWaiters
        authorizationWaiters.removeAll()
        waiters.forEach { $0.resume(returning: Self.map(status)) }
    }

    fileprivate func didReceive(_ result: Result<Coordinate, any Error>) {
        let waiters = locationWaiters
        locationWaiters.removeAll()
        waiters.forEach { $0.resume(with: result) }
    }

    private static func map(_ status: CLAuthorizationStatus) -> LocationAuthorization {
        switch status {
        case .notDetermined: .notDetermined
        case .authorizedWhenInUse, .authorizedAlways: .authorized
        default: .denied
        }
    }
}

extension LocationService: CLLocationManagerDelegate {
    nonisolated public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in self.didChangeAuthorization(status) }
    }

    nonisolated public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        let coordinate = Coordinate(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
        Task { @MainActor in self.didReceive(.success(coordinate)) }
    }

    nonisolated public func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        Task { @MainActor in self.didReceive(.failure(LocationError.unavailable)) }
    }
}

/// テスト・プレビュー用の固定の位置情報
@MainActor
public final class FixedLocationProvider: LocationProviding {
    public var authorization: LocationAuthorization
    private let coordinate: Coordinate?

    public init(coordinate: Coordinate?, authorization: LocationAuthorization = .authorized) {
        self.coordinate = coordinate
        self.authorization = authorization
    }

    public func requestAuthorizationIfNeeded() async -> LocationAuthorization { authorization }

    public func currentLocation() async throws -> Coordinate {
        guard authorization == .authorized else { throw LocationError.denied }
        guard let coordinate else { throw LocationError.unavailable }
        return coordinate
    }
}

// MARK: - 徒歩時間（MapKit、NFR-03：位置情報はサーバーに送らない）

public protocol WalkingTimeProviding: Sendable {
    /// 徒歩の所要時間（秒）。求められなければ `nil`
    func walkingDuration(from: Coordinate, to: Coordinate) async -> TimeInterval?
}

public struct MapKitWalkingTimeService: WalkingTimeProviding {
    public init() {}

    public func walkingDuration(from: Coordinate, to: Coordinate) async -> TimeInterval? {
        await Self.calculate(from: from, to: to)
    }

    /// MapKit の型はメインスレッドで扱う
    @MainActor
    private static func calculate(from: Coordinate, to: Coordinate) async -> TimeInterval? {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: from.latitude, longitude: from.longitude)))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: to.latitude, longitude: to.longitude)))
        request.transportType = .walking
        return try? await MKDirections(request: request).calculateETA().expectedTravelTime
    }
}

public struct FixedWalkingTimeProvider: WalkingTimeProviding {
    private let duration: TimeInterval?

    public init(duration: TimeInterval?) {
        self.duration = duration
    }

    public func walkingDuration(from: Coordinate, to: Coordinate) async -> TimeInterval? { duration }
}

// MARK: - 出発リマインド（ローカル通知、frontend.md 7.1）

public protocol ReminderScheduling: Sendable {
    /// 通知の権限。案内開始を初めて使うときに要求する
    func requestAuthorizationIfNeeded() async -> Bool
    func schedule(at date: Date, title: String, body: String) async
    func cancel() async
}

public struct NotificationReminderScheduler: ReminderScheduling {
    static let identifier = "norikae.departure-reminder"

    public init() {}

    public func requestAuthorizationIfNeeded() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        case .authorized, .provisional, .ephemeral:
            return true
        default:
            return false
        }
    }

    public func schedule(at date: Date, title: String, body: String) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.identifier])
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let components = JapanCalendar.calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        try? await center.add(UNNotificationRequest(identifier: Self.identifier, content: content, trigger: trigger))
    }

    public func cancel() async {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.identifier])
    }
}

/// テスト用。予約を記録する
public actor RecordingReminderScheduler: ReminderScheduling {
    public private(set) var scheduled: [(date: Date, title: String, body: String)] = []
    public private(set) var cancelCount = 0
    private let granted: Bool

    public init(granted: Bool = true) {
        self.granted = granted
    }

    public func requestAuthorizationIfNeeded() async -> Bool { granted }

    public func schedule(at date: Date, title: String, body: String) async {
        scheduled.append((date, title, body))
    }

    public func cancel() async {
        cancelCount += 1
    }
}
