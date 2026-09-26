import Domain
import SwiftUI

/// 経路詳細の縦タイムライン（design-spec 7.5、FR-DTL-01・05・07・09・10・11）
///
/// 3 つの列：時刻 60 ｜ レール 26 ｜ 内容
public struct RouteTimelineView: View {
    private let route: Route
    private let catalog: Catalog
    private let capabilities: CapabilitySnapshot
    private let onSelectStopList: (TrainLeg) -> Void
    private let onShowStationMap: (String) -> Void

    public init(
        route: Route, catalog: Catalog, capabilities: CapabilitySnapshot,
        onSelectStopList: @escaping (TrainLeg) -> Void, onShowStationMap: @escaping (String) -> Void
    ) {
        self.route = route
        self.catalog = catalog
        self.capabilities = capabilities
        self.onSelectStopList = onSelectStopList
        self.onShowStationMap = onShowStationMap
    }

    public var body: some View {
        let trains = route.indexedTrainLegs
        let transfers = route.transfers
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(trains.enumerated()), id: \.offset) { position, item in
                let appearance = LineAppearance(line: catalog.line(item.leg.lineId), fallbackID: item.leg.lineId)
                TimelineStationRow(
                    stop: item.leg.from, role: .departure, stationName: stationName(item.leg.from.stationId),
                    railAbove: position == 0 ? .none : .dotted, railBelow: .solid(appearance.color),
                    node: .ring(appearance.color), showsPlatform: capabilities.isSupported(.platform, lineId: item.leg.lineId),
                    hasRealtime: capabilities.isSupported(.tripUpdates, lineId: item.leg.lineId)
                )
                .accessibilityIdentifier("timelineDeparture-\(position)")
                TimelineRideRow(
                    leg: item.leg, legIndex: item.legIndex, appearance: appearance, catalog: catalog, capabilities: capabilities,
                    warnings: route.warnings(forLegAt: item.legIndex), onSelectStopList: onSelectStopList
                )
                TimelineStationRow(
                    stop: item.leg.to, role: .arrival, stationName: stationName(item.leg.to.stationId),
                    railAbove: .solid(appearance.color), railBelow: position == trains.count - 1 ? .none : .dotted,
                    node: position == trains.count - 1 ? .filled(appearance.color) : .ring(appearance.color),
                    showsPlatform: capabilities.isSupported(.platform, lineId: item.leg.lineId),
                    hasRealtime: capabilities.isSupported(.tripUpdates, lineId: item.leg.lineId)
                )
                if position < transfers.count {
                    let nextIndex = trains[position + 1].legIndex
                    let walkWarnings = ((item.legIndex + 1)..<nextIndex).flatMap { route.warnings(forLegAt: $0) }
                    TimelineTransferRow(
                        transfer: transfers[position], warnings: walkWarnings,
                        onShowStationMap: { onShowStationMap(transfers[position].fromStationId) }
                    )
                }
            }
        }
        .padding(.vertical, 12)
        .padding(.trailing, 12)
        .nkCard()
    }

    private func stationName(_ id: String) -> String {
        catalog.station(id)?.name ?? String(localized: "駅名不明", bundle: .module)
    }
}

// MARK: - レール

enum RailSegment {
    case none
    case solid(Color)
    case dotted
}

enum RailNode {
    case ring(Color)
    case filled(Color)
}

/// レールの列（幅 26）。行の高さいっぱいに線を描き、中央に丸を置く
struct RailColumn: View {
    let above: RailSegment
    let below: RailSegment
    let node: RailNode?
    /// 丸の縦位置（行の上端から）。`nil` なら行の中央
    var nodeY: CGFloat? = nil

    var body: some View {
        GeometryReader { geometry in
            let centerX = geometry.size.width / 2
            let splitY = nodeY ?? geometry.size.height / 2
            ZStack(alignment: .topLeading) {
                segment(above, from: 0, to: splitY, x: centerX)
                segment(below, from: splitY, to: geometry.size.height, x: centerX)
                if let node {
                    nodeView(node)
                        .position(x: centerX, y: splitY)
                }
            }
        }
        .frame(width: NKTimelineMetrics.railColumnWidth)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func segment(_ segment: RailSegment, from top: CGFloat, to bottom: CGFloat, x: CGFloat) -> some View {
        switch segment {
        case .none:
            EmptyView()
        case .solid(let color):
            Rectangle()
                .fill(color)
                .frame(width: NKTimelineMetrics.railWidth, height: max(bottom - top, 0))
                .position(x: x, y: (top + bottom) / 2)
        case .dotted:
            Path { path in
                path.move(to: CGPoint(x: x, y: top))
                path.addLine(to: CGPoint(x: x, y: bottom))
            }
            .stroke(NKColor.connectorTransfer, style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [2, 4]))
        }
    }

