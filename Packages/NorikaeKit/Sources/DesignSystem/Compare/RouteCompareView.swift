import Domain
import SwiftUI

/// 縦比較の 1 列分のデータ
public struct CompareColumn: Identifiable, Hashable, Sendable {
    public var route: Route
    public var badges: [RouteBadge]
    public var fare: FareDisplay

    public var id: Route.ID { route.id }

    public init(route: Route, badges: [RouteBadge], fare: FareDisplay) {
        self.route = route
        self.badges = badges
        self.fare = fare
    }

    /// VoiceOver で読む内容（NFR-A11Y-03）：「経路1、8時14分発、8時48分着、34分、乗換0回、836円」
    public func accessibilityLabel(index: Int) -> String {
        var parts = [
            String(localized: "経路\(index + 1)", bundle: .module),
            String(localized: "\(NKFormat.spokenTime(route.departureTime))発", bundle: .module),
            String(localized: "\(NKFormat.spokenTime(route.arrivalTime))着", bundle: .module),
            NKFormat.duration(minutes: route.durationMinutes),
            NKFormat.transfers(route.transferCount),
            NKFormat.fare(fare),
        ]
        parts.append(contentsOf: badges.map(RouteBadgeView.accessibilityText(for:)))
        if route.hasServiceDisruption {
            parts.append(String(localized: "遅延の影響あり", bundle: .module))
        }
        return parts.joined(separator: "、")
    }
}

/// 縦比較（design-spec 7.4、FR-CMP）
///
/// - 3 列を画面内に固定し、4 本目以降は横スクロール。時間軸は固定し、列（要約と本体）だけをスクロールする
/// - 全ての列で縦の時間軸を共通にし、1 分あたりの高さは使える高さから自動で決める
/// - 列の要約と本体を合わせて 1 つのボタンにする
public struct RouteCompareView: View {
    private let columns: [CompareColumn]
    private let catalog: Catalog
    private let onSelect: (Route.ID) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .callout) private var scaledHeaderHeight: CGFloat = NKCompareMetrics.headerCardSize
    private let headerGap: CGFloat = 8

    private var headerHeight: CGFloat {
        NKCompareMetrics.headerHeight(scaled: scaledHeaderHeight, dynamicTypeSize: dynamicTypeSize)
    }

    public init(columns: [CompareColumn], catalog: Catalog, onSelect: @escaping (Route.ID) -> Void) {
        self.columns = columns
        self.catalog = catalog
        self.onSelect = onSelect
    }

    public var body: some View {
        GeometryReader { geometry in
            let gutter = NKCompareMetrics.axisGutterWidth
            let columnWidth = max((geometry.size.width - gutter) / CGFloat(NKCompareMetrics.visibleColumnCount), 96)
            let bodyHeight = max(geometry.size.height - headerHeight - headerGap, 220)
            if let axis = TimeAxis(routes: columns.map(\.route)) {
                let metrics = CompareAxisMetrics(axis: axis, bodyHeight: bodyHeight)
                ZStack(alignment: .topLeading) {
                    CompareBodyBackground(ticks: metrics.tickPositions)
                        .frame(width: geometry.size.width, height: bodyHeight)
                        .offset(y: headerHeight + headerGap)

                    HStack(alignment: .top, spacing: 0) {
                        CompareAxisLabels(ticks: metrics.tickPositions, width: gutter)
                            .dynamicTypeSize(...NKCompareMetrics.axisMaxTypeSize)
                            .frame(width: gutter, height: bodyHeight)
                            .padding(.top, headerHeight + headerGap)
                            .accessibilityHidden(true)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(alignment: .top, spacing: 0) {
                                ForEach(Array(columns.enumerated()), id: \.element.id) { index, column in
                                    Button {
                                        onSelect(column.id)
                                    } label: {
                                        VStack(spacing: headerGap) {
                                            CompareHeaderCard(column: column)
                                                .dynamicTypeSize(...NKCompareMetrics.headerMaxTypeSize)
                                                .frame(width: columnWidth - 6, height: headerHeight)
                                            CompareColumnBody(
                                                column: column, catalog: catalog, metrics: metrics,
                                                width: columnWidth, height: bodyHeight, showsSeparator: index > 0
                                            )
                                            .dynamicTypeSize(...NKCompareMetrics.bodyMaxTypeSize)
                                        }
                                        .frame(width: columnWidth)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(CompareColumnButtonStyle())
                                    .accessibilityElement(children: .ignore)
                                    .accessibilityLabel(Text(column.accessibilityLabel(index: index)))
                                    .accessibilityHint(Text("経路の詳細を開きます", bundle: .module))
                                    .accessibilityAddTraits(.isButton)
                                    .accessibilityIdentifier("compareColumn-\(index)")
                                }
                            }
                            .scrollTargetLayout()
                        }
                        .scrollTargetBehavior(.viewAligned)
                    }
                }
            }
        }
    }
}

