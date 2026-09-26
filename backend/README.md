# Norikae バックエンド

TypeScript / Fastify / PostgreSQL による初期実装。変更対象はこの `backend/` ディレクトリのみ。既存のフロントエンド、Swift、モック、要件書は変更していない。

RapidAPI接続を追加：登録済みは **NAVITIME Transport / Free**。駅検索CLIと、別途Route(totalnavi)登録後に利用する概算経路APIを実装。キー設定・接続確認は [RAPIDAPI.md](RAPIDAPI.md) を参照。ODPTはユーザー申込済み・承認待ち。

## 設計の読み取りと実装判断

`docs/design/README.md` から参照される設計三文書と `docs/requirements/api-contract.md` v1.1 案を読み、実装可能と判断した。ユーザーの実装指示に基づき、以下をバックエンド側の初期契約として具体化した。設計文書に残る「合意待ち」を、フロント側まで合意済みという扱いにはしていない。

- `stopList`、地域別 `viaStations` / `firstLastTrain`、`RouteWarning` は v1.1 案を採用。
- `routeContext` は30分有効。AES-256-GCM の認証付き暗号で改ざんを検知し、検索条件や経路を外から読めない不透明な値にする。発行端末に束縛する。
- アクセストークン15分、更新トークン30日。更新時に旧更新トークンを失効させる。
- 監視用 `legs` は `lineId`, 任意の `trainRunId`, `serviceDate`, `from/to: {stationId, scheduledTime}`。OpenAPI に完全な形を記載。
- マスタは JSON スナップショットと、版番号付き upsert/delete の時系列差分。削除時に `replacedById` を返せる。
- Live Activity は全乗車区間を送信し、時刻は UNIX 秒。通常の進行は通知せず、実データ差分だけ送る。

## 実装済みの範囲

| 項目 | 状態 |
| --- | --- |
| API-01〜10、認証、capabilities、attributions | 全HTTPエンドポイント、入力検証、共通エラー、認証、出力スキーマ |
| 経路検索 | Provider interface、期限打切り、複数Providerの部分成功、重複除去、時系列・駅・種別・乗換時間検証 |
| ローカル検索 | 公開済みの全停車駅データから直通列車を検索。出発指定・到着指定、直前・直後の再探索 |
| 時刻表・停車駅・方面・運行情報 | 取込済みデータの配信。運行情報なし・期限切れは `unknown` |
| PostgreSQL | マイグレーション、認証、分散レート制限、マスタ差分、交通データ、暗号化Pushトークン、期限付き監視区間 |
| 取込 | 正規化済みJSONの検証と原子的公開、参照先・座標・時刻検証、失敗時に直前正常版を維持 |
| リアルタイム取込 | 正規化済み列車更新の検証、運行との照合、古い更新による巻戻し防止 |
| Live Activity | 冪等登録/解除、端末ごとの所有権、期限上限、更新差分、45秒集約、運休・既知番線変更の即時送信、APNs HTTP/2 adapter |
| 運用 | Docker/Compose、単発ジョブ、ヘルスチェック、OpenAPI、DBを含むローカルテスト |

**実交通データは同梱しない。起動するだけでは検索結果は得られない。** テスト内の架空データはテスト専用で、通常サーバーに自動投入しない。

## 未接続・未実装の範囲

本番利用できる完全な乗換案内サービスには、以下の追加作業が必要。

- Google Routes / ODPT と、NAVITIMEの実時刻表に基づくアダプターは未実装。RapidAPI版NAVITIMEの駅検索・概算経路の通信処理は実装済み。認証情報による実通信と契約の出典表示確認は未完了。
- GTFS ZIP/CSV と GTFS-RT protobuf の直接取込。現在は審査済みの正規化JSONを入力する。Canonical ID 対応、駅読み、休日区分などはデータ作成側で確定する必要がある。
- ローカルの乗換探索、経由駅、始発・終電、正確な運賃。初期ローカル検索は直通列車のみ。非対応条件は `FEATURE_UNAVAILABLE`。対応するProviderが検索して0件なら `ROUTE_NOT_FOUND`。
- App Attest。本実装はプライベート開発用。起動時に `DEPLOYMENT_MODE=private` を要求する。これはネットワークアクセス制御ではないため、Cloud Run は認証必須・非公開で運用する。
- 乗換不能の判定、APNs送達保証、実機での最終Swift型・静的ActivityAttributesとの合計サイズ検証。API-09は現段階では全監視区間の `tripUpdates=available` を要求する。一部区間だけ対応した経路の登録は未対応。
- 実データ品質の公表時刻との照合、取得スケジュール、予算アラート、Cloud Run配備、監視ダッシュボード。これらのクラウドリソースは作成していない。

