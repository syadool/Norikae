import SwiftUI

// MARK: - カード

public extension View {
    /// 白いカード（角丸 `xl`、design-spec 4 章）
    func nkCard(radius: CGFloat = NKRadius.xl, fill: Color = NKColor.surface) -> some View {
        background(fill, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }

    /// 画面の地
    func nkScreenBackground() -> some View {
        background(NKColor.background.ignoresSafeArea())
    }
}

/// カードの見出し（カードとの間は 8）
public struct SectionHeader: View {
    private let title: String
    private let trailing: AnyView?

    public init(_ title: String) {
        self.title = title
        self.trailing = nil
    }

    public init<Trailing: View>(_ title: String, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.trailing = AnyView(trailing())
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(NKColor.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            trailing
        }
        .padding(.horizontal, 4)
        .padding(.bottom, NKSpacing.sectionTitleGap)
    }
}

// MARK: - ボタン

/// 主ボタン（高さ 52〜54、横幅いっぱい、角丸 `md`）
public struct NKPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(NKColor.onAccent)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(NKColor.accentFill.opacity(isEnabled ? 1 : 0.4), in: RoundedRectangle(cornerRadius: NKRadius.md, style: .continuous))
            .opacity(configuration.isPressed ? 0.8 : 1)
            .contentShape(RoundedRectangle(cornerRadius: NKRadius.md, style: .continuous))
    }
}

/// 二次ボタン（1本前・1本後など。枠は `border`）
public struct NKSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(isEnabled ? NKColor.accent : NKColor.textTertiary)
            .frame(maxWidth: .infinity, minHeight: NKSpacing.minTapTarget)
            .background(NKColor.surface, in: RoundedRectangle(cornerRadius: NKRadius.md, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: NKRadius.md, style: .continuous)
                    .strokeBorder(NKColor.border, lineWidth: 1)
            }
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(RoundedRectangle(cornerRadius: NKRadius.md, style: .continuous))
    }
}

/// 丸いアイコンボタン（入れ替えボタンなど。44×44）
public struct NKCircleIconButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(NKColor.accent)
            .frame(width: NKSpacing.minTapTarget, height: NKSpacing.minTapTarget)
            .background(NKColor.fillPill, in: Circle())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

// MARK: - セグメントピッカー

/// セグメントピッカー（高さ 36、溝の内側の余白 2、つまみは capsule、design-spec 4 章・6 章）
public struct NKSegmentedPicker<Value: Hashable>: View {
    public struct Option: Identifiable {
        public var value: Value
        public var title: String
        public var id: Value { value }

        public init(_ value: Value, _ title: String) {
            self.value = value
            self.title = title
        }
    }

    @Binding private var selection: Value
    private let options: [Option]
    /// 選べない値（非対応の条件など。隠さずに選べない状態で出す、FR-CAP-02）
    private let disabled: Set<Value>
    @Namespace private var namespace
    @ScaledMetric(relativeTo: .footnote) private var height: CGFloat = 36

    public init(selection: Binding<Value>, options: [Option], disabled: Set<Value> = []) {
        _selection = selection
        self.options = options
        self.disabled = disabled
    }

    public var body: some View {
        HStack(spacing: 0) {
            ForEach(options) { option in
                let isSelected = option.value == selection
                let isDisabled = disabled.contains(option.value)
                Button {
                    withAnimation(.snappy(duration: 0.2)) { selection = option.value }
                } label: {
                    Text(option.title)
                        .font(.footnote.weight(isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? NKColor.textPrimary : (isDisabled ? NKColor.textTertiary.opacity(0.6) : NKColor.textSecondary))
                        .strikethrough(isDisabled)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity, minHeight: height - 4)
                        .background {
                            if isSelected {
                                Capsule()
                                    .fill(NKColor.surfaceRaised)
                                    .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
                                    .matchedGeometryEffect(id: "thumb", in: namespace)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(isDisabled)
                .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
            }
        }
        .padding(2)
        .background(NKColor.fillTrack, in: RoundedRectangle(cornerRadius: NKRadius.lg, style: .continuous))
    }
}

// MARK: - リストの行

/// カードの中の行（高さ 48〜52、右端に「›」）
public struct NKRow<Content: View>: View {
    private let showsChevron: Bool
    private let content: Content

    public init(showsChevron: Bool = true, @ViewBuilder content: () -> Content) {
        self.showsChevron = showsChevron
        self.content = content()
    }

    public var body: some View {
        HStack(spacing: 10) {
            content
            Spacer(minLength: 0)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(NKColor.iconChevron)
                    .accessibilityHidden(true)
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 12)
        .frame(minHeight: 50)
        .contentShape(Rectangle())
    }
}

/// カードの中の区切り線
public struct NKDivider: View {
    private let leading: CGFloat

    public init(leading: CGFloat = 16) {
        self.leading = leading
    }

    public var body: some View {
        Rectangle()
            .fill(NKColor.separator)
            .frame(height: 1)
            .padding(.leading, leading)
    }
}
