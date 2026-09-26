import Feature
import LiveGuidance
import SwiftUI

@main
struct NorikaeApp: App {
    @State private var dependencies: AppDependencies

    init() {
        let dependencies = AppDependencies.makeFromLaunchEnvironment()
        _dependencies = State(initialValue: dependencies)
        // LiveActivityIntent（「1本後に変更」「案内終了」）はアプリ本体のプロセスで実行される（frontend.md 9.2）
        GuidanceIntentBridge.shared.handler = dependencies.guidance
    }

    var body: some Scene {
        WindowGroup {
            NorikaeRootView()
                .environment(dependencies)
        }
    }
}
