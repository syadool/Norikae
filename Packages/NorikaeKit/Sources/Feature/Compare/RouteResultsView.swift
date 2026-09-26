import DesignSystem
import Domain
import SwiftUI

/// 縦比較（検索結果）の画面（design-spec 7.4、FR-CMP）
struct RouteResultsView: View {
    private let dependencies: AppDependencies
    @State private var model: RouteResultsModel

    init(query: RouteSearchQuery, preferred: RouteSignature?, fareKind: FareKind?, dependencies: AppDependencies) {
        self.dependencies = dependencies
        _model = State(initialValue: RouteResultsModel(query: query, preferred: preferred, fareKind: fareKind, dependencies: dependencies))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            NKSegmentedPicker(selection: $model.sortOrder, options: RouteSortOrder.allCases.map {
                NKSegmentedPicker<RouteSortOrder>.Option($0, QueryText.sortName($0))
            })
            .accessibilityIdentifier("sortPicker")
            infoRow
            ForEach(model.notices, id: \.self) { DataNoticeBanner($0) }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            AttributionFooter(model.attributions)
        }
        .padding(.top, 8)
        .nkScreen()
        .nkScreenBackground()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 0) {
                    Text(QueryText.title(model.query, catalog: model.catalog))
                        .font(.headline)
                        .foregroundStyle(NKColor.textPrimary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(NKColor.textSecondary)
                }
                .accessibilityElement(children: .combine)
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    dependencies.router.searchPath.removeAll()
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .accessibilityLabel(Text("条件を変更", bundle: .module))
            }
        }
        .task {
            guard model.result == nil else { return }
            await model.load()
            openPreferredIfNeeded()
        }
    }

    private var subtitle: String {
        "\(NKFormat.date(model.query.dateTime)) \(QueryText.when(model.query, includesDate: false))"
    }

    @ViewBuilder
    private var infoRow: some View {
        if model.phase == .loaded {
            HStack {
                if let info = model.infoText {
                    Menu {
                        Picker(String(localized: "運賃", bundle: .module), selection: $model.fareKind) {
                            ForEach(FareKind.allCases, id: \.self) { kind in
                                Text(NKFormat.fareKindLabel(kind)).tag(kind)
                            }
                        }
                    } label: {
                        Text(info)
                            .font(.caption)
                            .foregroundStyle(NKColor.textSecondary)
                    }
                    .accessibilityHint(Text("運賃の種別を切り替えます", bundle: .module))
                }
                Spacer()
                let count = model.columns.count
                Text(count > 3 ? String(localized: "1–3 / 全\(count)件 ›", bundle: .module) : String(localized: "全\(count)件", bundle: .module))
                    .font(.caption)
                    .foregroundStyle(NKColor.textSecondary)
                    .accessibilityLabel(Text(count > 3 ? String(localized: "全\(count)件。横にスクロールすると残りの経路を表示します", bundle: .module) : String(localized: "全\(count)件", bundle: .module)))
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading:
            RouteCompareSkeleton()
                .frame(minHeight: 420)
        case .loaded:
            RouteCompareView(columns: model.columns, catalog: model.catalog) { routeID in
                guard let selection = model.selection(for: routeID) else { return }
                dependencies.router.searchPath.append(.detail(selection))
            }
            .frame(minHeight: 420)
        case .empty:
            EmptyStateView(
                systemImage: "tram",
                title: String(localized: "経路が見つかりませんでした", bundle: .module),
                message: String(localized: "日時や経由駅などの条件を変えて検索してください", bundle: .module),
                actionTitle: String(localized: "条件を変更", bundle: .module),
                action: { dependencies.router.searchPath.removeAll() }
            )
            .nkCard()
        case .failed(let error):
            ErrorStateView(message: error.message, retryable: error.retryable) {
                Task { await model.load() }
            }
        case .featureUnavailable(let message, let removable):
            FeatureUnavailableView(message: message, removable: removable) { condition in
                Task { await model.searchRemoving(condition) }
            }
        }
    }

    private func openPreferredIfNeeded() {
        if let selection = model.takePreferredSelection() {
            dependencies.router.searchPath.append(.detail(selection))
        }
    }
}

/// 「この区間・条件には対応していません」と、条件を外して再検索する導線（api-contract 2.3）
struct FeatureUnavailableView: View {
    let message: String
    let removable: [RemovableCondition]
    let onRemove: (RemovableCondition) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                Text(message)
            } icon: {
                Image(systemName: "circle.slash")
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(NKColor.textPrimary)
            ForEach(removable, id: \.self) { condition in
                Button {
                    onRemove(condition)
                } label: {
                    switch condition {
                    case .viaStations: Text("経由駅を外して再検索", bundle: .module)
                    case .firstLastTrain: Text("始発・終電をやめて、今の時刻で再検索", bundle: .module)
                    }
                }
                .buttonStyle(NKSecondaryButtonStyle())
                .accessibilityIdentifier("removeCondition-\(condition.rawValue)")
            }
        }
        .padding(NKSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nkCard()
    }
}
