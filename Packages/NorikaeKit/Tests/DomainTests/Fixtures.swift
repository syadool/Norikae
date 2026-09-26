import Domain
import Foundation

/// テスト用の経路を組み立てる
enum Fixtures {
    /// 2026-09-26 08:00 JST
    static let base: Date = {
        var components = DateComponents()
        components.year = 2026
        components.month = 9
        components.day = 26
        components.hour = 8
        components.minute = 0
        return JapanCalendar.calendar.date(from: components)!
    }()

    static func t(_ minutes: Int) -> Date {
        base.addingTimeInterval(TimeInterval(minutes * 60))
    }

    static func stop(_ station: String, _ minute: Int, delay: Int? = nil, platform: String? = nil) -> StopPoint {
        let time = t(minute)
        return StopPoint(
            stationId: station, scheduledTime: time,
            estimatedTime: delay.map { time.addingTimeInterval(TimeInterval($0 * 60)) },
            platform: platform, serviceDate: .operatingDay(containing: time)
        )
    }

    static func train(_ line: String, _ from: String, _ dep: Int, _ to: String, _ arr: Int, delay: Int? = nil, runId: String? = "run") -> Leg {
        .train(TrainLeg(
            lineId: line, trainTypeId: "local", trainRunId: runId, destinationName: "行き先",
            from: stop(from, dep, delay: delay), to: stop(to, arr, delay: delay), stopCount: 3
        ))
    }

    static func walk(_ station: String, _ minutes: Int) -> Leg {
        .walk(WalkLeg(fromStationId: station, toStationId: station, durationMinutes: minutes))
    }

    static func route(
        _ id: String, _ legs: [Leg], fare: Fare = Fare(fareType: .exact, icTotal: 500, ticketTotal: 510),
        disruption: Bool = false, context: String? = nil
    ) -> Route {
        let trains = legs.compactMap { leg -> TrainLeg? in
            if case .train(let train) = leg { return train }
            return nil
        }
        let departure = trains.first!.from.scheduledTime
        let arrival = trains.last!.to.scheduledTime
        return Route(
            id: id, departureTime: departure, arrivalTime: arrival,
            durationMinutes: Int(arrival.timeIntervalSince(departure) / 60), transferCount: trains.count - 1,
            fare: fare, legs: legs, hasServiceDisruption: disruption, routeContext: RouteContext(context ?? "ctx-\(id)")
        )
    }
}
