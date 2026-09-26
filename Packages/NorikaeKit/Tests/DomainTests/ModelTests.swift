import Domain
import Foundation
import Testing

@Suite("運賃の表示（api-contract 3.8）")
struct FareDisplayTests {
    @Test("設定した種別の運賃があれば、その金額")
    func preferred() {
        let fare = Fare(fareType: .exact, icTotal: 836, ticketTotal: 850)
        #expect(fare.display(preferred: .ic) == .amount(836, kind: .ic, isPreferredKind: true))
        #expect(fare.display(preferred: .ticket) == .amount(850, kind: .ticket, isPreferredKind: true))
    }

    @Test("設定した種別がなく、もう一方があれば、種別を併記する")
    func otherKind() {
        let fare = Fare(fareType: .exact, icTotal: 684)
        #expect(fare.display(preferred: .ticket) == .amount(684, kind: .ic, isPreferredKind: false))
    }

    @Test("概算だけなら「約◯円」、何もなければ「運賃不明」")
    func estimatedAndUnavailable() {
        #expect(Fare(fareType: .estimated, estimatedTotal: 840).display(preferred: .ic) == .estimated(840))
        #expect(Fare.unavailable.display(preferred: .ic) == .unavailable)
    }

    @Test("特急料金が分かっていれば合計に含める")
    func express() {
        let fare = Fare(fareType: .exact, icTotal: 1000, ticketTotal: 1010, expressTotal: 760)
        #expect(fare.display(preferred: .ic).value == 1760)
    }

    @Test("未知の fareType は運賃不明として扱う")
    func unknownFareType() throws {
        let json = #"{"fareType":"something-new","icTotal":100}"#
        let fare = try NorikaeJSON.makeDecoder().decode(Fare.self, from: Data(json.utf8))
        #expect(fare.fareType == .unavailable)
    }
}

@Suite("路線記号の代替表示（NFR-A11Y-04）")
struct LineLabelTests {
    @Test("symbol → displayCode → name の順")
    func fallback() {
        #expect(Line(id: "1", operatorId: "o", name: "山手線", symbol: "JY", region: .kanto).label == "JY")
        #expect(Line(id: "2", operatorId: "o", name: "相鉄・JR直通線", displayCode: "相直", region: .kanto).label == "相直")
        #expect(Line(id: "3", operatorId: "o", name: "サンプル線", region: .kanto).label == "サンプル線")
        // 空文字は使わない約束だが、来ても代替する
        #expect(Line(id: "4", operatorId: "o", name: "線", symbol: "", displayCode: "略", region: .kanto).label == "略")
    }

    @Test("路線色がなければ nil（既定色で描く）")
    func missingColor() {
        #expect(Line(id: "1", operatorId: "o", name: "線", region: .kanto).rgbColor == nil)
        #expect(Line(id: "1", operatorId: "o", name: "線", color: "#80C241", region: .kanto).rgbColor == RGBColor(hex: 0x80C241))
    }
}

@Suite("暗い面での路線色（design-spec 3.6）")
struct RGBColorTests {
    @Test("コントラストが 3:1 未満なら明るくする")
    func brighten() {
        let surface = RGBColor.liveActivitySurface
        // 注：design-spec 3.6 で例に挙がっている副都心線 #9C5E31・東横線 #DA0442 は、WCAG の計算では約 3.2:1 あり、
        // 3:1 の基準では明るくならない。ここでは基準を下回る暗い色で確かめる
        for hex: UInt32 in [0x1F2F6F, 0x5B1A18] {
            let color = RGBColor(hex: hex)
            #expect(color.contrastRatio(with: surface) < 3)
            let adjusted = color.brightened(against: surface)
            #expect(adjusted.contrastRatio(with: surface) >= 3)
        }
    }

    @Test("十分明るい色はそのまま")
    func keep() {
        let yamanote = RGBColor(hex: 0x80C241)
        #expect(yamanote.brightened(against: .liveActivitySurface) == yamanote)
    }
}

@Suite("運行日と曜日区分")
struct ServiceDateTests {
    @Test("深夜 4 時より前は前日の運行日")
    func operatingDay() {
        #expect(ServiceDate.operatingDay(containing: Fixtures.t(0)).rawValue == "2026-09-26")
        // 翌 0:30
        #expect(ServiceDate.operatingDay(containing: Fixtures.t(990)).rawValue == "2026-09-26")
        // 翌 4:10
        #expect(ServiceDate.operatingDay(containing: Fixtures.t(1210)).rawValue == "2026-09-27")
    }