    @ViewBuilder
    private func nodeView(_ node: RailNode) -> some View {
        switch node {
        case .ring(let color):
            Circle()
                .fill(NKColor.surface)
                .overlay { Circle().strokeBorder(color, lineWidth: NKTimelineMetrics.nodeBorderWidth) }
                .frame(width: NKTimelineMetrics.nodeDiameter, height: NKTimelineMetrics.nodeDiameter)
        case .filled(let color):
            Circle()
                .fill(color)
                .frame(width: NKTimelineMetrics.terminalNodeDiameter, height: NKTimelineMetrics.terminalNodeDiameter)
        }
    }
}

// MARK: - 行

/// 駅の行（発・着、高さ 40）
struct TimelineStationRow: View {
    enum Role { case departure, arrival }

    let stop: StopPoint
    let role: Role
    let stationName: String
    let railAbove: RailSegment
    let railBelow: RailSegment
    let node: RailNode
    let showsPlatform: Bool
    let hasRealtime: Bool

    @ScaledMetric(relativeTo: .headline) private var rowHeight: CGFloat = NKTimelineMetrics.stationRowHeight

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            VStack(alignment: .trailing, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(NKFormat.time(stop.scheduledTime))
                        .font(.nkNumeric(.headline, weight: .bold))
                        .foregroundStyle(NKColor.textPrimary)
                    Text(role == .departure ? String(localized: "発", bundle: .module) : String(localized: "着", bundle: .module))
                        .font(.caption2)
                        .foregroundStyle(NKColor.textTertiary)
                }
                // 見込み時刻（リアルタイムの予測がある場合のみ。ないときに「定刻」とは出さない）
                if let estimated = stop.estimatedTime, let delay = stop.delayMinutes, delay != 0 {
                    Text("見込 \(NKFormat.time(estimated))", bundle: .module)
                        .font(.nkNumeric(.caption2))
                        .foregroundStyle(NKColor.delayText)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(width: NKTimelineMetrics.timeColumnWidth, alignment: .trailing)
            .padding(.trailing, 2)

            Color.clear.frame(width: NKTimelineMetrics.railColumnWidth)

            HStack(spacing: 8) {
                Text(stationName)
                    .font(.headline)
                    .foregroundStyle(NKColor.textPrimary)
                    .lineLimit(2)
                // 番線がない区間は札を出さない（FR-DTL-01）
                if let platform = stop.platform {
                    PlatformPill(platform)
                }
            }
            .padding(.leading, 4)
            Spacer(minLength: 0)
        }
        .frame(minHeight: rowHeight)
        // レールは行の大きさに合わせて背景に描く
        .background(alignment: .topLeading) {
            RailColumn(above: railAbove, below: railBelow, node: node)
                .padding(.leading, NKTimelineMetrics.timeColumnWidth + 2)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(accessibilityText))
    }

    private var accessibilityText: String {
        var parts = [stationName]
        parts.append(role == .departure
            ? String(localized: "\(NKFormat.spokenTime(stop.scheduledTime))発", bundle: .module)
            : String(localized: "\(NKFormat.spokenTime(stop.scheduledTime))着", bundle: .module))
        if let estimated = stop.estimatedTime, let delay = stop.delayMinutes, delay != 0 {
            parts.append(String(localized: "見込み\(NKFormat.spokenTime(estimated))", bundle: .module))
        }
        if let platform = stop.platform {
            parts.append(String(localized: "\(platform)番線", bundle: .module))
        }
        return parts.joined(separator: "、")
    }
}

