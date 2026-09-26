import Domain
import Foundation

/// モックの場面（api-contract 7 章）
///
/// 起動引数 `-MockScenario <rawValue>` で切り替えられる。池袋 → 横浜で検索すると、場面ごとに作り込んだ経路を返す。
/// それ以外の駅の組み合わせでは、駅マスタの路線から組み立てた経路を返す。
public enum MockScenario: String, CaseIterable, Sendable {
    /// #1 #2 #6：5 本の経路（横スクロール、遅延を含む）
    case standard
    /// #1：3 本の経路
    case threeRoutes
    /// #3：所要時間の差が大きい
    case wideSpread
    /// #4：終電で日付をまたぐ
    case overnight
    /// #5：乗換 0 回と 3 回
    case manyTransfers
    /// #7：乗車位置・番線がない
    case missingOptional
    /// #8：通信エラー（再試行できる）
    case retryableError
    /// #8：通信エラー（再試行できない）
    case nonRetryableError
    /// #9：検索結果が 0 件
    case empty
    /// #10：応答が数秒遅い
    case slow
    /// #11：路線記号・路線色がない路線
    case noSymbolLine
    /// #12：概算・不明・種別の混在
    case fareVariants
    /// #13：一部欠損・古い情報・警告
    case partialStale
    /// #17：FEATURE_UNAVAILABLE（経由駅・始発終電を指定したとき）
    case featureUnavailable
    /// #17：ROUTE_CONTEXT_EXPIRED（最初の検索の routeContext が期限切れ）
    case contextExpired
    /// #18：1 本後の経路で構成が変わる
    case adjacentStructureChange

    // #14（運行情報 unknown）、#15（capabilities の非対応）、#16（trainRunId なし）は、どの場面でも含まれる
}

/// モックで使う ID
public enum MockID {
    public static func station(_ key: String) -> String { "jp.station.\(key)" }
    public static func line(_ key: String) -> String { "jp.line.\(key)" }

    public static let ikebukuro = station("ikebukuro")
    public static let shibuya = station("shibuya")
    public static let shinjuku = station("shinjuku")
    public static let shinagawa = station("shinagawa")
    public static let yokohama = station("yokohama")
    public static let tokyo = station("tokyo")
    public static let musashiKosugi = station("musashi-kosugi")
    public static let hazawa = station("hazawa-yokohama-kokudai")
    public static let omiya = station("omiya")

    public static let yamanote = line("jr-east.yamanote")
    public static let shonanShinjuku = line("jr-east.shonan-shinjuku")
    public static let tokaido = line("jr-east.tokaido")
    public static let chuoRapid = line("jr-east.chuo-rapid")
    public static let saikyo = line("jr-east.saikyo")
    public static let keihinTohoku = line("jr-east.keihin-tohoku")
    public static let sotetsuDirect = line("jr-east.sotetsu-direct")
    public static let ginza = line("tokyo-metro.ginza")
    public static let marunouchi = line("tokyo-metro.marunouchi")
    public static let fukutoshin = line("tokyo-metro.fukutoshin")
    public static let oedo = line("toei.oedo")
    public static let toyoko = line("tokyu.toyoko")
    public static let kyoto = line("jr-west.kyoto")
    public static let osakaLoop = line("jr-west.osaka-loop")
    public static let midosuji = line("osaka-metro.midosuji")
    public static let sennichimae = line("osaka-metro.sennichimae")
    public static let hankyuKobe = line("hankyu.kobe")
    /// 記号・略称・色のない路線（#11、応答の includes で返す）
    public static let noSymbol = line("sample.no-symbol")

    public static let local = "jp.train-type.local"
    public static let localStop = "jp.train-type.local-stop"
    public static let rapid = "jp.train-type.rapid"
    public static let specialRapid = "jp.train-type.special-rapid"
    public static let express = "jp.train-type.express"
    public static let limitedExpress = "jp.train-type.limited-express"
}

/// モックの参照データ
public enum MockData {
    public static let catalog: Catalog = StationMasterSnapshot.bundled().catalog

    /// 記号・略称・色のない路線（#11）
    public static let noSymbolLine = Line(id: MockID.noSymbol, operatorId: "jp.operator.jr-east", name: "サンプル線", region: .kanto)

    /// 路線の駅の並び（停車駅一覧・時刻表・経路の組み立てに使う）
    public static let lineSequences: [String: [String]] = [
        MockID.yamanote: ["ikebukuro", "shinjuku", "shibuya", "ebisu", "osaki", "shinagawa", "shimbashi", "tokyo", "kanda", "ueno"],
        MockID.shonanShinjuku: ["omiya", "ikebukuro", "shinjuku", "shibuya", "ebisu", "osaki", "musashi-kosugi", "yokohama"],
        MockID.tokaido: ["tokyo", "shimbashi", "shinagawa", "kawasaki", "yokohama"],
        MockID.chuoRapid: ["tokyo", "kanda", "shinjuku", "kichijoji"],
        MockID.saikyo: ["omiya", "ikebukuro", "shinjuku", "shibuya", "ebisu", "osaki"],
        MockID.keihinTohoku: ["omiya", "ueno", "kanda", "tokyo", "shimbashi", "shinagawa", "kawasaki", "yokohama"],
        MockID.sotetsuDirect: ["musashi-kosugi", "hazawa-yokohama-kokudai"],
        MockID.ginza: ["shibuya", "shimbashi", "ginza", "kyobashi", "nihombashi", "kanda", "ueno"],
        MockID.marunouchi: ["ikebukuro", "otemachi", "tokyo", "ginza", "shinjuku-sanchome", "shinjuku"],
        MockID.fukutoshin: ["ikebukuro", "shinjuku-sanchome", "meiji-jingumae", "shibuya"],
        MockID.oedo: ["shinjuku", "roppongi"],
        MockID.toyoko: ["shibuya", "nakameguro", "jiyugaoka", "musashi-kosugi", "kikuna", "yokohama"],
        MockID.kyoto: ["kyoto", "takatsuki", "shin-osaka", "osaka"],
        MockID.osakaLoop: ["osaka", "kyobashi-osaka", "tsuruhashi", "tennoji"],
        MockID.midosuji: ["shin-osaka", "umeda", "namba", "tennoji"],
        MockID.sennichimae: ["namba", "nippombashi", "tsuruhashi"],
        MockID.hankyuKobe: ["osaka-umeda", "nishinomiya-kitaguchi", "kobe-sannomiya"],
    ].mapValues { $0.map(MockID.station) }

