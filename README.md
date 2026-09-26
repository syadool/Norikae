# Norikae（iOS フロントエンド）

乗り換え案内アプリ Norikae の iOS フロントエンド。要件・設計は [docs/](docs/) を参照。

- [フロントエンド要件定義書](docs/requirements/frontend.md)
- [API 要件定義書](docs/requirements/api-contract.md)
- [デザイン仕様書](docs/design/design-spec.md)

バックエンドはこのリポジトリの対象外。API の実装ができるまでは、モックの Repository で動く。

## 必要なもの

- macOS ＋ 最新安定版の Xcode（iOS 18 SDK、Swift 6）
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)（`brew install xcodegen`）

## 始め方

```bash
xcodegen generate
open Norikae.xcodeproj
```

`Norikae` スキームを iPhone のシミュレーターで実行する。Info.plist の `NorikaeAPIBaseURL` が空のあいだは、モックで動く。

実機・TestFlight では、`project.yml` のバンドル ID・App Group（`group.com.example.norikae`）・iCloud コンテナ（`iCloud.com.example.norikae`）を自分のチームの値に置き換える。App Group の ID は `AppGroupGuidanceSessionStore.defaultAppGroup` と合わせる。

### モックの場面を切り替える

スキームの起動引数に `-UseMockData -MockScenario <名前>` を付ける。名前は `MockScenario`（[MockData.swift](Packages/NorikaeKit/Sources/NorikaeData/Mock/MockData.swift)）の値で、api-contract 7 章の場面に対応する。池袋 → 横浜で検索すると、場面ごとに作り込んだ経路が返る。

| 起動引数 | 内容 |
| --- | --- |
| `-UseMockData` | モックを使う |
| `-MockScenario standard` など | 場面を選ぶ（`threeRoutes`、`wideSpread`、`overnight`、`manyTransfers`、`missingOptional`、`retryableError`、`nonRetryableError`、`empty`、`slow`、`noSymbolLine`、`fareVariants`、`partialStale`、`featureUnavailable`、`contextExpired`、`adjacentStructureChange`） |
| `-ResetUserData` | 設定・お気に入り・履歴を消して始める（UI テスト用） |
| `-Region kanto` | 主に使う地域を決めて、オンボーディングを飛ばす |

## 構成

```
App/                  アプリ本体（エントリポイント、entitlements、Privacy Manifest）
NorikaeWidget/        Widget Extension（Live Activity・Dynamic Island・Watch のスマートスタック）
Shared/               アプリと Widget Extension の両方でコンパイルする LiveActivityIntent
NorikaeUITests/       UI テスト（検索 → 縦比較 → 経路詳細 → 案内開始）
Packages/NorikaeKit/  Swift Package（下表）
project.yml           XcodeGen の定義
```

| モジュール | 責務（frontend.md 9.2） |
| --- | --- |
| `Domain` | モデル、Repository のプロトコル、時間軸・「早・楽・安」・運賃表示・同一経路の照合・リマインド時刻などの純粋なロジック |
| `NorikaeData` | API クライアント（匿名認証・トークン更新）、本物の Repository、モック、SwiftData、キャッシュ、同梱の駅マスタと駅検索。文書上の `Data` モジュール（Foundation の `Data` 型と名前が衝突するため改名） |
| `DesignSystem` | トークン（[DesignTokens.swift](docs/design/DesignTokens.swift) を移したもの）、路線記号チップ、バッジ、運行状況の札、非対応・情報なしの表示、縦比較・縦タイムラインの描画部品 |
| `LiveGuidance` | `ActivityAttributes`、ロック画面・Dynamic Island・Watch の表示、インテントとアプリをつなぐ部品 |
| `Feature` | 画面ごとの View と ViewModel、案内（Live Activity）の制御、位置情報・徒歩時間・通知 |

## テスト

```bash
cd Packages/NorikaeKit
xcodebuild test -scheme NorikaeKit-Package -destination 'platform=iOS Simulator,name=iPhone 16'
```

| ターゲット | 内容 |
| --- | --- |
| `DomainTests` | 時間軸、日付をまたぐ時刻、乗換回数、「早・楽・安」、運賃の表示と「安」の条件、路線記号の代替表示、同一経路の照合、1 本後の構成変更、リマインド時刻、Live Activity の進行、祝日・曜日区分 |
| `DataTests` | 契約テスト（fixture のデコード、`ContentState` の JSON 例）、API クライアントの認証の流れ、駅検索、SwiftData、キャッシュ、モックの各場面 |
| `FeatureTests` | ViewModel（縦比較・経路詳細・検索フォーム）、エラーの見せ方 |
| `SnapshotTests` | 縦比較、縦タイムライン、Live Activity（ロック画面・Dynamic Island・Watch）、非対応・情報なしの表示。ライト・ダーク・Dynamic Type |

スナップショットテストは、初回の実行で参照画像を記録して失敗する。iPhone 16（iOS 18）のシミュレーターで記録し、`__Snapshots__` をコミットする。

UI テストは `Norikae` スキームで実行する。CI は [.github/workflows/ios.yml](.github/workflows/ios.yml)。

## バックエンドとの契約について

API の呼び出しは、バックエンドの `backend/openapi.json`（v0.1.0）の形に合わせている。契約が変わったら次の場所を直す。

- エンドポイントごとの応答の形：[RemoteRepositories.swift](Packages/NorikaeKit/Sources/NorikaeData/API/RemoteRepositories.swift) の冒頭のコメント
- 認証（インストール登録・トークン更新）：[APIClient.swift](Packages/NorikaeKit/Sources/NorikaeData/API/APIClient.swift)
- 駅マスタの差分（API-08）：[MasterDataChangesPayload.swift](Packages/NorikaeKit/Sources/NorikaeData/API/MasterDataChangesPayload.swift)。同梱の [StationMaster.json](Packages/NorikaeKit/Sources/NorikaeData/Resources/StationMaster.json) は開発用のサンプル（version 0）で、本番は `GET /v1/master-data/snapshot` から作る
- 契約テストの fixture：[Tests/DataTests/Fixtures](Packages/NorikaeKit/Tests/DataTests/Fixtures)。バックエンドと共有する fixture ができたら置き換える

## まだ実装していないもの・仮の決め

| 内容 | 状況 |
| --- | --- |
| 簡単な Watch アプリ（FR-WCH-02） | MVP後半のため未着手。Live Activity のスマートスタック表示（FR-WCH-01）は対応済み |
| 歩く速さの補正値（frontend.md 14 章 #4） | ゆっくり ×1.25・普通 ×1.0・速い ×0.85 の仮の値 |
| 「非対応」「情報なし」「時刻表どおりの表示」の文言（14 章 #7） | `UnsupportedText`（DesignSystem）にまとめた案 |
| 構成が変わる「1本後に変更」をバックグラウンドから開始し直せるか（14 章 #6） | 開始できなければ「アプリを開いて案内し直してください」と表示する。実機で要検証 |
| 設定値の iCloud 同期 | お気に入り・履歴・マイ路線のみ同期。設定値は端末内（UserDefaults） |
| アプリのアイコン | 未定（14 章 #5） |