capabilities に機能を設定する際はこの実装範囲に合わせる。未実装機能を `available` にしない。リアルタイム情報がない経路で `hasServiceDisruption=false` が返っても「平常確認済み」を意味しない。経路の `partial` / 警告と運行情報の `unknown` を併用する。

## ローカル起動

Node.js 22以上、PostgreSQL 17を想定。開発では Node.js 24 で検証。

```powershell
cd backend
npm ci
$env:ENCRYPTION_KEY = node -e "console.log(require('node:crypto').randomBytes(32).toString('base64'))"
docker compose up --build
```

DBとAPIの公開先は localhost のみ。ComposeはDBの正常起動後にマイグレーションを実行する。秘密鍵を永続運用する場合は Secret Manager 等へ保管し、全APIインスタンスとジョブで同じ値を使う。変更すると既存トークン・暗号化保存値を復号できなくなる。

Dockerを使わず既存PostgreSQLへ接続する場合：

```powershell
$env:DATABASE_URL = 'postgres://USER:PASSWORD@HOST:5432/norikae'
$env:DEPLOYMENT_MODE = 'private'
npm run migrate
npm run dev
```

`.env.example` は設定一覧。`dev:env` / `migrate:env` / `navitime` は `backend/.env` を読み込む。従来の `dev` / `migrate` / `start` は環境変数を直接設定する。TLSが必要な外部DBには提供元指定の検証付きTLS接続を設定する。証明書検証を無効化しない。

## APIと契約

`openapi.json` がこの実装のHTTP契約。起動後は `/openapi.json` でも取得できる。共通応答は `{meta, data}`、登録/解除は204。認証・ヘルスチェック・OpenAPI以外はBearer必須。

```powershell
$auth = Invoke-RestMethod -Method Post http://localhost:8080/v1/installations
$headers = @{Authorization="Bearer $($auth.accessToken)"}
Invoke-RestMethod http://localhost:8080/v1/capabilities -Headers $headers
Invoke-RestMethod http://localhost:8080/v1/master-data/snapshot -Headers $headers
```

`PUT/DELETE /v1/live-activities/{activityId}` には `Idempotency-Key` 必須。同じキー・同じ内容の再送は何もしない。内容が違う再利用は409。トークン変更には新しいキーを使う。履歴は24時間で破棄する。検索条件・位置・お気に入りをDBへ保存しない。

## データ公開とジョブ

`src/ingestion.ts` の `FeedBundle` が正規化ファイルの形式。`test/helpers.ts` に架空の最小例がある。`reviewedForPublication: true` は自動的な法的確認を意味せず、投入前の人による確認結果を記録するフラグ。

- `master` に stations / lines / operators / trainTypes を渡す。IDは事前に対応づけた安定Canonical ID。
- `documents` のキー：trainRun は `trainRunId:serviceDate`、directions は stationId、timetable は `stationId:lineId:directionId:dayType`、status / capability は lineId、regionCapability は地域。
- 各公開は当該Providerの交通文書スナップショットを置換する。残す文書も同梱する。マスタはupsertと明示deletions。失敗時は全体がロールバックする。
- 時刻はタイムゾーン付き実日時。深夜25:10は翌日01:10に変換して、元の運行日をserviceDateへ保持する。
- 日種別時刻表にも具体的な日付を含むため、対象運行日のデータを更新し、有効期限を日付に合わせる。カレンダーの自動展開は未実装。

```powershell
npx tsx src/jobs.ts publish reviewed-feed.json
npx tsx src/jobs.ts realtime PROVIDER_ID reviewed-trip-updates.json
npx tsx src/jobs.ts monitor
npx tsx src/jobs.ts cleanup
```

