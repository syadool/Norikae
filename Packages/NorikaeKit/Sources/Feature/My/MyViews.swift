import DesignSystem
import Domain
import SwiftUI

/// マイタブ（FR-MY）
struct MyTab: View {
    @Environment(AppDependencies.self) private var dependencies

    var body: some View {
        @Bindable var router = dependencies.router
        NavigationStack(path: $router.myPath) {
            MyHomeView(dependencies: dependencies)
                .navigationDestination(for: MyDestination.self) { destination in
                    switch destination {
                    case .favorites: FavoritesView(dependencies: dependencies)
                    case .history: HistoryView(dependencies: dependencies)
                    case .myLines: MyLinesView(dependencies: dependencies)
                    case .settings: SettingsView(dependencies: dependencies)
                    case .attributions: AttributionsView(dependencies: dependencies)
                    }
                }
        }
    }
}

struct MyHomeView: View {
    let dependencies: AppDependencies

    var body: some View {
        List {
            Section {
                link(.favorites, title: String(localized: "お気に入り", bundle: .module), icon: "star", count: dependencies.userData.favorites().count)
                link(.history, title: String(localized: "検索履歴", bundle: .module), icon: "clock.arrow.circlepath", count: dependencies.userData.history().count)
                link(.myLines, title: String(localized: "マイ路線", bundle: .module), icon: "tram", count: dependencies.userData.myLines().count)
            }
            Section {
                link(.settings, title: String(localized: "設定", bundle: .module), icon: "gearshape", count: nil)
                link(.attributions, title: String(localized: "データの提供元", bundle: .module), icon: "doc.text", count: nil)
            }
        }
        .scrollContentBackground(.hidden)
        .nkScreenBackground()
        .navigationTitle(String(localized: "マイ", bundle: .module))
    }

    private func link(_ destination: MyDestination, title: String, icon: String, count: Int?) -> some View {
        NavigationLink(value: destination) {
            HStack {
                Label(title, systemImage: icon)
                Spacer()
                if let count, count > 0 {
                    Text("\(count)").foregroundStyle(NKColor.textTertiary)
                }
            }
        }
    }
}

// MARK: - お気に入り（一覧・並べ替え・削除、FR-MY-01）

struct FavoritesView: View {
    let dependencies: AppDependencies