/// 乗車区間の行
struct TimelineRideRow: View {
    let leg: TrainLeg
    let legIndex: Int
    let appearance: LineAppearance
    let catalog: Catalog
    let capabilities: CapabilitySnapshot
    let warnings: [RouteWarning]
    let onSelectStopList: (TrainLeg) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Color.clear.frame(width: NKTimelineMetrics.timeColumnWidth + 2)
            Color.clear.frame(width: NKTimelineMetrics.railColumnWidth)
            VStack(alignment: .leading, spacing: 6) {
                lineHeader
                stopListButton
                boardingPosition
                if let disruption = leg.disruption {
                    Label {
                        Text(disruption.summary)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                    }
                    .font(.footnote)
                    .foregroundStyle(NKColor.delayText)
                }
                ForEach(warnings, id: \.self) { warning in
                    Label {
                        Text(warning.message)
                    } icon: {
                        Image(systemName: "exclamationmark.circle")
                    }
                    .font(.caption)
                    .foregroundStyle(NKColor.textSecondary)
                }
                if !capabilities.isSupported(.tripUpdates, lineId: leg.lineId) {
                    ScheduledTimeNote()
                }
            }
            .padding(.leading, 4)
            .padding(.vertical, 8)
            Spacer(minLength: 0)
        }
        .background(alignment: .topLeading) {
            RailColumn(above: .solid(appearance.color), below: .solid(appearance.color), node: nil)
                .padding(.leading, NKTimelineMetrics.timeColumnWidth + 2)
        }
    }

    private var lineHeader: some View {
        let type = catalog.trainType(leg.trainTypeId)
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                LineSymbolChip(appearance, size: .detail)
                Text(appearance.name)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(NKColor.textPrimary)
                if let type {
                    Text(type.name)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(trainTypeColor(type))
                }
            }
            Text(leg.destinationName)
                .font(.footnote)
                .foregroundStyle(NKColor.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }

    /// 「途中 n 駅に停車 ›」。`trainRunId` がない区間はタップできないようにし、見た目でも区別する（FR-DTL-07）
    @ViewBuilder
    private var stopListButton: some View {
        let text = Text("途中 \(leg.stopCount)駅に停車", bundle: .module)
        if leg.trainRunId != nil, capabilities.isSupported(.stopList, lineId: leg.lineId) {
            Button {
                onSelectStopList(leg)
            } label: {
                HStack(spacing: 2) {
                    text
                    Image(systemName: "chevron.right").font(.caption2.weight(.semibold))
                }
                .font(.footnote)
                .foregroundStyle(NKColor.accent)
                .frame(minHeight: NKSpacing.minTapTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text("停車駅一覧を開きます", bundle: .module))
            .accessibilityIdentifier("stopListButton-\(legIndex)")
        } else {
            HStack(spacing: 6) {
                text
                    .font(.footnote)
                    .foregroundStyle(NKColor.textTertiary)
                UnsupportedBadge(.stopList)
            }
            .accessibilityElement(children: .combine)
        }
    }

    /// 乗車位置（FR-DTL-05）。データがない区間では表示しない。路線が非対応なら非対応と示す（FR-CAP-02）
    @ViewBuilder
    private var boardingPosition: some View {
        if let position = leg.boardingPosition {
            BoardingPositionView(position: position, color: appearance.color)
        } else if !capabilities.isSupported(.boardingPosition, lineId: leg.lineId) {
            UnsupportedBadge(.boardingPosition)
        }
    }
}

/// 乗車位置（号車を 18×10 の角丸の四角で並べる、design-spec 7.5）
public struct BoardingPositionView: View {
    private let position: BoardingPosition
    private let color: Color

    public init(position: BoardingPosition, color: Color) {
        self.position = position
        self.color = color
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let count = position.carCount, count > 0, count <= 16 {
                HStack(spacing: NKTimelineMetrics.carSpacing) {
                    ForEach(1...count, id: \.self) { car in
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(car == position.carNumber ? color : NKColor.fillCarInactive)
                            .frame(width: NKTimelineMetrics.carSize.width, height: NKTimelineMetrics.carSize.height)
                    }
                }
                .accessibilityHidden(true)
            }
            (Text("\(position.carNumber)号車", bundle: .module).fontWeight(.bold) + Text(noteText))
                .font(.caption)
                .foregroundStyle(NKColor.textPrimary)
        }
        .padding(10)
        .background(NKColor.fillSubtle, in: RoundedRectangle(cornerRadius: NKRadius.sm, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var noteText: String {
        if let note = position.note { return " · \(note)" }
        switch position.purpose {
        case .transfer: return String(localized: " · 乗換に便利", bundle: .module)
        case .exit: return String(localized: " · 出口に近い", bundle: .module)
        case .other: return ""
        }
    }
}

/// 乗換の行（高さ 44）：「乗換 4分（徒歩 約2分）」、右に「駅の地図」
struct TimelineTransferRow: View {
    let transfer: TransferInfo
    let warnings: [RouteWarning]
    let onShowStationMap: () -> Void

    @ScaledMetric(relativeTo: .footnote) private var rowHeight: CGFloat = NKTimelineMetrics.transferRowHeight

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            Color.clear.frame(width: NKTimelineMetrics.timeColumnWidth + 2)
            Color.clear.frame(width: NKTimelineMetrics.railColumnWidth)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: "figure.walk")
                        .foregroundStyle(NKColor.textSecondary)
                        .accessibilityHidden(true)
                    Text(transferText)
                        .font(.footnote)
                        .foregroundStyle(NKColor.textSecondary)
                    Spacer(minLength: 4)
                    Button(action: onShowStationMap) {
                        Text("駅の地図", bundle: .module)
                            .font(.footnote)
                            .foregroundStyle(NKColor.accent)
                            .frame(minHeight: NKSpacing.minTapTarget)
                    }
                    .buttonStyle(.plain)
                }
                ForEach(warnings, id: \.self) { warning in
                    Text(warning.message)
                        .font(.caption)
                        .foregroundStyle(NKColor.textSecondary)
                }
            }
            .padding(.leading, 4)
        }
        .frame(minHeight: rowHeight)
        .background(alignment: .topLeading) {
            RailColumn(above: .dotted, below: .dotted, node: nil)
                .padding(.leading, NKTimelineMetrics.timeColumnWidth + 2)
        }
    }

    private var transferText: String {
        if let walk = transfer.walkMinutes {
            return String(localized: "乗換 \(transfer.totalMinutes)分（徒歩 約\(walk)分）", bundle: .module)
        }
        return String(localized: "乗換 \(transfer.totalMinutes)分", bundle: .module)
    }
}
