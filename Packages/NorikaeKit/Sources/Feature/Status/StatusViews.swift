import DesignSystem
import Domain
import SwiftUI

/// 運行情報タブ
struct StatusTab: View {
    @Environment(AppDependencies.self) private var dependencies

    var body: some View {
        @Bindable var router = dependencies.router
        NavigationStack(path: $router.statusPath) {
            StatusListView(dependencies: dependencies)
                .navigationDestination(for: StatusDestination.self) { destination in
                    switch destination {
                    case .detail(let lineId):
                        StatusDetailView(lineId: lineId, dependencies: dependencies)
                    }
                }
        }
    }
}

/// 運行情報の一覧（design-spec 7.6）
struct StatusListView: View {
    private let dependencies: AppDependencies
    @State private var model: StatusListModel

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
        _model = State(initialValue: StatusListModel(dependencies: dependencies))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                NKSegmentedPicker(selection: $model.region, options: Region.allCases.map {
                    NKSegmentedPicker<Region>.Option($0, QueryText.regionName($0))
                })

                switch model.phase {
                case .loading:
                    ListSkeleton()
                case .failed(let error):
                    ErrorStateView(message: error.message, retryable: error.retryable) {
                        Task { await model.load() }
                    }
                case .loaded, .empty:
                    myLinesSection
                    ForEach(model.operatorSections) { section in
                        lineSection(title: section.operatorName, rows: section.rows)
                    }
                    if !model.unsupportedRows.isEmpty {
                        unsupportedSection
                    }
                    AttributionFooter(model.meta?.attributions ?? [])
                }
            }
            .padding(.vertical, 12)
            .nkScreen()
        }
        .nkScreenBackground()
        .navigationTitle(String(localized: "運行情報", bundle: .module))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 4) {
                    if let asOf = model.meta?.asOf {
                        // 情報の取得時刻（FR-STS-05）
                        Text("\(NKFormat.time(asOf)) 時点", bundle: .module)
                            .font(.caption)
                            .foregroundStyle(NKColor.textSecondary)
                    }
                    Button {
                        Task { await model.load() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel(Text("更新", bundle: .module))
                }
            }
        }
        .refreshable { await model.load() }
        // 首都圏 / 関西圏を切り替えたら取り直す（FR-STS-02）
        .onChange(of: model.region) { Task { await model.load() } }
        .task { if model.meta == nil { await model.load() } }
    }

    @ViewBuilder
    private var myLinesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(String(localized: "マイ路線", bundle: .module)) {
                Button(String(localized: "編集", bundle: .module)) {
                    dependencies.router.selectedTab = .my
                    dependencies.router.myPath = [.myLines]
                }
                .font(.footnote)
            }
            if model.myLineRows.isEmpty {
                EmptyStateView(
                    systemImage: "star",
                    title: String(localized: "マイ路線を登録すると、ここに運行状況を表示します", bundle: .module),
                    actionTitle: String(localized: "マイ路線を登録する", bundle: .module),
                    action: {
                        dependencies.router.selectedTab = .my
                        dependencies.router.myPath = [.myLines]
                    }
                )
                .nkCard()
            } else {
                rowsCard(model.myLineRows)
            }
        }
    }

    private func lineSection(title: String, rows: [StatusListModel.Row]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title)
            rowsCard(rows)
        }
    }

    /// 運行情報に対応していない路線は、まとめて「運行情報非対応」と表示する（FR-STS-06）
    private var unsupportedSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(String(localized: "運行情報非対応", bundle: .module))
            VStack(alignment: .leading, spacing: 10) {
                Text(UnsupportedText.explanation(.operationAlerts))
                    .font(.caption)
                    .foregroundStyle(NKColor.textTertiary)
                FlowLines(lines: model.unsupportedRows.map(\.line))
            }
            .padding(NKSpacing.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .nkCard()
        }
    }

    private func rowsCard(_ rows: [StatusListModel.Row]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                StatusRow(row: row) {
                    dependencies.router.statusPath.append(.detail(lineId: row.line.id))
                }
                if index < rows.count - 1 { NKDivider(leading: 56) }
            }
        }
        .nkCard()
    }
}

/// 運行情報の行：路線記号チップ（22）｜路線名（下に summary。平常のときは出さない）｜状況の札｜›
struct StatusRow: View {
    let row: StatusListModel.Row
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            NKRow {
                LineSymbolChip(LineAppearance(line: row.line, fallbackID: row.line.id), size: .status)
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.line.name)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(NKColor.textPrimary)
                    if let status = row.status, status.status != .normal, status.status != .unknown {
                        Text(status.summary)
                            .font(.caption)
                            .foregroundStyle(NKColor.textSecondary)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 4)
                if let status = row.status {
                    OperationStatusLabel(status.status, summary: status.summary)
                } else {
                    UnsupportedBadge(.operationAlerts)
                }
            }
            .frame(minHeight: 60)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}

