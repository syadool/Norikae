import DesignSystem
import Domain
import SwiftUI

/// 検索条件（FR-CND-01〜05）
struct ConditionsView: View {
    @Bindable var form: SearchFormModel
    let dependencies: AppDependencies

    @Environment(\.dismiss) private var dismiss
    @State private var isPickingVia = false

    private var region: Region { form.region(default: dependencies.settings.preferredRegion) }
    private var capabilities: CapabilitySnapshot { dependencies.capabilities.snapshot }
    private var supportsVia: Bool { capabilities.isSupported(.viaStations, region: region) }
    private var supportsFirstLast: Bool { capabilities.isSupported(.firstLastTrain, region: region) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    dateSection
                    viaSection
                    optionSection
                }
                .padding(.vertical, 12)
                .nkScreen()
            }
            .nkScreenBackground()
            .navigationTitle(String(localized: "検索条件", bundle: .module))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "完了", bundle: .module)) { dismiss() }
                }
            }
            .sheet(isPresented: $isPickingVia) {
                StationPickerView(title: String(localized: "経由駅", bundle: .module), dependencies: dependencies) { station in
                    if form.canAddVia, !form.via.contains(where: { $0.id == station.id }) { form.via.append(station) }
                }
            }
        }
    }

    // MARK: 日時

    private var dateSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(String(localized: "日時", bundle: .module))
            VStack(alignment: .leading, spacing: 12) {
                NKSegmentedPicker(
                    selection: $form.searchType,
                    options: SearchType.allCases.map { NKSegmentedPicker<SearchType>.Option($0, QueryText.searchTypeName($0)) },
                    disabled: supportsFirstLast ? [] : [.firstTrain, .lastTrain]
                )
                .accessibilityIdentifier("searchTypePicker")
                if !supportsFirstLast {
                    UnsupportedNotice(.firstLastTrain)
                }
                switch form.searchType {
                case .departure:
                    Toggle(String(localized: "今の時刻で検索", bundle: .module), isOn: $form.usesCurrentTime)
                        .font(.subheadline)
                    if !form.usesCurrentTime {
                        DatePicker(String(localized: "出発", bundle: .module), selection: $form.dateTime)
                            .environment(\.timeZone, JapanCalendar.timeZone)
                    }
                case .arrival:
                    DatePicker(String(localized: "到着", bundle: .module), selection: $form.dateTime)
                        .environment(\.timeZone, JapanCalendar.timeZone)
                case .firstTrain, .lastTrain:
                    DatePicker(String(localized: "日付", bundle: .module), selection: $form.dateTime, displayedComponents: .date)
                        .environment(\.timeZone, JapanCalendar.timeZone)
                }
            }
            .padding(NKSpacing.cardPadding)
            .nkCard()
        }
    }

    // MARK: 経由駅（最大 3 駅）

    private var viaSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(String(localized: "経由駅", bundle: .module))
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(form.via.enumerated()), id: \.element.id) { index, station in
                    NKRow(showsChevron: false) {
                        Text(station.name).font(.subheadline.weight(.bold))
                        Spacer()
                        Button {
                            form.via.remove(at: index)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(NKColor.textTertiary)
                                .frame(width: NKSpacing.minTapTarget, height: NKSpacing.minTapTarget)
                        }
                        .accessibilityLabel(Text("\(station.name)を外す", bundle: .module))
                    }
                    NKDivider()
                }
                Button {
                    isPickingVia = true
                } label: {
                    NKRow(showsChevron: false) {
                        Label {
                            Text("経由駅を追加（最大3駅）", bundle: .module)
                        } icon: {
                            Image(systemName: "plus.circle")
                        }
                        .font(.subheadline)
                        .foregroundStyle(supportsVia && form.canAddVia ? NKColor.accent : NKColor.textTertiary)
                    }
                }
                .buttonStyle(.plain)
                .disabled(!supportsVia || !form.canAddVia)
                if !supportsVia {
                    // 隠さずに、選べない状態と説明文で出す（FR-CAP-02）
                    UnsupportedNotice(.viaStations)
                        .padding([.horizontal, .bottom], 16)
                }
            }
            .nkCard()
        }
    }

    // MARK: 条件

    private var optionSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(String(localized: "条件", bundle: .module))
            VStack(alignment: .leading, spacing: 14) {
                Toggle(String(localized: "新幹線を使う", bundle: .module), isOn: $form.useShinkansen)
                Toggle(String(localized: "有料特急を使う", bundle: .module), isOn: $form.usePaidExpress)
                VStack(alignment: .leading, spacing: 6) {
                    Text("運賃", bundle: .module).font(.footnote).foregroundStyle(NKColor.textSecondary)
                    NKSegmentedPicker(selection: $form.fareKind, options: FareKind.allCases.map {
                        NKSegmentedPicker<FareKind>.Option($0, NKFormat.fareKindLabel($0))
                    })
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("並び替え", bundle: .module).font(.footnote).foregroundStyle(NKColor.textSecondary)
                    NKSegmentedPicker(selection: $form.sortOrder, options: RouteSortOrder.allCases.map {
                        NKSegmentedPicker<RouteSortOrder>.Option($0, QueryText.sortName($0))
                    })
                }
            }
            .font(.subheadline)
            .tint(NKColor.accentFill)
            .padding(NKSpacing.cardPadding)
            .nkCard()
        }
    }
}
