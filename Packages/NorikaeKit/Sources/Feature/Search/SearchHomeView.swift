import DesignSystem
import Domain
import SwiftUI

/// 経路検索タブ（駅入力 → 検索条件 → 縦比較 → 経路詳細 → 案内開始）
struct SearchTab: View {
    @Environment(AppDependencies.self) private var dependencies

    var body: some View {
        @Bindable var router = dependencies.router
        NavigationStack(path: $router.searchPath) {
            SearchHomeView(dependencies: dependencies)
                .navigationDestination(for: SearchDestination.self) { destination in
                    switch destination {
                    case .results(let query, let preferred, let fareKind):
                        RouteResultsView(query: query, preferred: preferred, fareKind: fareKind, dependencies: dependencies)
                    case .detail(let selection):
                        RouteDetailView(selection: selection, dependencies: dependencies)
                    case .stopList(let request):
                        StopListView(request: request, dependencies: dependencies)
                    case .stationMap(let stationId):
                        StationMapView(stationId: stationId, dependencies: dependencies)
                    }
                }
        }
    }
}

/// 経路検索の最初の画面（design-spec 7.7）
struct SearchHomeView: View {
    private let dependencies: AppDependencies
    @State private var form: SearchFormModel
    @State private var picking: PickerTarget?
    @State private var isEditingConditions = false