/// 非対応の路線を横に並べる
struct FlowLines: View {
    let lines: [Line]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), alignment: .leading)], alignment: .leading, spacing: 8) {
            ForEach(lines) { line in
                HStack(spacing: 6) {
                    LineSymbolChip(LineAppearance(line: line, fallbackID: line.id), size: .detail)
                    Text(line.name)
                        .font(.caption)
                        .foregroundStyle(NKColor.textSecondary)
                        .lineLimit(1)
                }
            }
        }
    }
}

// MARK: - 詳細（FR-STS-04）

@MainActor
@Observable
final class StatusDetailModel {
    let lineId: String
    private(set) var phase: LoadPhase = .loading
    private(set) var detail: OperationStatusDetail?
    private let dependencies: AppDependencies

    init(lineId: String, dependencies: AppDependencies) {
        self.lineId = lineId
        self.dependencies = dependencies
    }

    var line: Line? { dependencies.catalog.line(lineId) }
    var isSupported: Bool { dependencies.capabilities.snapshot.isSupported(.operationAlerts, lineId: lineId) }

    var myLineEntry: MyLineEntry? {
        dependencies.userData.myLines().first { $0.lineId == lineId }
    }

    func toggleMyLine() {
        if let entry = myLineEntry {
            dependencies.userData.removeMyLine(id: entry.id)
        } else {
            dependencies.userData.addMyLine(lineId: lineId)
        }
    }

    func load() async {
        guard isSupported else {
            phase = .loaded
            return
        }
        phase = .loading
        do {
            detail = try await dependencies.statuses.status(lineID: lineId)
            phase = .loaded
        } catch {
            phase = .failed(AppError.wrap(error).presentation)
        }
    }
}

struct StatusDetailView: View {
    @State private var model: StatusDetailModel

    init(lineId: String, dependencies: AppDependencies) {
        _model = State(initialValue: StatusDetailModel(lineId: lineId, dependencies: dependencies))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NKSpacing.cardGap) {
                if let line = model.line {
                    HStack(spacing: 10) {
                        LineSymbolChip(LineAppearance(line: line, fallbackID: line.id), size: .status)
                        Text(line.name).font(.title3.weight(.bold))
                        Spacer()
                    }
                }
                if !model.isSupported {
                    UnsupportedNotice(.operationAlerts)
                        .padding(NKSpacing.cardPadding)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .nkCard()
                } else {
                    switch model.phase {
                    case .loading:
                        ListSkeleton(rows: 3)
                    case .failed(let error):
                        ErrorStateView(message: error.message, retryable: error.retryable) { Task { await model.load() } }
                    case .loaded, .empty:
                        if let detail = model.detail {
                            detailCard(detail.status)
                            AttributionFooter(detail.meta.attributions)
                        }
                    }
                }
                Button {
                    model.toggleMyLine()
                } label: {
                    if model.myLineEntry == nil {
                        Label { Text("マイ路線に登録", bundle: .module) } icon: { Image(systemName: "star") }
                    } else {
                        Label { Text("マイ路線から外す", bundle: .module) } icon: { Image(systemName: "star.fill") }
                    }
                }
                .buttonStyle(NKSecondaryButtonStyle())
            }
            .padding(.vertical, 12)
            .nkScreen()
        }
        .nkScreenBackground()
        .navigationTitle(String(localized: "運行情報の詳細", bundle: .module))
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
    }

    private func detailCard(_ status: OperationStatus) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            OperationStatusLabel(status.status, summary: status.summary)
            Text(status.summary)
                .font(.subheadline)
                .foregroundStyle(NKColor.textPrimary)
            detailRow(String(localized: "原因", bundle: .module), status.cause)
            detailRow(String(localized: "発生時刻", bundle: .module), status.occurredAt.map(NKFormat.time))
            detailRow(String(localized: "見込み", bundle: .module), status.outlook)
            detailRow(String(localized: "振替輸送", bundle: .module), status.hasTransferTransport.map {
                $0 ? String(localized: "あり", bundle: .module) : String(localized: "なし", bundle: .module)
            })
            Text(NKFormat.asOf(status.asOf))
                .font(.caption)
                .foregroundStyle(NKColor.textTertiary)
        }
        .padding(NKSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nkCard()
    }

    /// 値がない項目は「情報なし」と出す（推測で埋めない）
    private func detailRow(_ title: String, _ value: String?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.footnote)
                .foregroundStyle(NKColor.textSecondary)
                .frame(width: 72, alignment: .leading)
            Text(value ?? String(localized: "情報なし", bundle: .module))
                .font(.footnote.weight(value == nil ? .regular : .semibold))
                .foregroundStyle(value == nil ? NKColor.textTertiary : NKColor.textPrimary)
        }
        .accessibilityElement(children: .combine)
    }
}