    var body: some View {
        let favorites = dependencies.userData.favorites()
        Group {
            if favorites.isEmpty {
                EmptyStateView(
                    systemImage: "star",
                    title: String(localized: "お気に入りはまだありません", bundle: .module),
                    message: String(localized: "経路詳細・時刻表・駅選択の星のボタンで登録できます", bundle: .module),
                    actionTitle: String(localized: "駅を検索する", bundle: .module),
                    action: { dependencies.router.selectedTab = .search }
                )
            } else {
                List {
                    ForEach(favorites) { entry in
                        Button {
                            open(entry.item)
                        } label: {
                            FavoriteRow(item: entry.item, dependencies: dependencies)
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete { offsets in
                        for index in offsets { dependencies.userData.removeFavorite(id: favorites[index].id) }
                    }
                    .onMove { source, destination in
                        dependencies.userData.moveFavorites(from: source, to: destination)
                    }
                }
                .scrollContentBackground(.hidden)
                .toolbar { EditButton() }
            }
        }
        .nkScreenBackground()
        .navigationTitle(String(localized: "お気に入り", bundle: .module))
    }

    private func open(_ item: FavoriteItem) {
        switch item {
        case .route(let route):
            // 開くときに再検索する（FR-DTL-03）
            dependencies.router.openSearch(route.query.refreshed(now: Date()), preferred: route.signature)
        case .station(let id):
            guard dependencies.isStationAvailable(id) else { return }
            dependencies.router.startSearch(from: id)
        case .timetable(let timetable):
            guard dependencies.isStationAvailable(timetable.stationId) else { return }
            dependencies.router.openTimetable(timetable)
        }
    }
}

struct FavoriteRow: View {
    let item: FavoriteItem
    let dependencies: AppDependencies

    private var catalog: Catalog { dependencies.catalog }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(NKColor.accent)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(isAvailable ? NKColor.textPrimary : NKColor.textTertiary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(NKColor.textSecondary)
                // 駅が統合・廃止されて移行先がない（FR-SRC-09）
                if !isAvailable {
                    Text("この駅は利用できません", bundle: .module)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(NKColor.delayText)
                }
            }
            Spacer()
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var isAvailable: Bool {
        item.stationIds.allSatisfy(dependencies.isStationAvailable)
    }

    private var icon: String {
        switch item {
        case .route: "point.topleft.down.to.point.bottomright.curvepath"
        case .station: "mappin.circle"
        case .timetable: "tablecells"
        }
    }

    private var title: String {
        switch item {
        case .route(let route):
            QueryText.title(route.query, catalog: catalog)
        case .station(let id):
            catalog.station(id)?.name ?? String(localized: "不明な駅", bundle: .module)
        case .timetable(let timetable):
            catalog.station(timetable.stationId)?.name ?? String(localized: "不明な駅", bundle: .module)
        }
    }

    private var subtitle: String {
        switch item {
        case .route(let route):
            String(localized: "経路 · \(route.signature.segments.compactMap { catalog.line($0.lineId)?.name }.joined(separator: " → "))", bundle: .module)
        case .station:
            String(localized: "駅", bundle: .module)
        case .timetable(let timetable):
            String(localized: "時刻表 · \(catalog.line(timetable.lineId)?.name ?? "") \(timetable.directionName)", bundle: .module)
        }
    }
}

// MARK: - 検索履歴（1 件ずつ・全件の削除、FR-MY-02）

struct HistoryView: View {
    let dependencies: AppDependencies
    @State private var isConfirmingClear = false

    var body: some View {
        let history = dependencies.userData.history()
        Group {
            if history.isEmpty {
                EmptyStateView(
                    systemImage: "clock.arrow.circlepath",
                    title: String(localized: "検索の履歴はまだありません", bundle: .module),
                    actionTitle: String(localized: "駅を検索する", bundle: .module),
                    action: { dependencies.router.selectedTab = .search }
                )
            } else {
                List {
                    ForEach(history) { entry in
                        Button {
                            dependencies.router.openSearch(entry.query.refreshed(now: Date()))
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(QueryText.title(entry.query, catalog: dependencies.catalog))
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(NKColor.textPrimary)
                                Text(QueryText.when(entry.query))
                                    .font(.caption)
                                    .foregroundStyle(NKColor.textSecondary)
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete { offsets in
                        for index in offsets { dependencies.userData.removeHistory(id: history[index].id) }
                    }
                }
                .scrollContentBackground(.hidden)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button(String(localized: "すべて削除", bundle: .module), role: .destructive) {
                            isConfirmingClear = true
                        }
                    }
                }
            }
        }
        .nkScreenBackground()
        .navigationTitle(String(localized: "検索履歴", bundle: .module))
        .confirmationDialog(String(localized: "検索履歴をすべて削除しますか？", bundle: .module), isPresented: $isConfirmingClear, titleVisibility: .visible) {
            Button(String(localized: "すべて削除", bundle: .module), role: .destructive) {
                dependencies.userData.clearHistory()
            }
        }
    }
}

// MARK: - マイ路線（登録と削除、FR-MY-03）

struct MyLinesView: View {
    let dependencies: AppDependencies
    @State private var isAdding = false

    var body: some View {
        let entries = dependencies.userData.myLines()
        Group {
            if entries.isEmpty {
                EmptyStateView(
                    systemImage: "tram",
                    title: String(localized: "マイ路線はまだありません", bundle: .module),
                    message: String(localized: "登録した路線の運行状況を、運行情報の一番上に表示します", bundle: .module),
                    actionTitle: String(localized: "路線を追加", bundle: .module),
                    action: { isAdding = true }
                )
            } else {
                List {
                    ForEach(entries) { entry in
                        let line = dependencies.catalog.line(entry.lineId)
                        HStack(spacing: 10) {
                            LineSymbolChip(LineAppearance(line: line, fallbackID: entry.lineId), size: .status)
                            Text(line?.name ?? String(localized: "この路線は利用できません", bundle: .module))
                                .font(.subheadline.weight(.bold))
                            Spacer()
                            // 運行情報に対応していない路線も、そのことを示す（FR-STS-06）
                            if !dependencies.capabilities.snapshot.isSupported(.operationAlerts, lineId: entry.lineId) {
                                UnsupportedBadge(.operationAlerts)
                            }
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets { dependencies.userData.removeMyLine(id: entries[index].id) }
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
        .nkScreenBackground()
        .navigationTitle(String(localized: "マイ路線", bundle: .module))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isAdding = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(Text("路線を追加", bundle: .module))
            }
        }
        .sheet(isPresented: $isAdding) {
            LinePickerView(dependencies: dependencies)
        }
    }
}

/// マイ路線に追加する路線を選ぶ（地域・鉄道会社ごと）
struct LinePickerView: View {
    let dependencies: AppDependencies
    @Environment(\.dismiss) private var dismiss
    @State private var region: Region

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
        _region = State(initialValue: dependencies.settings.preferredRegion)
    }

    var body: some View {
        let lines = dependencies.catalog.lines.values.filter { $0.region == region }
        let grouped = Dictionary(grouping: lines, by: \.operatorId)
        let registered = Set(dependencies.userData.myLines().map(\.lineId))
        NavigationStack {
            List {
                Section {
                    Picker(String(localized: "地域", bundle: .module), selection: $region) {
                        ForEach(Region.allCases, id: \.self) { Text(QueryText.regionName($0)).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                ForEach(grouped.keys.sorted(), id: \.self) { operatorID in
                    Section(dependencies.catalog.operator(operatorID)?.name ?? operatorID) {
                        ForEach((grouped[operatorID] ?? []).sorted { $0.name < $1.name }) { line in
                            Button {
                                if let entry = dependencies.userData.myLines().first(where: { $0.lineId == line.id }) {
                                    dependencies.userData.removeMyLine(id: entry.id)
                                } else {
                                    dependencies.userData.addMyLine(lineId: line.id)
                                }
                            } label: {
                                HStack(spacing: 10) {
                                    LineSymbolChip(LineAppearance(line: line, fallbackID: line.id), size: .status)
                                    Text(line.name).foregroundStyle(NKColor.textPrimary)
                                    Spacer()
                                    if registered.contains(line.id) {
                                        Image(systemName: "checkmark").foregroundStyle(NKColor.accent)
                                    }
                                }
                            }
                            .accessibilityAddTraits(registered.contains(line.id) ? .isSelected : [])
                        }
                    }
                }
            }
            .navigationTitle(String(localized: "路線を追加", bundle: .module))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "完了", bundle: .module)) { dismiss() }
                }
            }
        }
    }
}

// MARK: - 設定（FR-MY-04〜07）

struct SettingsView: View {
    @Bindable var settings: AppSettings
    let dependencies: AppDependencies

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
        settings = dependencies.settings
    }

    var body: some View {
        Form {
            Section(String(localized: "検索条件の初期値", bundle: .module)) {
                Picker(String(localized: "運賃", bundle: .module), selection: $settings.fareKind) {
                    ForEach(FareKind.allCases, id: \.self) { Text(NKFormat.fareKindLabel($0)).tag($0) }
                }
                Toggle(String(localized: "新幹線を使う", bundle: .module), isOn: $settings.useShinkansen)
                Toggle(String(localized: "有料特急を使う", bundle: .module), isOn: $settings.usePaidExpress)
                Picker(String(localized: "並び替え", bundle: .module), selection: $settings.sortOrder) {
                    ForEach(RouteSortOrder.allCases, id: \.self) { Text(QueryText.sortName($0)).tag($0) }
                }
            }
            Section {
                Picker(String(localized: "余裕の時間", bundle: .module), selection: $settings.reminderMargin) {
                    ForEach(ReminderMargin.allCases, id: \.self) { margin in
                        Text("\(margin.rawValue)分", bundle: .module).tag(margin)
                    }
                }
                Picker(String(localized: "歩く速さ", bundle: .module), selection: $settings.walkingSpeed) {
                    ForEach(WalkingSpeed.allCases, id: \.self) { speed in
                        Text(Self.walkingSpeedName(speed)).tag(speed)
                    }
                }
            } header: {
                Text("出発リマインド", bundle: .module)
            } footer: {
                Text("案内を開始した経路について、「発車時刻 − 歩く時間 − 余裕の時間」に通知します。", bundle: .module)
            }
            Section {
                Toggle(String(localized: "iCloud 同期", bundle: .module), isOn: $settings.iCloudSync)
            } footer: {
                if settings.needsRestartForSync {
                    Text("変更はアプリを再起動したあとに反映されます。", bundle: .module)
                } else {
                    Text("お気に入り・検索履歴・マイ路線を、同じ Apple アカウントの端末と同期します。", bundle: .module)
                }
            }
            Section(String(localized: "主に使う地域", bundle: .module)) {
                Picker(String(localized: "地域", bundle: .module), selection: $settings.selectedRegion) {
                    ForEach(Region.allCases, id: \.self) { Text(QueryText.regionName($0)).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            Section {
                NavigationLink(value: MyDestination.attributions) {
                    Text("データの提供元", bundle: .module)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .nkScreenBackground()
        .navigationTitle(String(localized: "設定", bundle: .module))
    }

    static func walkingSpeedName(_ speed: WalkingSpeed) -> String {
        switch speed {
        case .slow: String(localized: "ゆっくり", bundle: .module)
        case .normal: String(localized: "普通", bundle: .module)
        case .fast: String(localized: "速い", bundle: .module)
        }
    }
}

// MARK: - データの提供元（FR-MY-08）

struct AttributionsView: View {
    let dependencies: AppDependencies
    @State private var phase: LoadPhase = .loading
    @State private var attributions: [Attribution] = []

    var body: some View {
        List {
            switch phase {
            case .loading:
                ListSkeleton(rows: 3)
                    .listRowBackground(Color.clear)
            case .failed(let error):
                ErrorStateView(message: error.message, retryable: error.retryable) { Task { await load() } }
                    .listRowBackground(Color.clear)
            case .empty:
                Text("表示する提供元はありません", bundle: .module)
            case .loaded:
                ForEach(attributions, id: \.self) { attribution in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(attribution.displayText)
                            .font(.subheadline)
                        if let urlString = attribution.licenseUrl, let url = URL(string: urlString) {
                            Link(destination: url) {
                                Text("ライセンス", bundle: .module).font(.footnote)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .nkScreenBackground()
        .navigationTitle(String(localized: "データの提供元", bundle: .module))
        .task { await load() }
    }

    private func load() async {
        phase = .loading
        do {
            attributions = try await dependencies.attributions.attributions()
            phase = attributions.isEmpty ? .empty : .loaded
        } catch {
            phase = .failed(AppError.wrap(error).presentation)
        }
    }
}
