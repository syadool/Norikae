import DesignSystem
import Domain
import SwiftUI

/// アプリの最上位の画面。初回はオンボーディング、以降はタブ（frontend.md 4 章）
public struct NorikaeRootView: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.scenePhase) private var scenePhase
    @State private var didBootstrap = false

    public init() {}

    public var body: some View {
        Group {
            if dependencies.settings.region == nil {
                OnboardingView(settings: dependencies.settings)
            } else {
                MainTabView()
            }
        }
        .tint(NKColor.accent)
        .task {
            guard !didBootstrap else { return }
            didBootstrap = true
            await dependencies.bootstrap()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, didBootstrap else { return }
            Task { await dependencies.sceneDidBecomeActive() }
        }
        .onChange(of: dependencies.network.isOnline) { _, online in
            guard online else { return }
            Task { await dependencies.guidance.networkDidBecomeAvailable() }
        }
    }
}

/// タブ（経路検索・運行情報・時刻表・マイ）
struct MainTabView: View {
    @Environment(AppDependencies.self) private var dependencies

    var body: some View {
        @Bindable var router = dependencies.router
        TabView(selection: $router.selectedTab) {
            Tab(String(localized: "経路検索", bundle: .module), systemImage: "point.topleft.down.to.point.bottomright.curvepath", value: AppTab.search) {
                SearchTab()
            }
            Tab(String(localized: "運行情報", bundle: .module), systemImage: "waveform.path.ecg", value: AppTab.status) {
                StatusTab()
            }
            Tab(String(localized: "時刻表", bundle: .module), systemImage: "tablecells", value: AppTab.timetable) {
                TimetableTab()
            }
            Tab(String(localized: "マイ", bundle: .module), systemImage: "person", value: AppTab.my) {
                MyTab()
            }
        }
    }
}

/// 初回起動：主に使う地域の選択（FR-ONB-01〜03）。機能紹介は出さず、権限も要求しない
struct OnboardingView: View {
    let settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Spacer()
            VStack(alignment: .leading, spacing: 8) {
                Text("主に使う地域を選んでください", bundle: .module)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(NKColor.textPrimary)
                Text("駅の候補の並び順と、運行情報の最初の表示に使います。あとから設定で変更できます。", bundle: .module)
                    .font(.subheadline)
                    .foregroundStyle(NKColor.textSecondary)
            }
            VStack(spacing: 12) {
                ForEach(Region.allCases, id: \.self) { region in
                    Button {
                        settings.region = region
                    } label: {
                        HStack {
                            Text(QueryText.regionName(region))
                                .font(.title3.weight(.bold))
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                        .foregroundStyle(NKColor.textPrimary)
                        .padding(.horizontal, 20)
                        .frame(minHeight: 64)
                        .nkCard()
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("region-\(region.rawValue)")
                }
            }
            Spacer()
            Spacer()
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .nkScreenBackground()
    }
}