    enum PickerTarget: Identifiable {
        case from, to
        var id: Self { self }
    }

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
        _form = State(initialValue: SearchFormModel(settings: dependencies.settings))
    }

    private var catalog: Catalog { dependencies.catalog }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let session = dependencies.guidance.session {
                    ActiveGuidanceCard(session: session) {
                        Task { await dependencies.guidance.end() }
                    }
                }
                stationCard
                conditionCard
                Button {
                    search()
                } label: {
                    Label {
                        Text("この条件で検索", bundle: .module)
                    } icon: {
                        Image(systemName: "magnifyingglass")
                    }
                }
                .buttonStyle(NKPrimaryButtonStyle())
                .disabled(!form.canSearch)
                .accessibilityIdentifier("searchButton")
                historySection
                favoriteSection
            }
            .padding(.vertical, 12)
            .nkScreen()
        }
        .nkScreenBackground()
        .navigationTitle(String(localized: "経路検索", bundle: .module))
        .sheet(item: $picking) { target in
            StationPickerView(
                title: target == .from ? String(localized: "出発駅", bundle: .module) : String(localized: "到着駅", bundle: .module),
                dependencies: dependencies
            ) { station in
                if target == .from { form.from = station } else { form.to = station }
            }
        }
        .sheet(isPresented: $isEditingConditions) {
            ConditionsView(form: form, dependencies: dependencies)
        }
        .onAppear(perform: applyPendingOrigin)
        .onChange(of: dependencies.router.pendingOriginStationId) { applyPendingOrigin() }
    }

    private func search() {
        let region = form.region(default: dependencies.settings.preferredRegion)
        form.removeUnsupported(capabilities: dependencies.capabilities.snapshot, region: region)
        guard let query = form.makeQuery() else { return }
        dependencies.userData.addHistory(query)
        dependencies.router.searchPath.append(.results(query, fareKind: form.fareKind))
    }

    private func applyPendingOrigin() {
        guard let id = dependencies.router.pendingOriginStationId else { return }
        form.from = catalog.station(id)
        dependencies.router.pendingOriginStationId = nil
    }

    // MARK: 出発・到着（行の高さ 60、入れ替えボタン 44×44）

    private var stationCard: some View {
        HStack(spacing: 8) {
            VStack(spacing: 0) {
                stationField(label: String(localized: "出発", bundle: .module), station: form.from, marker: .origin) { picking = .from }
                    .accessibilityIdentifier("fromStationField")
                NKDivider(leading: 44)
                stationField(label: String(localized: "到着", bundle: .module), station: form.to, marker: .destination) { picking = .to }
                    .accessibilityIdentifier("toStationField")
            }
            .overlay(alignment: .leading) {
                // 出発と到着をつなぐ点線
                Path { path in
                    path.move(to: CGPoint(x: 26, y: 38))
                    path.addLine(to: CGPoint(x: 26, y: 84))
                }
                .stroke(NKColor.connectorDotted, style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [1, 4]))
                .accessibilityHidden(true)
            }
            Button {
                withAnimation(.snappy) { form.swap() }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
            }
            .buttonStyle(NKCircleIconButtonStyle())
            .accessibilityLabel(Text("出発駅と到着駅を入れ替える", bundle: .module))
            .padding(.trailing, 12)
        }
        .nkCard()
    }

    private enum Marker { case origin, destination }

    private func stationField(label: String, station: Station?, marker: Marker, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Group {
                    if marker == .origin {
                        Circle().strokeBorder(NKColor.textPrimary, lineWidth: 2.5).frame(width: 14, height: 14)
                    } else {
                        RoundedRectangle(cornerRadius: 3).fill(NKColor.textPrimary).frame(width: 13, height: 13)
                    }
                }
                .frame(width: 20)
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(NKColor.textTertiary)
                    if let station {
                        Text(station.name)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(NKColor.textPrimary)
                    } else {
                        Text(marker == .origin ? String(localized: "出発駅を入力", bundle: .module) : String(localized: "到着駅を入力", bundle: .module))
                            .font(.title3)
                            .foregroundStyle(NKColor.textTertiary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.leading, 16)
            .frame(minHeight: 60)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: 条件（日時／経由駅／条件、各 48）

    private var conditionCard: some View {
        VStack(spacing: 0) {
            conditionRow(icon: "clock", title: String(localized: "日時", bundle: .module), value: whenText)
            NKDivider()
            conditionRow(icon: "mappin", title: String(localized: "経由駅", bundle: .module), value: viaText)
            NKDivider()
            conditionRow(icon: "slider.horizontal.3", title: String(localized: "条件", bundle: .module), value: form.conditionsSummary)
        }
        .nkCard()
    }

    private func conditionRow(icon: String, title: String, value: String) -> some View {
        Button {
            isEditingConditions = true
        } label: {
            NKRow {
                Image(systemName: icon)
                    .foregroundStyle(NKColor.accent)
                    .frame(width: 22)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(NKColor.textSecondary)
                Spacer()
                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(NKColor.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(minHeight: 48)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    private var whenText: String {
        switch form.searchType {
        case .departure where form.usesCurrentTime:
            return String(localized: "今 出発", bundle: .module)
        default:
            let query = RouteSearchQuery(fromStationId: "", toStationId: "", dateTime: form.dateTime, searchType: form.searchType)
            return QueryText.when(query)
        }
    }

    private var viaText: String {
        let region = form.region(default: dependencies.settings.preferredRegion)
        if !dependencies.capabilities.snapshot.isSupported(.viaStations, region: region) {
            return UnsupportedText.label(.viaStations)
        }
        if form.via.isEmpty { return String(localized: "追加する（最大3駅）", bundle: .module) }
        return form.via.map(\.name).joined(separator: "・")
    }

    // MARK: 最近の検索・お気に入り（FR-SRC-06）

    @ViewBuilder
    private var historySection: some View {
        let history = Array(dependencies.userData.history().prefix(3))
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(String(localized: "最近の検索", bundle: .module)) {
                if !history.isEmpty {
                    Button(String(localized: "すべて見る", bundle: .module)) {
                        dependencies.router.selectedTab = .my
                        dependencies.router.myPath = [.history]
                    }
                    .font(.footnote)
                }
            }
            if history.isEmpty {
                EmptyStateView(
                    systemImage: "clock.arrow.circlepath",
                    title: String(localized: "検索の履歴はまだありません", bundle: .module),
                    actionTitle: String(localized: "駅を検索する", bundle: .module),
                    action: { picking = .from }
                )
                .nkCard()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(history.enumerated()), id: \.element.id) { index, entry in
                        Button {
                            form.apply(entry.query, catalog: catalog)
                        } label: {
                            NKRow(showsChevron: false) {
                                Image(systemName: "clock")
                                    .foregroundStyle(NKColor.textTertiary)
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(QueryText.title(entry.query, catalog: catalog))
                                        .font(.subheadline.weight(.bold))
                                        .foregroundStyle(NKColor.textPrimary)
                                    Text(QueryText.when(entry.query))
                                        .font(.caption)
                                        .foregroundStyle(NKColor.textSecondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        if index < history.count - 1 { NKDivider() }
                    }
                }
                .nkCard()
            }
        }
    }

    @ViewBuilder
    private var favoriteSection: some View {
        let routes: [FavoriteRouteItem] = dependencies.userData.favorites().compactMap { entry in
            if case .route(let route) = entry.item { return FavoriteRouteItem(id: entry.id, route: route) }
            return nil
        }
        if !routes.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                SectionHeader(String(localized: "お気に入り", bundle: .module))
                VStack(spacing: 0) {
                    ForEach(Array(routes.enumerated()), id: \.element.id) { index, item in
                        Button {
                            // 開くときに再検索する（FR-DTL-03）
                            dependencies.router.searchPath.append(.results(item.route.query.refreshed(now: Date()), preferred: item.route.signature))
                        } label: {
                            NKRow {
                                Image(systemName: "star.fill")
                                    .foregroundStyle(NKColor.accent)
                                    .accessibilityHidden(true)
                                Text(QueryText.title(item.route.query, catalog: catalog))
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(NKColor.textPrimary)
                                Text("経路", bundle: .module)
                                    .font(.caption)
                                    .foregroundStyle(NKColor.textTertiary)
                            }
                        }
                        .buttonStyle(.plain)
                        if index < routes.count - 1 { NKDivider() }
                    }
                }
                .nkCard()
            }
        }
    }

    private struct FavoriteRouteItem: Identifiable {
        var id: UUID
        var route: FavoriteRoute
    }
}

/// 案内中の経路のカード
struct ActiveGuidanceCard: View {
    let session: GuidanceSession
    let onEnd: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "location.fill")
                .foregroundStyle(NKColor.onAccent)
                .frame(width: 36, height: 36)
                .background(NKColor.accentFill, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("案内中", bundle: .module)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(NKColor.accent)
                Text("\(session.summary.originName) → \(session.summary.destinationName)", bundle: .module)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(NKColor.textPrimary)
                Text("\(NKFormat.time(session.route.departureTime))発 → \(NKFormat.time(session.route.arrivalTime))着", bundle: .module)
                    .font(.nkNumeric(.caption, weight: .regular))
                    .foregroundStyle(NKColor.textSecondary)
            }
            Spacer()
            Button(String(localized: "案内終了", bundle: .module), action: onEnd)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(NKColor.accent)
                .frame(minHeight: NKSpacing.minTapTarget)
                .accessibilityIdentifier("endGuidanceButton")
        }
        .padding(NKSpacing.cardPadding)
        .nkCard()
        .accessibilityElement(children: .contain)
    }
}