    @Test("平日・土曜・休日（祝日と振替休日を含む）", arguments: [
        ("2026-09-25", DayType.weekday),  // 金
        ("2026-09-26", DayType.saturday), // 土
        ("2026-09-27", DayType.holiday),  // 日
        ("2026-09-21", DayType.holiday),  // 敬老の日
        ("2026-09-22", DayType.holiday),  // 国民の休日（敬老の日と秋分の日の間）
        ("2026-09-23", DayType.holiday),  // 秋分の日
        ("2026-05-06", DayType.holiday),  // 振替休日（5/3 が日曜）
        ("2026-01-01", DayType.holiday),  // 元日
    ])
    func dayType(date: String, expected: DayType) {
        #expect(DayType(serviceDate: ServiceDate(rawValue: date)) == expected)
    }
}

@Suite("運行状況")
struct OperationStatusTests {
    @Test("unknown は平常と別の状態。未知の値は other として扱う")
    func unknownIsNotNormal() throws {
        let decoder = NorikaeJSON.makeDecoder()
        let unknown = try decoder.decode(OperationStatusKind.self, from: Data(#""unknown""#.utf8))
        #expect(unknown == .unknown)
        #expect(unknown != .normal)
        let future = try decoder.decode(OperationStatusKind.self, from: Data(#""someday""#.utf8))
        #expect(future == .other)
    }
}

@Suite("検索条件")
struct SearchQueryTests {
    @Test("経由駅は最大 3 つ")
    func maxVia() {
        let query = RouteSearchQuery(fromStationId: "A", toStationId: "B", viaStationIds: ["1", "2", "3", "4"], dateTime: Fixtures.base)
        #expect(query.viaStationIds == ["1", "2", "3"])
    }

    @Test("非対応の条件を外す（FR-CND-02）")
    func removing() {
        let query = RouteSearchQuery(fromStationId: "A", toStationId: "B", viaStationIds: ["V"], dateTime: Fixtures.base, searchType: .lastTrain)
        #expect(query.removableConditions == [.viaStations, .firstLastTrain])
        #expect(query.removing(.viaStations).viaStationIds.isEmpty)
        #expect(query.removing(.firstLastTrain).searchType == .departure)
    }

    @Test("入れ替え（FR-SRC-07）")
    func swapped() {
        let query = RouteSearchQuery(fromStationId: "A", toStationId: "B", viaStationIds: ["1", "2"], dateTime: Fixtures.base)
        let swapped = query.swapped()
        #expect(swapped.fromStationId == "B")
        #expect(swapped.toStationId == "A")
        #expect(swapped.viaStationIds == ["2", "1"])
    }

    @Test("駅の統合で ID を置き換える（FR-SRC-09）")
    func replacing() {
        let query = RouteSearchQuery(fromStationId: "old", toStationId: "B", viaStationIds: ["old"], dateTime: Fixtures.base)
        let replaced = query.replacingStationIDs(["old": "new"])
        #expect(replaced.fromStationId == "new")
        #expect(replaced.viaStationIds == ["new"])
    }

    @Test("日時を含めて JSON に書き出せる（日本時間）")
    func encodesJST() throws {
        let query = RouteSearchQuery(fromStationId: "A", toStationId: "B", dateTime: Fixtures.base)
        let json = String(decoding: try NorikaeJSON.makeEncoder().encode(query), as: UTF8.self)
        #expect(json.contains(#""dateTime":"2026-09-26T08:00:00+09:00""#))
    }
}

@Suite("提供状況（FR-CAP）")
struct CapabilityTests {
    @Test("キャッシュもないときは、全機能を利用可能として扱う")
    func assumeAvailable() {
        let snapshot = CapabilitySnapshot.assumeAllAvailable
        #expect(snapshot.isSupported(.timetable, lineId: "any"))
        #expect(snapshot.isSupported(.viaStations, region: .kansai))
        #expect(snapshot.needsRefresh(now: Fixtures.base))
    }

    @Test("非対応の判定と 1 日 1 回の更新")
    func unavailable() {
        let snapshot = CapabilitySnapshot(
            lines: [LineCapability(lineId: "L", features: [.timetable: .unavailable, .tripUpdates: .partial], asOf: Fixtures.base)],
            regions: [RegionCapability(region: .kansai, features: [.viaStations: .unavailable])],
            fetchedAt: Fixtures.base
        )
        #expect(!snapshot.isSupported(.timetable, lineId: "L"))
        #expect(snapshot.isSupported(.tripUpdates, lineId: "L"))
        #expect(!snapshot.isSupported(.viaStations, region: .kansai))
        #expect(snapshot.isSupported(.viaStations, region: .kanto))
        #expect(!snapshot.needsRefresh(now: Fixtures.t(60)))
        #expect(snapshot.needsRefresh(now: Fixtures.t(24 * 60)))
    }
}
