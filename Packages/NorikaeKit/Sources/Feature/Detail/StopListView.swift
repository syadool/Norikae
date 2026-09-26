import DesignSystem
import Domain
import SwiftUI

/// 停車駅一覧の ViewModel（FR-DTL-07、FR-TT-06）
@MainActor
@Observable
final class StopListModel {
    private(set) var phase: LoadPhase = .loading
    private(set) var result: TrainRunResult?
    let request: StopListRequest
    private let dependencies: AppDependencies

    init(request: StopListRequest, dependencies: AppDependencies) {
        self.request = request
        self.dependencies = dependencies
    }

    var catalog: Catalog { dependencies.catalog }
    var isSupported: Bool { dependencies.capabilities.snapshot.isSupported(.stopList, lineId: request.lineId) }

    func load() async {
        guard isSupported else { return }
        phase = .loading
        do {
            result = try await dependencies.routes.trainRun(id: request.trainRunId, serviceDate: request.serviceDate)
            phase = (result?.trainRun.stops.isEmpty ?? true) ? .empty : .loaded
        } catch {
            let appError = AppError.wrap(error)
            phase = appError.apiCode == .featureUnavailable
                ? .failed(ErrorPresentation(message: UnsupportedText.explanation(.stopList), retryable: false))
                : .failed(appError.presentation)
        }
    }

    /// 乗車駅から降車駅までの区間か
    func isWithinRide(_ index: Int) -> Bool {
        guard let stops = result?.trainRun.stops,
              let from = stops.firstIndex(where: { $0.stationId == request.fromStationId }),
              let to = stops.firstIndex(where: { $0.stationId == request.toStationId }) else { return false }
        return (from...to).contains(index)
    }
}

/// 停車駅一覧（時刻表の停車駅一覧と同じ画面）
struct StopListView: View {
    @State private var model: StopListModel

    init(request: StopListRequest, dependencies: AppDependencies) {
        _model = State(initialValue: StopListModel(request: request, dependencies: dependencies))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NKSpacing.cardGap) {
                if !model.isSupported {
                    UnsupportedNotice(.stopList)
                        .padding(NKSpacing.cardPadding)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .nkCard()
                } else {
                    switch model.phase {
                    case .loading:
                        ListSkeleton(rows: 8)
                    case .empty:
                        EmptyStateView(systemImage: "list.bullet", title: String(localized: "停車駅の情報がありません", bundle: .module))
                            .nkCard()
                    case .failed(let error):
                        ErrorStateView(message: error.message, retryable: error.retryable) {
                            Task { await model.load() }
                        }
                    case .loaded:
                        if let run = model.result?.trainRun {
                            header(run)
                            stops(run)
                            AttributionFooter(model.result?.meta.attributions ?? [])
                        }
                    }
                }
            }
            .padding(.vertical, 12)
            .nkScreen()
        }
        .nkScreenBackground()
        .navigationTitle(String(localized: "停車駅一覧", bundle: .module))
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
    }

    private func header(_ run: TrainRun) -> some View {
        let appearance = LineAppearance(line: model.catalog.line(run.lineId), fallbackID: run.lineId)
        let type = model.catalog.trainType(run.trainTypeId)
        return HStack(spacing: 8) {
            LineSymbolChip(appearance, size: .detail)
            Text(appearance.name).font(.subheadline.weight(.bold))
            if let type {
                Text(type.name).font(.subheadline.weight(.bold)).foregroundStyle(trainTypeColor(type))
            }
            Text(run.destinationName).font(.subheadline).foregroundStyle(NKColor.textSecondary)
            Spacer()
        }
        .padding(NKSpacing.cardPadding)
        .nkCard()
        .accessibilityElement(children: .combine)
    }

    private func stops(_ run: TrainRun) -> some View {
        let color = LineAppearance(line: model.catalog.line(run.lineId), fallbackID: run.lineId).color
        return VStack(spacing: 0) {
            ForEach(Array(run.stops.enumerated()), id: \.offset) { index, stop in
                let highlighted = model.isWithinRide(index)
                HStack(spacing: 12) {
                    Text(NKFormat.time(stop.scheduledTime))
                        .font(.nkNumeric(.subheadline, weight: highlighted ? .bold : .regular))
                        .foregroundStyle(highlighted ? NKColor.textPrimary : NKColor.textSecondary)
                        .frame(width: 52, alignment: .trailing)
                    Circle()
                        .fill(highlighted ? color : NKColor.fillCarInactive)
                        .frame(width: 10, height: 10)
                        .accessibilityHidden(true)
                    Text(model.catalog.station(stop.stationId)?.name ?? String(localized: "駅名不明", bundle: .module))
                        .font(.subheadline.weight(highlighted ? .bold : .regular))
                        .foregroundStyle(highlighted ? NKColor.textPrimary : NKColor.textSecondary)
                    Spacer()
                    if let platform = stop.platform { PlatformPill(platform) }
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 44)
                .accessibilityElement(children: .combine)
                if index < run.stops.count - 1 { NKDivider(leading: 80) }
            }
        }
        .padding(.vertical, 6)
        .nkCard()
    }
}
