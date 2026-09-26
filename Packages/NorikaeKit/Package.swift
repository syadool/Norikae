// swift-tools-version: 6.0
//
// Norikae のフロントエンド共通パッケージ（frontend.md 9.2 のモジュール構成）。
//
// - Domain:       モデル、Repository のプロトコル、時間軸・バッジなどの純粋なロジック
// - NorikaeData:  Repository の実装（API クライアント・モック）、SwiftData、キャッシュ、駅マスタ
//                 ※ 文書上の名前は `Data`。Foundation の `Data` 型と衝突するため、モジュール名だけ変えている
// - DesignSystem: トークン、路線記号チップ・バッジ・非対応表示などの共通部品、縦比較・タイムラインの描画部品
// - LiveGuidance: Live Activity の Attributes・画面・LiveActivityIntent（アプリと Widget Extension で共有）
// - Feature:      画面ごとの View と ViewModel

import PackageDescription

let package = Package(
    name: "NorikaeKit",
    defaultLocalization: "ja",
    platforms: [.iOS(.v18), .watchOS(.v11)],
    products: [
        .library(name: "Domain", targets: ["Domain"]),
        .library(name: "NorikaeData", targets: ["NorikaeData"]),
        .library(name: "DesignSystem", targets: ["DesignSystem"]),
        .library(name: "LiveGuidance", targets: ["LiveGuidance"]),
        .library(name: "Feature", targets: ["Feature"]),
    ],
    dependencies: [
        // テスト専用（NFR-05）。スナップショットテストにのみ使う
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.17.0"),
    ],
    targets: [
        .target(name: "Domain"),
        .target(
            name: "NorikaeData",
            dependencies: ["Domain"],
            resources: [.process("Resources")]
        ),
        .target(
            name: "DesignSystem",
            dependencies: ["Domain"],
            resources: [.process("Resources")]
        ),
        .target(
            name: "LiveGuidance",
            dependencies: ["Domain", "DesignSystem"],
            resources: [.process("Resources")]
        ),
        .target(
            name: "Feature",
            dependencies: ["Domain", "NorikaeData", "DesignSystem", "LiveGuidance"],
            resources: [.process("Resources")]
        ),
        .testTarget(name: "DomainTests", dependencies: ["Domain"]),
        .testTarget(
            name: "DataTests",
            dependencies: ["NorikaeData", "Domain", "LiveGuidance"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(name: "FeatureTests", dependencies: ["Feature", "NorikaeData", "Domain", "DesignSystem"]),
        .testTarget(
            name: "SnapshotTests",
            dependencies: [
                "Feature", "DesignSystem", "LiveGuidance", "NorikaeData", "Domain",
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