APNsには `APNS_TEAM_ID`, `APNS_KEY_ID`, `APNS_PRIVATE_KEY_FILE`, `APNS_BUNDLE_ID`, `APNS_ENVIRONMENT=sandbox|production`, `ENCRYPTION_KEY` が必要。実APNsを呼ぶのは `monitor` の実行時だけ。通常アラートは付与しない。失敗は次のジョブで再試行し、無効トークンは削除する。成功直後のDB障害では重複送信の可能性がある。

Cloud Schedulerから認証付きCloud Run Jobとして単発実行する。monitorは60秒、cleanupも定期実行し、遅くとも24時間以内に期限切れ行を消す。APIプロセスに常駐タイマーはない。ログ基盤の保持は30日以下に別途設定する。通常アクセスログを無効化し、生の入力・Provider応答・秘密情報はログへ出さない。

## 検証

ユーザー指定の実データ評価区間は **東京→横浜、日比谷→神谷町、梅田→心斎橋**。駅の同定方針と実施手順は [評価ケース](test/evaluation/README.md)、機械可読な区間一覧は [routes.json](test/evaluation/routes.json) を参照。2026-09-26にRapidAPIの概算経路取得は全3区間で成功。実ダイヤ照合とDB経由のHTTP API検証は未実施。詳細は [接続確認記録](test/evaluation/connection-check.md)。

```powershell
npm run check
npm run build
npm test
npm run openapi
```

テストはPGlite（PostgreSQLをWASMで実行）へ実マイグレーションを適用し、FastifyのHTTP injectionを使う。認証→検索→Live Activity登録、所有権、更新トークンの再使用拒否、期限切れ、入力検証、隣接検索、レート制限、Providerタイムアウト、データ公開ロールバック、Push差分・集約・再試行・トークン失効を検証する。

通常のPostgreSQLサーバーでの負荷・並行トランザクション、Docker起動、外部Provider、実APNs/iOS端末は別途検証が必要。フロントの18場面すべてに対応した契約fixtureは未整備。

実装時に参照した公式資料：

- [Fastify validation / serialization](https://fastify.dev/docs/latest/Reference/Validation-and-Serialization/)
- [Fastify OpenAPI plugin](https://github.com/fastify/fastify-swagger)
- [Apple ActivityKit push notifications](https://developer.apple.com/documentation/ActivityKit/starting-and-updating-live-activities-with-activitykit-push-notifications)

## レビュー対応（2026-09-26）

- Live Activity登録・解除とmonitorの行ロック処理は `READ COMMITTED`。snapshot / changesを含むその他のトランザクションは従来の `REPEATABLE READ` を維持する。
- monitorはsession単位の例外を `retry` に数え、後続を処理する。送信・削除の件数はDBコミット成功後に加算し、ジョブは集計結果のみ出力する。
- 時刻表の再公開は独立した `tripUpdate` を削除しない。
- APNs adapterはJWTを30分キャッシュし、HTTP/2接続を再利用する。GOAWAY・接続終了後は次の送信で再接続し、単発ジョブの終了時に接続を閉じる。キャッシュはadapterインスタンス内のみで、別プロセスの単発ジョブ間では共有しない。高頻度のジョブ起動や複数worker運用では、長寿命の配信workerやトークン共有を別途設計する必要がある。
- `TRUST_PROXY` は信頼するプロキシのIP/CIDRをカンマ区切りで指定する（例：`127.0.0.1,10.20.0.0/24`）。未指定では転送ヘッダーを信頼しない。本番ネットワークに合わせて設定し、クライアントが転送ヘッダーを偽装できない構成にする。

回帰テストは時刻表再公開時のrealtime保持、monitorの例外・コミット失敗後の継続、ローカルHTTP/2経由のJWT・接続再利用と再接続、信頼済み／未信頼プロキシ経由のレート制限を検証する。PGliteでは実PostgreSQLの行ロック競合を再現できないため、PUT/DELETE・同一キー再送・monitorの並行実行は実PostgreSQLで追加検証が必要。

低重要度の指摘（未知の `/v1/*` の認証優先、routeContext失効後のPUT再送、LocalScheduleProviderの探索性能、migration適用履歴管理）は今回の変更対象外として残る。
