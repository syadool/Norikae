import DesignSystem
import Domain
import Foundation
import Observation

/// 運行情報の一覧の ViewModel（FR-STS）
@MainActor
@Observable
final class StatusListModel {
    struct Row: Identifiable, Hashable {
        var line: Line
        /// 運行情報。非対応の路線は `nil`
        var status: OperationStatus?
        var id: String { line.id }
    }

    struct OperatorSection: Identifiable, Hashable {
        var operatorName: String
        var rows: [Row]
        var id: String { operatorName }
    }

    var region: Region
    private(set) var phase: LoadPhase = .loading
    private(set) var statuses: [String: OperationStatus] = [:]
    private(set) var meta: ResponseMeta?
    private(set) var loadedRegions: Set<Region> = []

    private let dependencies: AppDependencies

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
        // 初期表示は主に使う地域（FR-STS-02）
        region = dependencies.settings.preferredRegion
    }

    private var catalog: Catalog { dependencies.catalog }
    private var capabilities: CapabilitySnapshot { dependencies.capabilities.snapshot }

    /// マイ路線（FR-STS-01）
    var myLineRows: [Row] {
        dependencies.userData.myLines().compactMap { entry in
            guard let line = catalog.line(entry.lineId) else { return nil }
            return row(for: line)
        }
    }

    /// 鉄道会社ごとの路線（運行情報に対応している路線）
    var operatorSections: [OperatorSection] {
        let lines = linesInRegion.filter { capabilities.isSupported(.operationAlerts, lineId: $0.id) }
        let grouped = Dictionary(grouping: lines, by: \.operatorId)
        return grouped.keys.sorted().map { operatorID in
            OperatorSection(
                operatorName: catalog.operator(operatorID)?.name ?? operatorID,
                rows: (grouped[operatorID] ?? []).sorted { $0.name < $1.name }.map(row(for:))
            )
        }
    }

    /// 運行情報に対応していない路線（まとめて表示する、FR-STS-06）
    var unsupportedRows: [Row] {
        linesInRegion
            .filter { !capabilities.isSupported(.operationAlerts, lineId: $0.id) }
            .sorted { ($0.operatorId, $0.name) < ($1.operatorId, $1.name) }
            .map { Row(line: $0, status: nil) }
    }

    private var linesInRegion: [Line] {
        catalog.lines.values.filter { $0.region == region }
    }

    private func row(for line: Line) -> Row {
        guard capabilities.isSupported(.operationAlerts, lineId: line.id) else { return Row(line: line, status: nil) }
        // 取得できなかった路線は「情報なし」（平常ではない、FR-STS-03）
        let status = statuses[line.id] ?? OperationStatus(
            lineId: line.id, status: .unknown, summary: String(localized: "運行情報を確認できません", bundle: .module),
            asOf: meta?.asOf ?? Date()
        )
        return Row(line: line, status: status)
    }

    func load() async {
        phase = .loading
        // マイ路線がほかの地域にもあれば、その地域も取得する
        var regions: [Region] = [region]
        for entry in dependencies.userData.myLines() {
            if let line = catalog.line(entry.lineId), !regions.contains(line.region) { regions.append(line.region) }
        }
        do {
            for target in regions {
                let list = try await dependencies.statuses.statuses(region: target)
                for status in list.statuses { statuses[status.lineId] = status }
                if target == region { meta = list.meta }
                loadedRegions.insert(target)
            }
            phase = .loaded
        } catch {
            phase = .failed(AppError.wrap(error).presentation)
        }
    }
}
