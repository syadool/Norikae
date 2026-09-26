import DesignSystem
import Domain
import SwiftUI

/// 時刻表タブ（駅 → 路線 → 方面 → 時刻表、FR-TT-01）
struct TimetableTab: View {
    @Environment(AppDependencies.self) private var dependencies

    var body: some View {
        @Bindable var router = dependencies.router
        NavigationStack(path: $router.timetablePath) {
            TimetableHomeView(dependencies: dependencies)
                .navigationDestination(for: TimetableDestination.self) { destination in
                    switch destination {
                    case .directions(let stationId):
                        DirectionListView(stationId: stationId, dependencies: dependencies)
                    case .timetable(let target):
                        TimetableView(target: target, dependencies: dependencies)
                    case .stopList(let request):
                        StopListView(request: request, dependencies: dependencies)
                    }
                }
        }
    }
}

/// 時刻表の最初の画面：駅を選ぶ・お気に入りの時刻表
struct TimetableHomeView: View {
    let dependencies: AppDependencies
    @State private var isPicking = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Button {
                    isPicking = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").foregroundStyle(NKColor.textTertiary)
                        Text("駅を選ぶ", bundle: .module).foregroundStyle(NKColor.textTertiary)
                        Spacer()
                    }
                    .font(.body)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 48)
                    .nkCard(radius: NKRadius.lg)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("timetableStationButton")
                favoritesSection
            }
            .padding(.vertical, 12)
            .nkScreen()
        }
        .nkScreenBackground()
        .navigationTitle(String(localized: "時刻表", bundle: .module))
        .sheet(isPresented: $isPicking) {
            StationPickerView(title: String(localized: "駅を選ぶ", bundle: .module), dependencies: dependencies) { station in
                dependencies.router.timetablePath.append(.directions(stationId: station.id))
            }
        }
    }

    /// お気に入りの時刻表（すぐに開ける、FR-TT-07）
    @ViewBuilder
    private var favoritesSection: some View {
        let items: [FavoriteTimetableItem] = dependencies.userData.favorites().compactMap { entry in
            if case .timetable(let timetable) = entry.item { return FavoriteTimetableItem(id: entry.id, timetable: timetable) }
            return nil
        }
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(String(localized: "お気に入りの時刻表", bundle: .module))
            if items.isEmpty {
                EmptyStateView(
                    systemImage: "tablecells",
                    title: String(localized: "よく見る時刻表をお気に入りに登録すると、ここからすぐに開けます", bundle: .module),
                    actionTitle: String(localized: "駅を選ぶ", bundle: .module),
                    action: { isPicking = true }
                )
                .nkCard()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        Button {
                            dependencies.router.timetablePath.append(.timetable(item.timetable))
                        } label: {
                            NKRow {
                                LineSymbolChip(LineAppearance(line: dependencies.catalog.line(item.timetable.lineId), fallbackID: item.timetable.lineId), size: .detail)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(dependencies.catalog.station(item.timetable.stationId)?.name ?? String(localized: "この駅は利用できません", bundle: .module))
                                        .font(.subheadline.weight(.bold))
                                        .foregroundStyle(NKColor.textPrimary)
                                    Text(item.timetable.directionName)
                                        .font(.caption)
                                        .foregroundStyle(NKColor.textSecondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        if index < items.count - 1 { NKDivider() }
                    }
                }
                .nkCard()
            }
        }
    }

    private struct FavoriteTimetableItem: Identifiable {
        var id: UUID
        var timetable: FavoriteTimetable
    }
}

// MARK: - 路線・方面の選択

@MainActor
@Observable
final class DirectionListModel {
    let stationId: String
    private(set) var phase: LoadPhase = .loading
    private(set) var directions: [LineDirection] = []
    private let dependencies: AppDependencies

    init(stationId: String, dependencies: AppDependencies) {
        self.stationId = stationId
        self.dependencies = dependencies
    }

    var station: Station? { dependencies.catalog.station(stationId) }

    struct LineGroup: Identifiable {
        var line: Line?
        var lineId: String
        var directions: [LineDirection]
        var id: String { lineId }
    }

    /// 路線ごとにまとめた方面（駅の路線の順）
    var groups: [LineGroup] {
        let order = station?.lineIds ?? []
        let grouped = Dictionary(grouping: directions, by: \.lineId)
        let lineIds = order.filter { grouped[$0] != nil } + grouped.keys.filter { !order.contains($0) }.sorted()
        return lineIds.map { LineGroup(line: dependencies.catalog.line($0), lineId: $0, directions: grouped[$0] ?? []) }
    }

    func isSupported(lineId: String) -> Bool {
        dependencies.capabilities.snapshot.isSupported(.timetable, lineId: lineId)
    }