/// 時間軸の寸法の計算結果
struct CompareAxisMetrics: Hashable {
    let axis: TimeAxis
    let pointsPerMinute: Double
    let padding: Double
    let tickPositions: [TickPosition]

    struct TickPosition: Hashable {
        var date: Date
        var y: CGFloat
    }

    init(axis: TimeAxis, bodyHeight: CGFloat) {
        self.axis = axis
        padding = NKCompareMetrics.axisVerticalPadding
        pointsPerMinute = axis.pointsPerMinute(contentHeight: bodyHeight, verticalPadding: padding)
        let interval = TimeAxis.tickInterval(
            pointsPerMinute: pointsPerMinute, minimumSpacing: NKCompareMetrics.minTickSpacing,
            candidates: NKCompareMetrics.tickIntervalCandidates
        )
        let axis = axis, ppm = pointsPerMinute, pad = padding
        tickPositions = axis.ticks(intervalMinutes: interval, pointsPerMinute: ppm, verticalPadding: pad)
            .map { TickPosition(date: $0, y: axis.y(for: $0, pointsPerMinute: ppm, verticalPadding: pad)) }
            .filter { $0.y >= 0 && $0.y <= bodyHeight }
    }

    func y(_ date: Date) -> CGFloat {
        axis.y(for: date, pointsPerMinute: pointsPerMinute, verticalPadding: padding)
    }
}

/// 本体のカードと目盛り線（スクロールしない）
struct CompareBodyBackground: View {
    let ticks: [CompareAxisMetrics.TickPosition]

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: NKRadius.xl, style: .continuous)
                .fill(NKColor.surface)
            Canvas { context, size in
                for tick in ticks {
                    var path = Path()
                    path.move(to: CGPoint(x: NKCompareMetrics.axisGutterWidth, y: tick.y))
                    path.addLine(to: CGPoint(x: size.width, y: tick.y))
                    context.stroke(path, with: .color(NKColor.gridline), lineWidth: 1)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: NKRadius.xl, style: .continuous))
    }
}

/// 時間軸の目盛りのラベル（右寄せ）
struct CompareAxisLabels: View {
    let ticks: [CompareAxisMetrics.TickPosition]
    let width: CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(ticks, id: \.date) { tick in
                Text(NKFormat.time(tick.date))
                    .font(.nkNumeric(.caption2, weight: .regular))
                    .foregroundStyle(NKColor.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(width: width - 6, alignment: .trailing)
                    .position(x: (width - 6) / 2, y: tick.y)
            }
        }
    }
}

