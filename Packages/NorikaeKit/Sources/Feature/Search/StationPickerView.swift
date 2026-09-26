import DesignSystem
import Domain
import SwiftUI

/// 駅選択の ViewModel（FR-SRC-02〜06）
@MainActor
@Observable
final class StationPickerModel {
    enum NearbyState: Equatable {
        case idle
        case loading
        case loaded([Station])
        case denied
        case failed
    }

    var text = ""
    private(set) var results: [Station] = []
    private(set) var nearby: NearbyState = .idle

    private let dependencies: AppDependencies

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
    }

    /// 同梱の駅マスタを端末内で検索する（オフラインでも動く）
    func search() async {
        let query = text
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            results = []
            return
        }
        // 入力中の連続した検索をまとめる
        try? await Task.sleep(for: .milliseconds(120))
        guard !Task.isCancelled, query == text else { return }
        results = (try? await dependencies.stations.search(text: query, preferredRegion: dependencies.settings.preferredRegion)) ?? []
    }

    /// 現在地から最寄り駅を探す（FR-SRC-05。位置情報は端末内だけで使う、NFR-03）
    func loadNearby() async {
        nearby = .loading
        do {
            let here = try await dependencies.location.currentLocation()
            nearby = .loaded(try await dependencies.stations.nearest(to: here, limit: 3))
        } catch LocationError.denied {
            nearby = .denied
        } catch {
            nearby = .failed
        }
    }

    /// 履歴とお気に入りから出す候補（FR-SRC-06）
    var suggestions: [Station] {
        var ids: [String] = []
        for entry in dependencies.userData.favorites() {
            if case .station(let id) = entry.item { ids.append(id) }
        }
        for entry in dependencies.userData.favorites() {
            if case .route(let route) = entry.item { ids.append(contentsOf: [route.query.fromStationId, route.query.toStationId]) }
        }
        for entry in dependencies.userData.history().prefix(10) {
            ids.append(contentsOf: [entry.query.fromStationId, entry.query.toStationId])
        }
        var seen = Set<String>()
        return ids.filter { seen.insert($0).inserted }.compactMap { dependencies.catalog.station($0) }.prefix(8).map { $0 }
    }

    func isFavorite(_ station: Station) -> Bool {
        dependencies.userData.favorite(matching: .station(stationId: station.id)) != nil
    }

    func toggleFavorite(_ station: Station) {
        if let entry = dependencies.userData.favorite(matching: .station(stationId: station.id)) {
            dependencies.userData.removeFavorite(id: entry.id)
        } else {
            dependencies.userData.addFavorite(.station(stationId: station.id))
        }
    }
}

/// 駅選択の画面
struct StationPickerView: View {
    let title: String
    let onSelect: (Station) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var model: StationPickerModel
    @FocusState private var isFieldFocused: Bool
    private let dependencies: AppDependencies

    init(title: String, dependencies: AppDependencies, onSelect: @escaping (Station) -> Void) {
        self.title = title
        self.onSelect = onSelect
        self.dependencies = dependencies
        _model = State(initialValue: StationPickerModel(dependencies: dependencies))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: NKSpacing.cardGap) {
                    searchField
                    if model.text.isEmpty {
                        nearbySection
                        if !model.suggestions.isEmpty {
                            stationSection(title: String(localized: "履歴・お気に入り", bundle: .module), stations: model.suggestions)
                        }
                    } else if model.results.isEmpty {
                        EmptyStateView(
                            systemImage: "magnifyingglass",
                            title: String(localized: "駅が見つかりません", bundle: .module),
                            message: String(localized: "漢字またはひらがなで入力してください", bundle: .module)
                        )
                    } else {
                        stationSection(title: String(localized: "候補", bundle: .module), stations: model.results)
                    }
                }
                .padding(.vertical, 12)
                .nkScreen()
            }
            .nkScreenBackground()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "閉じる", bundle: .module)) { dismiss() }
                }
            }
            .task(id: model.text) { await model.search() }
            .onAppear { isFieldFocused = true }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(NKColor.textTertiary)
                .accessibilityHidden(true)
            TextField(String(localized: "駅名（漢字・ひらがな）", bundle: .module), text: $model.text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($isFieldFocused)
                .submitLabel(.search)
                .accessibilityIdentifier("stationSearchField")
            if !model.text.isEmpty {
                Button {
                    model.text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(NKColor.textTertiary)
                }
                .accessibilityLabel(Text("入力を消す", bundle: .module))
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 48)
        .nkCard(radius: NKRadius.lg)
    }

    @ViewBuilder
    private var nearbySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(String(localized: "現在地から", bundle: .module))
            VStack(alignment: .leading, spacing: 0) {
                switch model.nearby {
                case .idle:
                    Button {
                        Task { await model.loadNearby() }
                    } label: {
                        NKRow(showsChevron: false) {
                            Label {
                                Text("最寄り駅を探す", bundle: .module)
                            } icon: {
                                Image(systemName: "location")
                            }
                            .font(.subheadline)
                            .foregroundStyle(NKColor.accent)
                        }
                    }
                    .buttonStyle(.plain)
                case .loading:
                    NKRow(showsChevron: false) {
                        SkeletonBlock(width: 140, height: 14)
                    }
                case .loaded(let stations):
                    ForEach(Array(stations.enumerated()), id: \.element.id) { index, station in
                        stationRow(station)
                        if index < stations.count - 1 { NKDivider() }
                    }
                case .denied:
                    OpenSettingsLink(message: String(localized: "位置情報の利用が許可されていません。最寄り駅を出すには、設定で許可してください。", bundle: .module))
                        .padding(16)
                case .failed:
                    Text("現在地を取得できませんでした", bundle: .module)
                        .font(.footnote)
                        .foregroundStyle(NKColor.textSecondary)
                        .padding(16)
                }
            }
            .nkCard()
        }
    }

    private func stationSection(title: String, stations: [Station]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title)
            VStack(spacing: 0) {
                ForEach(Array(stations.enumerated()), id: \.element.id) { index, station in
                    stationRow(station)
                    if index < stations.count - 1 { NKDivider() }
                }
            }
            .nkCard()
        }
    }

    private func stationRow(_ station: Station) -> some View {
        HStack(spacing: 0) {
            Button {
                onSelect(station)
                dismiss()
            } label: {
                NKRow(showsChevron: false) {
                    StationLabel(station: station, catalog: dependencies.catalog)
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("stationRow-\(station.name)")
            Button {
                model.toggleFavorite(station)
            } label: {
                Image(systemName: model.isFavorite(station) ? "star.fill" : "star")
                    .foregroundStyle(NKColor.accent)
                    .frame(width: NKSpacing.minTapTarget, height: NKSpacing.minTapTarget)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(model.isFavorite(station) ? Text("お気に入りから外す", bundle: .module) : Text("お気に入りに追加", bundle: .module))
            .padding(.trailing, 4)
        }
    }
}