    func load() async {
        phase = .loading
        do {
            directions = try await dependencies.timetables.directions(stationID: stationId)
            phase = directions.isEmpty ? .empty : .loaded
        } catch {
            phase = .failed(AppError.wrap(error).presentation)
        }
    }
}

struct DirectionListView: View {
    private let dependencies: AppDependencies
    @State private var model: DirectionListModel

    init(stationId: String, dependencies: AppDependencies) {
        self.dependencies = dependencies
        _model = State(initialValue: DirectionListModel(stationId: stationId, dependencies: dependencies))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                switch model.phase {
                case .loading:
                    ListSkeleton(rows: 4)
                case .empty:
                    EmptyStateView(systemImage: "tablecells", title: String(localized: "この駅の時刻表はありません", bundle: .module))
                        .nkCard()
                case .failed(let error):
                    ErrorStateView(message: error.message, retryable: error.retryable) { Task { await model.load() } }
                case .loaded:
                    ForEach(model.groups) { group in
                        lineGroup(line: group.line, lineId: group.lineId, directions: group.directions)
                    }
                }
            }
            .padding(.vertical, 12)
            .nkScreen()
        }
        .nkScreenBackground()
        .navigationTitle(model.station?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    dependencies.router.startSearch(from: model.stationId)
                } label: {
                    Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                }
                .accessibilityLabel(Text("この駅から経路を検索", bundle: .module))
            }
        }
        .task { if model.directions.isEmpty { await model.load() } }
    }

    private func lineGroup(line: Line?, lineId: String, directions: [LineDirection]) -> some View {
        let supported = model.isSupported(lineId: lineId)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                LineSymbolChip(LineAppearance(line: line, fallbackID: lineId), size: .detail)
                Text(line?.name ?? lineId).font(.subheadline.weight(.bold))
                Spacer()
                if !supported { UnsupportedBadge(.timetable) }
            }
            .padding(.bottom, 8)
            .padding(.horizontal, 4)
            VStack(spacing: 0) {
                ForEach(Array(directions.enumerated()), id: \.element.id) { index, direction in
                    Button {
                        dependencies.router.timetablePath.append(.timetable(FavoriteTimetable(
                            stationId: model.stationId, lineId: lineId, directionId: direction.directionId, directionName: direction.directionName
                        )))
                    } label: {
                        NKRow(showsChevron: supported) {
                            Text(direction.directionName)
                                .font(.subheadline)
                                .foregroundStyle(supported ? NKColor.textPrimary : NKColor.textTertiary)
                        }
                    }
                    .buttonStyle(.plain)
                    // 時刻表非対応の路線は、選べない状態で出す（FR-TT-01）
                    .disabled(!supported)
                    if index < directions.count - 1 { NKDivider() }
                }
            }
            .nkCard()
        }
    }
}

// MARK: - 時刻表

@MainActor
@Observable
final class TimetableModel {
    let target: FavoriteTimetable
    var dayType: DayType
    private(set) var phase: LoadPhase = .loading
    private(set) var result: TimetableResult?
    private(set) var cachedAt: Date?
    private let dependencies: AppDependencies
    /// 最後に始めた読み込みの番号。曜日を素早く切り替えたとき、古い応答を捨てる
    @ObservationIgnored private var loadGeneration = 0

    init(target: FavoriteTimetable, dependencies: AppDependencies, now: Date = Date()) {
        self.target = target
        self.dependencies = dependencies
        // 初期表示は今日の曜日区分（運行日で判定、FR-TT-02）
        dayType = DayType(serviceDate: .operatingDay(containing: now))
    }

    var catalog: Catalog { dependencies.catalog }
    var isSupported: Bool { dependencies.capabilities.snapshot.isSupported(.timetable, lineId: target.lineId) }
    var supportsStopList: Bool { dependencies.capabilities.snapshot.isSupported(.stopList, lineId: target.lineId) }
    var isToday: Bool { dayType == DayType(serviceDate: .operatingDay(containing: Date())) }

    struct HourGroup: Identifiable {
        var hour: Int
        var entries: [TimetableEntry]
        var id: Int { hour }
    }

    /// 時ごとにまとめた発車
    var hours: [HourGroup] {
        guard let entries = result?.timetable.departures else { return [] }
        let grouped = Dictionary(grouping: entries) { entry in
            // 運行日の 0 時からの時間。深夜 0 時台は 24 時台として並べる
            let start = ServiceDate.operatingDay(containing: entry.departureTime).startDate ?? entry.departureTime
            return Int(entry.departureTime.timeIntervalSince(start) / 3600)
        }
        return grouped.keys.sorted().map { HourGroup(hour: $0, entries: grouped[$0]?.sorted { $0.departureTime < $1.departureTime } ?? []) }
    }