/// 列の要約（104×104、角丸 lg、内側の余白 8）
///
/// アクセシビリティサイズでは列の幅に 1 行で収まらないので、「出発→」「到着」、所要時間、乗換回数を 1 行ずつに分ける（design-spec 5.2）
struct CompareHeaderCard: View {
    let column: CompareColumn

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let stacked = dynamicTypeSize.isAccessibilitySize
        VStack(alignment: .leading, spacing: 3) {
            RouteBadgeRow(badges: column.badges, hasDisruption: column.route.hasServiceDisruption)
                .dynamicTypeSize(...(stacked ? NKCompareMetrics.accessibilityBadgeMaxTypeSize : .accessibility5))
                .frame(minHeight: 20, alignment: .leading)
            Group {
                if stacked {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("\(NKFormat.time(column.route.departureTime))→", bundle: .module)
                        Text(NKFormat.time(column.route.arrivalTime))
                    }
                } else {
                    Text("\(NKFormat.time(column.route.departureTime))→\(NKFormat.time(column.route.arrivalTime))", bundle: .module)
                }
            }
            .font(.nkNumeric(.callout))
            .foregroundStyle(NKColor.textPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            Group {
                if stacked {
                    Text(NKFormat.duration(minutes: column.route.durationMinutes)).fontWeight(.bold)
                    Text(NKFormat.transfers(column.route.transferCount))
                } else {
                    HStack(spacing: 4) {
                        Text(NKFormat.duration(minutes: column.route.durationMinutes)).fontWeight(.bold)
                        Text(NKFormat.transfers(column.route.transferCount))
                    }
                }
            }
            .font(.caption)
            .foregroundStyle(NKColor.textSecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            Text(NKFormat.fare(column.fare))
                .font(.caption)
                .foregroundStyle(NKColor.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .nkCard(radius: NKRadius.lg)
    }
}

/// 列の本体（帯・チップ・種別と行き先・発着のラベル・乗換の点線）
struct CompareColumnBody: View {
    let column: CompareColumn
    let catalog: Catalog
    let metrics: CompareAxisMetrics
    let width: CGFloat
    let height: CGFloat
    let showsSeparator: Bool

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// 発着のラベルどうしが重なる間隔。アクセシビリティサイズでは時刻の文字の高さに合わせて広げる
    @ScaledMetric(relativeTo: .footnote) private var scaledLabelSpacing: CGFloat = 16
    /// 時刻の横に駅名を出すのに最低限要る幅（駅名 1 文字分ほど）。これより狭いときは駅名を省く
    @ScaledMetric(relativeTo: .caption2) private var minimumStationNameWidth: CGFloat = 16

    var body: some View {
        let isAccessibilitySize = dynamicTypeSize.isAccessibilitySize
        let layout = CompareColumnLayout(
            route: column.route, axis: metrics.axis, pointsPerMinute: metrics.pointsPerMinute,
            verticalPadding: metrics.padding, collapseDistance: NKCompareMetrics.labelCollapseDistance,
            minimumLabelSpacing: isAccessibilitySize ? scaledLabelSpacing : 16
        )
        let bandCenterX = NKCompareMetrics.bandLeading + NKCompareMetrics.bandWidth / 2
        let labelWidth = max(width - NKCompareMetrics.labelLeading - 4, 30)
        let labelCenterX = NKCompareMetrics.labelLeading + labelWidth / 2

        ZStack(alignment: .topLeading) {
            if showsSeparator {
                Rectangle().fill(NKColor.gridline).frame(width: 1, height: height)
            }

            // 乗換・待ち時間の点線
            Canvas { context, _ in
                for connector in layout.connectors {
                    var path = Path()
                    path.move(to: CGPoint(x: bandCenterX, y: connector.top))
                    path.addLine(to: CGPoint(x: bandCenterX, y: connector.bottom))
                    context.stroke(
                        path, with: .color(NKColor.connectorTransfer),
                        style: StrokeStyle(lineWidth: NKCompareMetrics.transferLineWidth, lineCap: .round, dash: [2, 4])
                    )
                }
            }
            .frame(width: width, height: height)

            // 乗車区間の帯
            ForEach(layout.bands, id: \.legIndex) { band in
                let appearance = LineAppearance(line: catalog.line(band.leg.lineId), fallbackID: band.leg.lineId)
                Capsule()
                    .fill(appearance.color)
                    .frame(width: NKCompareMetrics.bandWidth, height: max(band.height, NKCompareMetrics.bandWidth))
                    .offset(x: NKCompareMetrics.bandLeading, y: band.top)
            }

            // 種別・行き先（チップと同じ高さ）
            ForEach(layout.bands, id: \.legIndex) { band in
                if band.height >= 52, !appearance(band).isLongLabel {
                    legLabel(band.leg)
                        .frame(width: labelWidth, alignment: .leading)
                        .position(x: labelCenterX, y: band.midY)
                }
            }

            // 路線記号チップ（帯の縦方向の中央。帯からはみ出してよい）
            ForEach(layout.bands, id: \.legIndex) { band in
                let line = appearance(band)
                if line.isLongLabel {
                    // 路線名で代わりに表示するチップは幅が広く、横に置いた種別・行き先に重なる。
                    // 列の左端から置き、種別・行き先はチップの右に入るときだけ出す
                    Group {
                        if band.height >= 52 {
                            ViewThatFits(in: .horizontal) {
                                HStack(spacing: 4) {
                                    chip(line)
                                    legLabel(band.leg)
                                }
                                chip(line)
                            }
                        } else {
                            chip(line)
                        }
                    }
                    .frame(width: width - 6, alignment: .leading)
                    .position(x: 2 + (width - 6) / 2, y: band.midY)
                } else {
                    chip(line)
                        .position(x: bandCenterX, y: band.midY)
                }
            }

            // 発着の時刻と駅名
            ForEach(Array(layout.labels.enumerated()), id: \.offset) { _, label in
                Group {
                    // 大きい文字サイズでは駅名を省き、時刻だけにする（design-spec 5.2）
                    if label.showsStationName, !isAccessibilitySize {
                        // 時刻と駅名が列に入らないとき（XXXL など）は、時刻が「8:…」と切れないよう駅名を省く。
                        // 駅名は理想の幅を最低限の幅にし、入るときは今までどおり駅名の後ろを「…」で切る
                        ViewThatFits(in: .horizontal) {
                            HStack(alignment: .firstTextBaseline, spacing: 3) {
                                timeText(label)
                                Text(catalog.station(label.stationId)?.name ?? "")
                                    .font(.caption2)
                                    .foregroundStyle(NKColor.textSecondary)
                                    .frame(idealWidth: minimumStationNameWidth, alignment: .leading)
                            }
                            timeText(label)
                        }
                    } else {
                        timeText(label)
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: labelWidth, alignment: .leading)
                .position(x: labelCenterX, y: label.y)
            }
        }
        .frame(width: width, height: height, alignment: .topLeading)
    }

    private func timeText(_ label: CompareColumnLayout.TimeLabel) -> some View {
        Text(NKFormat.time(label.time))
            .font(.nkNumeric(.footnote))
            .foregroundStyle(NKColor.textPrimary)
    }

    private func appearance(_ band: CompareColumnLayout.Band) -> LineAppearance {
        LineAppearance(line: catalog.line(band.leg.lineId), fallbackID: band.leg.lineId)
    }

    private func chip(_ appearance: LineAppearance) -> some View {
        LineSymbolChip(appearance, size: .compare)
            .dynamicTypeSize(...(dynamicTypeSize.isAccessibilitySize ? NKCompareMetrics.accessibilityChipMaxTypeSize : .accessibility5))
    }

    @ViewBuilder
    private func legLabel(_ leg: TrainLeg) -> some View {
        let type = catalog.trainType(leg.trainTypeId)
        VStack(alignment: .leading, spacing: 1) {
            Text(type?.name ?? "")
                .font(.caption2.weight(.bold))
                .foregroundStyle(trainTypeColor(type))
            if let delay = leg.delayMinutes, delay > 0 {
                Text(NKFormat.delay(minutes: delay))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(NKColor.delayText)
            } else if !dynamicTypeSize.isAccessibilitySize {
                // 大きい文字サイズでは 2 行目（行き先）を省く（design-spec 5.2）
                Text(leg.destinationName)
                    .font(.caption2)
                    .foregroundStyle(NKColor.textSecondary)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
}

/// 列を押したときの見た目
struct CompareColumnButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

/// 縦比較のスケルトン（FR-CMP-11）。同じ骨組みのまま、帯とラベルを灰色の角丸の四角にする
public struct RouteCompareSkeleton: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .callout) private var scaledHeaderHeight: CGFloat = NKCompareMetrics.headerCardSize

    private var headerHeight: CGFloat {
        NKCompareMetrics.headerHeight(scaled: scaledHeaderHeight, dynamicTypeSize: dynamicTypeSize)
    }

    public init() {}

    public var body: some View {
        GeometryReader { geometry in
            let gutter = NKCompareMetrics.axisGutterWidth
            let columnWidth = (geometry.size.width - gutter) / CGFloat(NKCompareMetrics.visibleColumnCount)
            let bodyHeight = max(geometry.size.height - headerHeight - 8, 220)
            let bands: [(top: CGFloat, height: CGFloat)] = [(0.08, 0.55), (0.05, 0.25), (0.02, 0.5)]
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 0) {
                    Color.clear.frame(width: gutter)
                    ForEach(0..<3, id: \.self) { _ in
                        VStack(alignment: .leading, spacing: 8) {
                            SkeletonBlock(width: 44, height: 16)
                            SkeletonBlock(width: 70, height: 14)
                            SkeletonBlock(width: 56, height: 10)
                            SkeletonBlock(width: 40, height: 10)
                            Spacer(minLength: 0)
                        }
                        .padding(8)
                        .frame(width: columnWidth - 6, height: headerHeight, alignment: .topLeading)
                        .nkCard(radius: NKRadius.lg)
                        .frame(width: columnWidth)
                    }
                }
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: NKRadius.xl, style: .continuous).fill(NKColor.surface)
                    HStack(alignment: .top, spacing: 0) {
                        VStack(alignment: .trailing, spacing: 48) {
                            ForEach(0..<5, id: \.self) { _ in SkeletonBlock(width: 24, height: 8) }
                        }
                        .frame(width: gutter)
                        .padding(.top, 12)
                        ForEach(0..<3, id: \.self) { index in
                            ZStack(alignment: .topLeading) {
                                SkeletonBlock(width: NKCompareMetrics.bandWidth, height: bodyHeight * bands[index].height, radius: NKCompareMetrics.bandWidth / 2)
                                    .offset(x: NKCompareMetrics.bandLeading, y: bodyHeight * bands[index].top)
                                SkeletonBlock(width: 50, height: 10)
                                    .offset(x: NKCompareMetrics.labelLeading, y: bodyHeight * bands[index].top)
                                SkeletonBlock(width: 44, height: 10)
                                    .offset(x: NKCompareMetrics.labelLeading, y: bodyHeight * (bands[index].top + bands[index].height) - 10)
                            }
                            .frame(width: columnWidth, height: bodyHeight, alignment: .topLeading)
                        }
                    }
                }
                .frame(height: bodyHeight)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("経路を検索しています", bundle: .module))
    }
}
