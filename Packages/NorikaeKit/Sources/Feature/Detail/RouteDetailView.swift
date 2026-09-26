import DesignSystem
import Domain
import SwiftUI

/// 経路詳細（縦タイムライン、design-spec 7.5）
struct RouteDetailView: View {
    private let dependencies: AppDependencies
    @State private var model: RouteDetailModel
    @State private var screenshot: Image?

    init(selection: RouteSelection, dependencies: AppDependencies) {
        self.dependencies = dependencies
        _model = State(initialValue: RouteDetailModel(selection: selection, dependencies: dependencies))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NKSpacing.cardGap) {
                summaryCard
                ForEach(model.route.routeLevelWarnings, id: \.self) { warning in
                    Label {
                        Text(warning.message)
                    } icon: {
                        Image(systemName: "exclamationmark.circle")
                    }
                    .font(.footnote)
                    .foregroundStyle(NKColor.textSecondary)
                }
                if let asOf = model.selection.asOf {
                    if model.selection.isFromCache {
                        DataNoticeBanner(.cached(asOf: asOf))
                    } else if model.route.availability == .stale {
                        DataNoticeBanner(.stale(asOf: asOf))
                    }
                }
                timeline
                AttributionFooter(model.selection.attributions)
            }
            .padding(.vertical, 12)
            .nkScreen()
        }
        .safeAreaInset(edge: .bottom) { startButton }
        .nkScreenBackground()
        .navigationTitle(String(localized: "経路詳細", bundle: .module))
        .navigationBarTitleDisplayMode(.inline)
        // この画面ではタブバーを隠す（design-spec 7.5）
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    model.toggleFavorite()
                } label: {
                    Image(systemName: model.isFavorite ? "star.fill" : "star")
                }
                .accessibilityLabel(model.isFavorite ? Text("お気に入りから外す", bundle: .module) : Text("お気に入りに追加", bundle: .module))
                .accessibilityIdentifier("favoriteButton")
                shareMenu
            }
        }
        .task { renderScreenshot() }
        .onChange(of: model.route) { renderScreenshot() }
    }

    private var timeline: some View {
        RouteTimelineView(
            route: model.route, catalog: model.catalog, capabilities: model.capabilities,
            onSelectStopList: { leg in
                guard let runID = leg.trainRunId else { return }
                dependencies.router.searchPath.append(.stopList(StopListRequest(
                    trainRunId: runID, serviceDate: leg.from.serviceDate, lineId: leg.lineId,
                    fromStationId: leg.from.stationId, toStationId: leg.to.stationId
                )))
            },
            onShowStationMap: { stationID in
                dependencies.router.searchPath.append(.stationMap(stationId: stationID))
            }
        )
    }

    // MARK: 上部の要約カード

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                RouteBadgeRow(badges: model.selection.badges, hasDisruption: model.route.hasServiceDisruption)
                Text("\(NKFormat.date(model.route.departureTime)) · \(NKFormat.fareKindLabel(model.fareKind))", bundle: .module)
                    .font(.caption)
                    .foregroundStyle(NKColor.textSecondary)
            }
            Text("\(NKFormat.time(model.route.departureTime)) → \(NKFormat.time(model.route.arrivalTime))", bundle: .module)
                .font(.nkNumeric(.largeTitle, weight: .bold))
                .foregroundStyle(NKColor.textPrimary)
                .accessibilityLabel(Text("\(NKFormat.spokenTime(model.route.departureTime))発、\(NKFormat.spokenTime(model.route.arrivalTime))着", bundle: .module))
            HStack(spacing: 14) {
                Text(NKFormat.duration(minutes: model.route.durationMinutes)).fontWeight(.bold)
                Text("乗換 \(model.route.transferCount)回", bundle: .module)
                Text("運賃 \(model.fareText)", bundle: .module)
            }
            .font(.subheadline)
            .foregroundStyle(NKColor.textSecondary)

            HStack(spacing: 10) {
                Button {
                    Task { await model.loadAdjacent(.previous) }
                } label: {
                    Label { Text("1本前", bundle: .module) } icon: { Image(systemName: "chevron.left") }
                }
                .accessibilityIdentifier("previousRouteButton")
                Button {
                    Task { await model.loadAdjacent(.next) }
                } label: {
                    Label { Text("1本後", bundle: .module) } icon: { Image(systemName: "chevron.right") }
                        .labelStyle(TrailingIconLabelStyle())
                }
                .accessibilityIdentifier("nextRouteButton")
            }
            .buttonStyle(NKSecondaryButtonStyle())
            .disabled(model.adjacentState == .running)

            switch model.adjacentState {
            case .running:
                SkeletonBlock(height: 12)
            case .failed(let error):
                Text(error.message)
                    .font(.footnote)
                    .foregroundStyle(NKColor.delayText)
            case .idle:
                if let text = model.adjacentChangeText {
                    Label {
                        Text(text)
                    } icon: {
                        Image(systemName: "info.circle")
                    }
                    .font(.footnote)
                    .foregroundStyle(NKColor.textSecondary)
                }
            }
        }
        .padding(NKSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nkCard()
    }

    // MARK: 案内開始（画面下に固定）

    private var startButton: some View {
        VStack(spacing: 6) {
            if case .failed(let error) = model.guidanceState {
                Text(error.message)
                    .font(.footnote)
                    .foregroundStyle(NKColor.delayText)
                    .multilineTextAlignment(.center)
            }
            if model.isGuiding {
                Button {
                    Task { await model.endGuidance() }
                } label: {
                    Label { Text("案内終了", bundle: .module) } icon: { Image(systemName: "xmark.circle") }
                }
                .buttonStyle(NKSecondaryButtonStyle())
                .accessibilityIdentifier("endGuidanceButton")
            } else {
                Button {
                    Task { await model.startGuidance() }
                } label: {
                    Label { Text("この経路で案内開始", bundle: .module) } icon: { Image(systemName: "location.fill") }
                }
                .buttonStyle(NKPrimaryButtonStyle())
                .disabled(model.guidanceState == .running)
                .accessibilityIdentifier("startGuidanceButton")
            }
        }
        .padding(.horizontal, NKSpacing.screenHorizontal)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .background(NKColor.background.opacity(0.95))
    }

    // MARK: 共有（テキスト・スクリーンショット、FR-DTL-04）

    private var shareMenu: some View {
        Menu {
            ShareLink(item: model.shareText) {
                Label { Text("テキストで共有", bundle: .module) } icon: { Image(systemName: "text.alignleft") }
            }
            if let screenshot {
                ShareLink(item: screenshot, preview: SharePreview(QueryText.title(model.selection.query, catalog: model.catalog), image: screenshot)) {
                    Label { Text("スクリーンショットで共有", bundle: .module) } icon: { Image(systemName: "photo") }
                }
            }
        } label: {
            Image(systemName: "square.and.arrow.up")
        }
        .accessibilityLabel(Text("共有", bundle: .module))
    }

    @MainActor
    private func renderScreenshot() {
        let content = VStack(alignment: .leading, spacing: 12) {
            summaryCard
            timeline
        }
        .padding(16)
        .frame(width: 390)
        .background(NKColor.background)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 3
        if let image = renderer.uiImage {
            screenshot = Image(uiImage: image)
        }
    }
}

/// アイコンを文字の後ろに置く（「1本後 ›」）
struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.title
            configuration.icon
        }
    }
}