    /// 今の時刻の次の列車（自動スクロール先、FR-TT-05）
    var nextEntryID: String? {
        guard isToday else { return nil }
        let now = Date()
        return result?.timetable.departures.sorted { $0.departureTime < $1.departureTime }.first { $0.departureTime >= now }?.id
    }

    var notices: [DataNoticeBanner.Kind] {
        if let cachedAt { return [.cached(asOf: cachedAt)] }
        if let meta = result?.meta, meta.isStale { return [.stale(asOf: meta.asOf)] }
        if let meta = result?.meta, meta.partialResult { return [.partial] }
        return []
    }

    // MARK: お気に入り（FR-TT-07）

    var isFavorite: Bool { dependencies.userData.favorite(matching: .timetable(target)) != nil }

    func toggleFavorite() {
        if let entry = dependencies.userData.favorite(matching: .timetable(target)) {
            dependencies.userData.removeFavorite(id: entry.id)
        } else {
            dependencies.userData.addFavorite(.timetable(target))
        }
    }

    func load() async {
        guard isSupported else { return }
        loadGeneration += 1
        let generation = loadGeneration
        let dayType = dayType
        phase = .loading
        if !dependencies.network.isOnline {
            await showCacheOrFail(.offline, dayType: dayType, generation: generation)
            return
        }
        do {
            let result = try await dependencies.timetables.timetable(
                stationID: target.stationId, lineID: target.lineId, directionID: target.directionId, dayType: dayType
            )
            guard generation == loadGeneration else { return }
            self.result = result
            cachedAt = nil
            phase = result.timetable.departures.isEmpty ? .empty : .loaded
            await dependencies.timetableCache.save(result)
        } catch {
            guard generation == loadGeneration else { return }
            let appError = AppError.wrap(error)
            if appError == .offline || appError == .network {
                await showCacheOrFail(appError, dayType: dayType, generation: generation)
            } else {
                phase = .failed(appError.presentation)
            }
        }
    }

    private func showCacheOrFail(_ error: AppError, dayType: DayType, generation: Int) async {
        let cached = await dependencies.timetableCache.load(
            stationID: target.stationId, lineID: target.lineId, directionID: target.directionId, dayType: dayType
        )
        guard generation == loadGeneration else { return }
        if let cached {
            result = cached.result
            cachedAt = cached.savedAt
            phase = .loaded
        } else {
            phase = .failed(error.presentation)
        }
    }

    func stopListRequest(for entry: TimetableEntry) -> StopListRequest {
        StopListRequest(
            trainRunId: entry.trainRunId, serviceDate: .operatingDay(containing: entry.departureTime),
            lineId: target.lineId, fromStationId: target.stationId, toStationId: nil
        )
    }
}

struct TimetableView: View {
    private let dependencies: AppDependencies
    @State private var model: TimetableModel

