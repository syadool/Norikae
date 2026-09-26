import DesignSystem
import Domain
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// 画面の読み込み状態
enum LoadPhase: Equatable {
    case loading
    case loaded
    case empty
    case failed(ErrorPresentation)
}

/// 駅の表示（同じ名前の駅は、都道府県名と路線名を併記して区別する、FR-SRC-04）
struct StationLabel: View {
    let station: Station
    let catalog: Catalog
    /// 同じ名前の駅がある場合だけ補足を出す
    var showsDetail = true

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(station.name)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(NKColor.textPrimary)
            if showsDetail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(NKColor.textSecondary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        let lines = station.lineIds.compactMap { catalog.line($0)?.name }.prefix(4).joined(separator: "・")
        return "\(station.prefecture) · \(lines)"
    }
}

/// 経路の条件の要約（「9/25(金) 8:02 出発」「終電」など）
enum QueryText {
    static func title(_ query: RouteSearchQuery, catalog: Catalog) -> String {
        let from = catalog.station(query.fromStationId)?.name ?? String(localized: "不明な駅", bundle: .module)
        let to = catalog.station(query.toStationId)?.name ?? String(localized: "不明な駅", bundle: .module)
        return "\(from) → \(to)"
    }

    static func when(_ query: RouteSearchQuery, includesDate: Bool = true) -> String {
        let date = includesDate ? NKFormat.shortDate(query.dateTime) + " " : ""
        switch query.searchType {
        case .departure:
            return String(localized: "\(date)\(NKFormat.time(query.dateTime)) 出発", bundle: .module)
        case .arrival:
            return String(localized: "\(date)\(NKFormat.time(query.dateTime)) 到着", bundle: .module)
        case .firstTrain:
            return String(localized: "\(date)始発", bundle: .module)
        case .lastTrain:
            return String(localized: "\(date)終電", bundle: .module)
        }
    }

    static func searchTypeName(_ type: SearchType) -> String {
        switch type {
        case .departure: String(localized: "出発", bundle: .module)
        case .arrival: String(localized: "到着", bundle: .module)
        case .firstTrain: String(localized: "始発", bundle: .module)
        case .lastTrain: String(localized: "終電", bundle: .module)
        }
    }

    static func sortName(_ order: RouteSortOrder) -> String {
        switch order {
        case .fastest: String(localized: "早い順", bundle: .module)
        case .fewestTransfers: String(localized: "乗換が少ない順", bundle: .module)
        case .cheapest: String(localized: "安い順", bundle: .module)
        }
    }

    static func regionName(_ region: Region) -> String {
        switch region {
        case .kanto: String(localized: "首都圏", bundle: .module)
        case .kansai: String(localized: "関西圏", bundle: .module)
        }
    }
}

/// 権限が拒否されたときの、設定アプリへの導線（frontend.md 7.2）
struct OpenSettingsLink: View {
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(message)
                .font(.footnote)
                .foregroundStyle(NKColor.textSecondary)
            #if canImport(UIKit)
            if let url = URL(string: UIApplication.openSettingsURLString) {
                Link(destination: url) {
                    Text("設定アプリを開く", bundle: .module)
                        .font(.footnote.weight(.semibold))
                }
            }
            #endif
        }
    }
}

/// 読み込み中のリストのスケルトン
struct ListSkeleton: View {
    var rows = 5

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<rows, id: \.self) { index in
                HStack(spacing: 10) {
                    SkeletonBlock(width: 30, height: 20, radius: NKRadius.chip)
                    VStack(alignment: .leading, spacing: 6) {
                        SkeletonBlock(width: 120, height: 12)
                        SkeletonBlock(width: 80, height: 10)
                    }
                    Spacer()
                    SkeletonBlock(width: 60, height: 20, radius: 10)
                }
                .padding(.horizontal, 16)
                .frame(height: 60)
                if index < rows - 1 { NKDivider() }
            }
        }
        .nkCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("読み込んでいます", bundle: .module))
    }
}

extension View {
    /// 画面の共通の見た目（地の色、左右の余白）
    func nkScreen() -> some View {
        self
            .padding(.horizontal, NKSpacing.screenHorizontal)
            .frame(maxWidth: .infinity, alignment: .top)
    }
}