    /// 路線ごとの提供状況（#15）。frontend.md 1.4 の初期の対応範囲に合わせている
    public static func capabilities(now: Date) -> CapabilitySnapshot {
        let metroLike: Set<String> = [MockID.ginza, MockID.marunouchi, MockID.fukutoshin, MockID.oedo]
        let jrEast: Set<String> = [MockID.yamanote, MockID.shonanShinjuku, MockID.tokaido, MockID.chuoRapid, MockID.saikyo, MockID.keihinTohoku, MockID.sotetsuDirect]
        var lines: [LineCapability] = []
        for line in catalog.lines.values {
            let features: [CapabilityFeature: DataAvailability]
            if metroLike.contains(line.id) {
                features = [
                    .routeSearch: .available, .timetable: .available, .stopList: .available, .fare: .available,
                    .operationAlerts: .available, .tripUpdates: .available, .vehiclePositions: .unavailable,
                    .platform: .available, .boardingPosition: line.id == MockID.fukutoshin ? .available : .unavailable,
                ]
            } else if jrEast.contains(line.id) {
                features = [
                    .routeSearch: .available, .timetable: .unavailable, .stopList: line.id == MockID.sotetsuDirect ? .unavailable : .available,
                    .fare: .partial, .operationAlerts: line.id == MockID.sotetsuDirect ? .unavailable : .available,
                    .tripUpdates: line.id == MockID.yamanote ? .available : .unavailable, .vehiclePositions: .unavailable,
                    .platform: .partial, .boardingPosition: .unavailable,
                ]
            } else {
                // 東急・関西圏：経路検索のみ（外部 API）
                features = [
                    .routeSearch: .available, .timetable: .unavailable, .stopList: .unavailable, .fare: .partial,
                    .operationAlerts: .unavailable, .tripUpdates: .unavailable, .vehiclePositions: .unavailable,
                    .platform: .unavailable, .boardingPosition: .unavailable,
                ]
            }
            lines.append(LineCapability(lineId: line.id, features: features, asOf: now))
        }
        let regions = [
            RegionCapability(region: .kanto, features: [.viaStations: .available, .firstLastTrain: .available]),
            RegionCapability(region: .kansai, features: [.viaStations: .unavailable, .firstLastTrain: .unavailable]),
        ]
        return CapabilitySnapshot(lines: lines, regions: regions, fetchedAt: now)
    }

    /// 運行情報（#14 の unknown を含む）
    public static func statuses(region: Region, now: Date, capabilities: CapabilitySnapshot) -> [OperationStatus] {
        let asOf = Date(timeIntervalSince1970: (now.timeIntervalSince1970 / 60).rounded(.down) * 60)
        return catalog.lines.values
            .filter { $0.region == region && $0.id != MockID.noSymbol }
            .sorted { $0.id < $1.id }
            .map { line in
                guard capabilities.isSupported(.operationAlerts, lineId: line.id) else {
                    return OperationStatus(lineId: line.id, status: .unknown, summary: "運行情報を確認できません", asOf: asOf)
                }
                if let disruption = disruptions[line.id] {
                    return OperationStatus(
                        lineId: line.id, status: disruption.status, summary: disruption.summary, cause: disruption.cause,
                        occurredAt: asOf.addingTimeInterval(-25 * 60), outlook: disruption.outlook,
                        hasTransferTransport: disruption.transfer, asOf: asOf
                    )
                }
                return OperationStatus(lineId: line.id, status: .normal, summary: "平常どおり運転しています", asOf: asOf)
            }
    }

    struct Disruption {
        var status: OperationStatusKind
        var summary: String
        var cause: String
        var outlook: String?
        var transfer: Bool?
        var delayMinutes: Int?
    }

    static let disruptions: [String: Disruption] = [
        MockID.yamanote: Disruption(
            status: .delayed, summary: "信号確認の影響で、一部列車に遅れが出ています", cause: "信号確認",
            outlook: "まもなく平常どおりの運転に戻る見込み", transfer: false, delayMinutes: 3
        ),
        MockID.ginza: Disruption(
            status: .partial, summary: "渋谷〜表参道間で折り返し運転を行っています", cause: "車両点検",
            outlook: "10時頃 全線で運転再開見込み", transfer: true, delayMinutes: nil
        ),
        MockID.oedo: Disruption(
            status: .suspended, summary: "車両点検の影響で、全線で運転を見合わせています", cause: "車両点検",
            outlook: "9時30分頃 運転再開見込み", transfer: true, delayMinutes: nil
        ),
    ]

    public static let attributions: [Attribution] = [
        Attribution(provider: "mock", displayText: "データ提供: サンプルデータ（モック）"),
        Attribution(provider: "odpt", displayText: "データ提供: 公共交通オープンデータセンター（モック表示）", licenseUrl: "https://developer.odpt.org/terms"),
    ]
}