    init(target: FavoriteTimetable, dependencies: AppDependencies) {
        self.dependencies = dependencies
        _model = State(initialValue: TimetableModel(target: target, dependencies: dependencies))
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: NKSpacing.cardGap) {
                    header
                    if !model.isSupported {
                        UnsupportedNotice(.timetable)
                            .padding(NKSpacing.cardPadding)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .nkCard()
                    } else {
                        NKSegmentedPicker(selection: $model.dayType, options: [
                            NKSegmentedPicker<DayType>.Option(.weekday, String(localized: "平日", bundle: .module)),
                            NKSegmentedPicker<DayType>.Option(.saturday, String(localized: "土曜", bundle: .module)),
                            NKSegmentedPicker<DayType>.Option(.holiday, String(localized: "休日", bundle: .module)),
                        ])
                        ForEach(model.notices, id: \.self) { DataNoticeBanner($0) }
                        legend
                        switch model.phase {
                        case .loading:
                            ListSkeleton(rows: 6)
                        case .empty:
                            EmptyStateView(systemImage: "tablecells", title: String(localized: "この曜日の列車はありません", bundle: .module))
                                .nkCard()
                        case .failed(let error):
                            ErrorStateView(message: error.message, retryable: error.retryable) { Task { await model.load() } }
                        case .loaded:
                            table
                            AttributionFooter(model.result?.meta.attributions ?? [])
                        }
                    }
                }
                .padding(.vertical, 12)
                .nkScreen()
            }
            .onChange(of: model.phase) {
                // 今の時刻の位置まで自動でスクロールする（FR-TT-05）
                guard model.phase == .loaded, let id = model.nextEntryID else { return }
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(100))
                    withAnimation { proxy.scrollTo(id, anchor: .center) }
                }
            }
        }
        .nkScreenBackground()
        .navigationTitle(String(localized: "時刻表", bundle: .module))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    model.toggleFavorite()
                } label: {
                    Image(systemName: model.isFavorite ? "star.fill" : "star")
                }
                .accessibilityLabel(model.isFavorite ? Text("お気に入りから外す", bundle: .module) : Text("お気に入りに追加", bundle: .module))
            }
        }
        .task { if model.result == nil { await model.load() } }
        // 平日 / 土曜 / 休日を切り替えたら取り直す（FR-TT-02）
        .onChange(of: model.dayType) { Task { await model.load() } }
    }

    private var header: some View {
        HStack(spacing: 8) {
            LineSymbolChip(LineAppearance(line: model.catalog.line(model.target.lineId), fallbackID: model.target.lineId), size: .detail)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.catalog.station(model.target.stationId)?.name ?? "")
                    .font(.headline)
                Text("\(model.catalog.line(model.target.lineId)?.name ?? "") \(model.target.directionName)", bundle: .module)
                    .font(.caption)
                    .foregroundStyle(NKColor.textSecondary)
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
    }

    /// 種別の略称・色と、当駅始発の印の説明（FR-TT-03、FR-TT-04）
    private var legend: some View {
        let types = Set((model.result?.timetable.departures ?? []).map(\.trainTypeId)).sorted()
        return HStack(spacing: 10) {
            ForEach(types, id: \.self) { id in
                if let type = model.catalog.trainType(id) {
                    HStack(spacing: 3) {
                        Text(type.shortName).fontWeight(.bold).foregroundStyle(trainTypeColor(type))
                        Text(type.name).foregroundStyle(NKColor.textSecondary)
                    }
                }
            }
            HStack(spacing: 3) {
                OriginMark()
                Text("当駅始発", bundle: .module).foregroundStyle(NKColor.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .font(.caption2)
    }

    private var table: some View {
        VStack(spacing: 0) {
            ForEach(Array(model.hours.enumerated()), id: \.element.id) { index, group in
                HStack(alignment: .top, spacing: 0) {
                    Text("\(group.hour)")
                        .font(.nkNumeric(.headline, weight: .bold))
                        .foregroundStyle(NKColor.textPrimary)
                        .frame(width: 44)
                        .padding(.vertical, 10)
                        .background(NKColor.fillSubtle)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 50), spacing: 4, alignment: .leading)], alignment: .leading, spacing: 6) {
                        ForEach(group.entries) { entry in
                            entryCell(entry)
                                .id(entry.id)
                        }
                    }
                    .padding(8)
                }
                if index < model.hours.count - 1 { NKDivider(leading: 0) }
            }
        }
        .nkCard()
        .clipShape(RoundedRectangle(cornerRadius: NKRadius.xl, style: .continuous))
    }

    /// 1 本分：種別の略称（色）と行き先の頭文字、分、当駅始発の印。タップで停車駅一覧（FR-TT-06）
    private func entryCell(_ entry: TimetableEntry) -> some View {
        let type = model.catalog.trainType(entry.trainTypeId)
        let minute = JapanCalendar.calendar.component(.minute, from: entry.departureTime)
        let isNext = entry.id == model.nextEntryID
        return Button {
            dependencies.router.timetablePath.append(.stopList(model.stopListRequest(for: entry)))
        } label: {
            VStack(spacing: 1) {
                HStack(spacing: 1) {
                    Text(type?.shortName ?? "").foregroundStyle(trainTypeColor(type))
                    Text(String(entry.destinationName.prefix(1))).foregroundStyle(NKColor.textSecondary)
                }
                .font(.caption2.weight(.bold))
                HStack(spacing: 2) {
                    if entry.isOriginStation { OriginMark() }
                    Text(String(format: "%02d", minute))
                        .font(.nkNumeric(.body, weight: .semibold))
                        .foregroundStyle(NKColor.textPrimary)
                }
            }
            .frame(minWidth: 44, minHeight: 44)
            .background(isNext ? NKColor.fillPill : .clear, in: RoundedRectangle(cornerRadius: NKRadius.sm, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!model.supportsStopList)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityText(entry, type: type)))
    }

    private func accessibilityText(_ entry: TimetableEntry, type: TrainType?) -> String {
        var parts = [NKFormat.spokenTime(entry.departureTime), type?.name ?? "", entry.destinationName]
        if entry.isOriginStation { parts.append(String(localized: "当駅始発", bundle: .module)) }
        if let platform = entry.platform { parts.append(String(localized: "\(platform)番線", bundle: .module)) }
        return parts.filter { !$0.isEmpty }.joined(separator: "、")
    }
}

/// 当駅始発の印
struct OriginMark: View {
    var body: some View {
        Circle()
            .strokeBorder(NKColor.accent, lineWidth: 1.5)
            .frame(width: 7, height: 7)
            .accessibilityHidden(true)
    }
}
