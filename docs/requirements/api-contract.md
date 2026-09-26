# API 要件定義書（フロントエンドからの要求）

| 項目 | 内容 |
| --- | --- |
| 対象 | 乗り換え案内アプリ（仮称：Norikae）でフロントエンドが必要とするデータと API |
| 版 | v1.1（修正案：バックエンド提案への回答を反映） |
| 作成日 | 2026-09-26 |
| 関連文書 | [frontend.md](./frontend.md)（フロントエンド要件定義書）、[バックエンド API 提案](../design/backend-api-proposal.md) |

### 改訂履歴

| 版 | 日付 | 内容 |
| --- | --- | --- |
| v1.0 | 2026-09-26 | 初版 |
| v1.1（案） | 2026-09-26 | バックエンド API 提案 v0.1 を受けた修正案。共通メタデータ、データ可用性、条件付き項目、運賃種別、`routeContext` の期限、Live Activity の日時形式と構成変更時の扱い、エラーコード、フロントからの追加要求を反映。バックエンドとの合意後に「案」を外す |

---

## 1. 位置づけ

- バックエンド（経路探索、データ取得、プッシュ送信）はフロントエンドの担当外である。
- この文書は、**フロントエンドが画面と Live Activity を作るために必要なデータの形** を定義し、バックエンド側に要求するためのものである。
- フロントエンドは、この文書を基に Repository のプロトコルとモックを実装して開発を進める。実際の API の URL や認証方式は、バックエンドが決めた時点で `Data` モジュールの実装だけを差し替える。
- 論理的な API 名（API-xx）は機能の単位を表しており、実際のエンドポイントの分け方はバックエンドに任せる。
- 実際のエンドポイント、認証方式、HTTP 上の共通仕様は [バックエンド API 提案](../design/backend-api-proposal.md) に従う。契約の正本は OpenAPI とし、フロントとバックエンドの両方で契約テストを実行する。

---

## 2. 共通規約

| 項目 | 規約 |
| --- | --- |
| 形式 | JSON（UTF-8）、キーは camelCase |
| 日時 | ISO 8601、タイムゾーン付き（例：`2026-09-26T08:15:00+09:00`）。**日付をまたぐ列車も、実際の日時で表す**（`25:10` のような表記は使わない） |
| 運行日 | 深夜の列車が属する運行日を、`serviceDate`（`YYYY-MM-DD`）で別に持つ。時刻表の平日・土曜・休日の区分は運行日で判定する |
| 時間の長さ | 分単位の整数（例：`durationMinutes`） |
| 金額 | 円単位の整数 |
| ID | 文字列。バージョンをまたいでも変わらないこと（お気に入りや履歴に保存するため） |
| 色 | `#RRGGBB` 形式 |
| 取得時刻 | 変動するデータ（経路、時刻表、運行情報）の応答には、情報の基準時刻 `asOf` を含める（フロントはキャッシュを表示するときにこれを出す）。2.1 の `meta` に含める |
| 欠けているデータ | 任意項目は、キーを省略するか `null` にする。空文字は使わない |
| 推測しない | 取得できない情報は推測値で埋めず、`null`、`unavailable`、または明示的なエラーで表す。フロントも、欠けている情報を「平常」「遅延なし」などに読み替えて表示しない |

### 2.1 共通メタデータ `meta`

変動するデータの応答は `{ "meta": ..., "data": ... }` の形にする。

| 項目 | 型 | 必須 | 説明 | フロントでの扱い |
| --- | --- | --- | --- | --- |
| `asOf` | datetime | ○ | 情報の基準時刻 | 「◯時◯分時点の情報」の表示に使う |
| `partialResult` | boolean | ○ | 一部の提供元が失敗したが、有効な結果を返したか | `true` のとき「一部の情報を取得できませんでした」を画面内に表示する |
| `isStale` | boolean | ○ | キャッシュの有効期限を過ぎた情報か | `true` のとき、キャッシュ表示と同じ見た目で取得時刻を明示し、最新情報として扱わない |
| `sources` | string[] | ○ | 提供元の識別子（デバッグ・監査用） | 表示しない |
| `attributions` | `Attribution[]` | ○ | 表示が必要な出典 | 2.2 参照 |

### 2.2 出典 `Attribution`

| 項目 | 型 | 必須 | 説明 |
| --- | --- | --- | --- |
| `provider` | string | ○ | 提供元の識別子 |
| `displayText` | string | ○ | 表示する文言。例：「データ提供: Example」 |
| `licenseUrl` | string | － | ライセンスのリンク |

- フロントは、応答の `meta.attributions` をその画面（縦比較、経路詳細、時刻表、運行情報）の下部に表示する。
- マイ画面の「データの提供元」（FR-MY-08）には、`GET /v1/attributions` で取得した全件を表示する。

### 2.3 エラー形式

```json
{
  "error": {
    "code": "STATION_NOT_FOUND",
    "message": "指定された駅が見つかりません",
    "retryable": false
  }
}
```

| 項目 | 説明 |
| --- | --- |
| `code` | 機械で判定するためのコード（一覧は下表） |
| `message` | ユーザーに見せてもよい日本語の文言 |
| `retryable` | 再試行ボタンを出してよいかどうか |

**エラーコードとフロントでの扱い**（コードと HTTP ステータスは [バックエンド API 提案](../design/backend-api-proposal.md) 11 章に合わせる）

| code | HTTP | retryable | フロントでの扱い |
| --- | --- | --- | --- |
| `INVALID_REQUEST` | 400 | false | 画面内にエラー表示。入力条件の見直しを促す |
| `STATION_NOT_FOUND` | 404 | false | 駅マスタの差分更新（API-08）を試み、駅の選び直しを促す |
| `ROUTE_NOT_FOUND` | 404 | false | 検索結果 0 件の空の状態として表示する |
| `FEATURE_UNAVAILABLE` | 422 | false | 「この区間・条件には対応していません」を表示し、対象の条件（経由駅、始発・終電など）を外して再検索する導線を出す |
| `ROUTE_CONTEXT_EXPIRED` | 410 | false | ユーザーに見せず、同じ検索条件で自動的に再検索する（4.2 参照） |
| `ROUTE_CONTEXT_MISMATCH` | 409 | false | 同じ検索条件で再検索し、案内の開始をやり直す |
| `AUTHENTICATION_REQUIRED` | 401 | true | ユーザーに見せず、トークンを更新して 1 回だけ再送する。失敗したらインストール登録からやり直す |
| `ATTESTATION_FAILED` | 403 | false | 「通信できませんでした」を表示する |
| `RATE_LIMITED` | 429 | true | 再試行ボタンを表示する。自動再試行はしない |
| `PROVIDER_QUOTA_EXCEEDED` | 503 | true | 再試行ボタンを表示する |
| `PROVIDER_UNAVAILABLE` | 503 | true | 再試行ボタンを表示する |
| `INTERNAL_ERROR` | 500 | true | 再試行ボタンを表示する |

- 表にないコードは、`retryable` に従って汎用のエラー表示にする（`/v1` 内でのコード追加に備える）。

---

## 3. ドメインモデル

### 3.1 事業者 `Operator`

| 項目 | 型 | 必須 | 説明 |
| --- | --- | --- | --- |
| `id` | string | ○ | |
| `name` | string | ○ | 例：「JR東日本」「東京メトロ」 |
| `region` | `Region[]` | ○ | `kanto` / `kansai` |

### 3.2 路線 `Line`

| 項目 | 型 | 必須 | 説明 |
| --- | --- | --- | --- |
| `id` | string | ○ | |
| `operatorId` | string | ○ | |
| `name` | string | ○ | 例：「山手線」 |
| `symbol` | string | － | 公式の路線記号。例：`JY`、`G`。記号がない路線は `null` |
| `displayCode` | string | － | 路線記号がない路線の表示用略称。例：「湘新」 |
| `color` | string | － | 公式の路線色。公式色がない路線は `null` |
| `region` | `Region` | ○ | |

- **色だけで路線を区別しない**（NFR-A11Y-04）ため、フロントは路線の記号欄に `symbol` → `displayCode` → `name` の順で最初にある値を表示する。
- `color` が `null` の路線は、フロントの既定色（`DesignSystem` で定義）で描く。

### 3.3 駅 `Station`（駅マスタ）

| 項目 | 型 | 必須 | 説明 |
| --- | --- | --- | --- |
| `id` | string | ○ | |
| `name` | string | ○ | 漢字表記 |
| `reading` | string | ○ | 読み（ひらがな）。候補検索に使う |
| `prefecture` | string | ○ | 都道府県名。同じ名前の駅の区別に使う |
| `region` | `Region` | ○ | |
| `lineIds` | string[] | ○ | 乗り入れている路線 |
| `stationCodes` | string[] | － | 駅ナンバリング（例：`JY01`） |
| `latitude` / `longitude` | number | ○ | 最寄り駅の検索と、駅周辺地図に使う |
| `exits` | `StationExit[]` | － | 出口名と座標。駅周辺地図に使う |

- 駅・路線・事業者・種別の `id` は、バックエンドが発行する Canonical ID とする（提供元の ID をそのまま使わない）。
- 駅の廃止・統合で ID が無効になる場合は、API-08 の `replacedById` で移行先を示す。フロントは保存済みのお気に入り・履歴・マイ路線の ID を移行先に置き換える。

### 3.4 種別 `TrainType`

| 項目 | 型 | 必須 | 説明 |
| --- | --- | --- | --- |
| `id` | string | ○ | |
| `name` | string | ○ | 例：「快速」「特急」 |
| `shortName` | string | ○ | 時刻表での略称。例：「快」 |
| `color` | string | － | 時刻表での表示色 |
| `isPaidExpress` | boolean | ○ | 有料特急かどうか |
| `isShinkansen` | boolean | ○ | 新幹線かどうか |

### 3.5 経路 `Route`

| 項目 | 型 | 必須 | 説明 |
| --- | --- | --- | --- |
| `id` | string | ○ | 検索結果の中で一意 |
| `departureTime` | datetime | ○ | 最初の出発時刻 |
| `arrivalTime` | datetime | ○ | 最後の到着時刻 |
| `durationMinutes` | int | ○ | 所要時間 |
| `transferCount` | int | ○ | 乗換回数 |
| `fare` | `Fare` | ○ | |
| `legs` | `Leg[]` | ○ | 区間の配列（時刻順） |
| `hasServiceDisruption` | boolean | ○ | 遅延・運転見合わせの影響がある路線を含むか（縦比較の警告バッジに使う） |
| `availability` | `DataAvailability` | ○ | 経路全体のデータの充足状況（3.14 参照） |
| `warnings` | `RouteWarning[]` | ○ | 欠損・古い情報・運行障害などの警告。ない場合は空配列 |
| `routeContext` | string | ○ | この経路を再現するための不透明な値。1 本前・1 本後の取得や、Live Activity のプッシュトークン登録に使う。**有効期限がある**（4.2 参照） |

- 「早・楽・安」のバッジは、フロントが `durationMinutes`・`transferCount`・`fare` から判定する（サーバーは返さなくてよい）。
- 「安」は、比較する全経路の表示運賃が同じ種別（3.8 の表示ルールで選ばれた種別）のときだけ付ける。種別が混在する場合や、運賃が不明な経路がある場合は付けない。

**`RouteWarning`**（フロントからの提案）

| 項目 | 型 | 必須 | 説明 |
| --- | --- | --- | --- |
| `code` | string | ○ | 例：`STALE_DATA`、`PARTIAL_DATA`、`SERVICE_DISRUPTION`、`ADJACENT_APPROXIMATE` |
| `message` | string | ○ | ユーザーに見せてもよい日本語の文言 |
| `legIndex` | int | － | 特定の区間に関する警告なら、その区間の `legs` 上の位置 |

- フロントは、経路詳細で `message` を表示する（`legIndex` があれば該当区間の近くに出す）。未知の `code` も `message` をそのまま表示する。

### 3.6 区間 `Leg`

`type` で乗車区間と徒歩区間を分ける。

**乗車区間（`type: "train"`）**

| 項目 | 型 | 必須 | 説明 |
| --- | --- | --- | --- |
| `type` | `"train"` | ○ | |
| `lineId` | string | ○ | 路線の色・記号は `Line` から引く |
| `trainTypeId` | string | ○ | |
| `trainRunId` | string | － | 停車駅一覧の取得に使う。全停車駅を提供できる区間のみ。ない区間では停車駅一覧を開けない |
| `destinationName` | string | ○ | 行き先 |
| `from` / `to` | `StopPoint` | ○ | 乗車駅と降車駅 |
| `stopCount` | int | ○ | 途中の停車駅数 |
| `boardingPosition` | `BoardingPosition` | － | 乗車位置。データがない区間は省略する（推定値は入れない） |
| `disruption` | `LegDisruption` | － | この区間の遅延情報 |

**徒歩区間（`type: "walk"`）**

| 項目 | 型 | 必須 | 説明 |
| --- | --- | --- | --- |
| `type` | `"walk"` | ○ | |
| `fromStationId` / `toStationId` | string | ○ | 同じ駅の中での乗換なら同じ ID |
| `durationMinutes` | int | ○ | 歩く時間 |

- 乗換での待ち時間は、前の区間の到着時刻と次の区間の出発時刻の差からフロントが計算する（縦比較では点線で描く）。

### 3.7 停車点 `StopPoint`

| 項目 | 型 | 必須 | 説明 |
| --- | --- | --- | --- |
| `stationId` | string | ○ | |
| `scheduledTime` | datetime | ○ | 時刻表上の発着時刻 |
| `estimatedTime` | datetime | － | 遅延を反映した見込みの時刻。リアルタイムの予測がある場合のみ |
| `platform` | string | － | 番線。例：`"3"`。提供元が返す場合のみ |
| `serviceDate` | date | ○ | 運行日 |

- `estimatedTime` がないことは「遅延なし」を意味しない。フロントは見込み時刻がない区間を「定刻」とは表示せず、時刻表上の時刻だけを表示する。

### 3.8 運賃 `Fare`

| 項目 | 型 | 必須 | 説明 |
| --- | --- | --- | --- |
| `fareType` | string | ○ | `exact`（IC・切符の区別がある確定運賃）/ `estimated`（種別を区別できない概算）/ `unavailable`（運賃を取得できない） |
| `icTotal` | int | － | IC カード運賃の合計。確認できる場合のみ |
| `ticketTotal` | int | － | 切符運賃の合計。確認できる場合のみ |
| `estimatedTotal` | int | － | `fareType: "estimated"` のときの概算運賃。IC・切符運賃として扱わない |
| `expressTotal` | int | － | 特急料金・新幹線料金などの合計。内訳を確認できる場合のみ |
| `breakdown` | `FareItem[]` | － | 内訳（事業者ごとなど） |

**フロントの表示ルール**

| 状態 | 表示 |
| --- | --- |
| 設定した種別（IC / 切符）の運賃がある | その金額 |
| 設定した種別がなく、もう一方の種別がある | もう一方の金額に「IC」「切符」の種別を併記する |
| `estimatedTotal` だけがある | 「約◯円」と表示する |
| いずれもない（`unavailable`） | 「運賃不明」と表示する |

### 3.9 乗車位置 `BoardingPosition`

| 項目 | 型 | 必須 | 説明 |
| --- | --- | --- | --- |
| `carNumber` | int | ○ | 号車 |
| `carCount` | int | － | 編成両数 |
| `purpose` | string | ○ | `transfer`（乗換に便利）/ `exit`（出口に近い） |
| `note` | string | － | 例：「中央線への乗換に便利」 |

### 3.10 区間の遅延情報 `LegDisruption`

| 項目 | 型 | 必須 | 説明 |
| --- | --- | --- | --- |
| `status` | `OperationStatusKind` | ○ | 3.13 参照 |
| `delayMinutes` | int | － | 遅延の分数 |
| `summary` | string | ○ | 例：「人身事故の影響で遅れ」 |

### 3.11 列車の運行 `TrainRun`（停車駅一覧）

| 項目 | 型 | 必須 | 説明 |
| --- | --- | --- | --- |
| `id` | string | ○ | |
| `lineId` / `trainTypeId` | string | ○ | |
| `destinationName` | string | ○ | |
| `stops` | `StopPoint[]` | ○ | 始発から終着までの全停車駅 |

### 3.12 時刻表 `Timetable`

| 項目 | 型 | 必須 | 説明 |
| --- | --- | --- | --- |
| `stationId` / `lineId` | string | ○ | |
| `directionId` | string | ○ | 方面 |
| `directionName` | string | ○ | 例：「渋谷・品川方面」 |
| `dayType` | string | ○ | `weekday` / `saturday` / `holiday` |
| `departures` | `TimetableEntry[]` | ○ | |
| `asOf` | datetime | ○ | 時刻表データの基準時点 |

**`TimetableEntry`**

| 項目 | 型 | 必須 | 説明 |
| --- | --- | --- | --- |
| `departureTime` | datetime | ○ | |
| `trainTypeId` | string | ○ | |
| `destinationName` | string | ○ | |
| `platform` | string | － | |
| `isOriginStation` | boolean | ○ | 当駅始発かどうか |
| `trainRunId` | string | ○ | 停車駅一覧の取得に使う |

### 3.13 運行情報 `OperationStatus`

| 項目 | 型 | 必須 | 説明 |
| --- | --- | --- | --- |
| `lineId` | string | ○ | |
| `status` | `OperationStatusKind` | ○ | `normal`（平常）/ `delayed`（遅延）/ `suspended`（運転見合わせ）/ `partial`（一部運休・直通中止など）/ `other` / `unknown`（運行情報を確認できない） |
| `summary` | string | ○ | 一覧に出す短い文言 |
| `cause` | string | － | 原因 |
| `occurredAt` | datetime | － | 発生時刻 |
| `outlook` | string | － | 見込み（例：「9時頃 運転再開見込み」） |
| `hasTransferTransport` | boolean | － | 振替輸送の有無 |
| `asOf` | datetime | ○ | 情報の基準時刻 |

- `unknown` は「平常」ではない。運行情報のデータがない路線、または取得に失敗した路線に使う。フロントは `normal` と異なるアイコン・色・文字で表示する。

### 3.14 データ可用性 `DataAvailability`

```text
DataAvailability = available | partial | stale | unavailable
```

| 値 | 意味 | フロントでの扱い |
| --- | --- | --- |
| `available` | 必要な情報がそろっている | 通常表示 |
| `partial` | 一部の情報が欠けている | 欠けた項目は表示しない。経路詳細に `warnings` を表示する |
| `stale` | 古い情報を含む | 取得時刻を明示する |
| `unavailable` | 情報を提供できない | その機能を「非対応」と表示し、操作できないようにする |

### 3.15 提供状況 `LineCapability`

`GET /v1/capabilities` で取得する、路線ごとの機能の提供状況。

| 項目 | 型 | 必須 | 説明 |
| --- | --- | --- | --- |
| `lineId` | string | ○ | |
| `features` | `[Feature: DataAvailability]` | ○ | 下表の機能ごとの提供状況 |
| `asOf` | datetime | ○ | |

| 機能 | 使う画面・要件 |
| --- | --- |
| `routeSearch` | 経路検索 |
| `timetable` | 時刻表（FR-TT） |
| `stopList` | 停車駅一覧（FR-DTL-07、FR-TT-06）。**フロントからの追加要求** |
| `fare` | 運賃の表示 |
| `operationAlerts` | 運行情報（FR-STS） |
| `tripUpdates` | 見込み時刻、Live Activity の遅延更新（FR-LA-12） |
| `vehiclePositions` | 使わない（将来用） |
| `platform` | 番線 |
| `boardingPosition` | 乗車位置（FR-DTL-05） |

**地域単位の提供状況（フロントからの追加要求）**

検索条件のうち、路線ではなく地域や提供元で決まるものは、検索前に分かるように地域ごとに返してほしい。

| 機能 | 使う画面・要件 |
| --- | --- |
| `viaStations` | 経由駅の指定（FR-CND-02） |
| `firstLastTrain` | 始発・終電の検索（FR-CND-01） |

- フロントは起動時と 1 日 1 回 capabilities を取得してキャッシュし、取得できない場合は直前のキャッシュを使う。キャッシュもない場合は、全機能を利用可能として扱い、API のエラー（`FEATURE_UNAVAILABLE`）で判定する。

---

## 4. 必要な API

| ID | 機能 | 主な入力 | 主な出力 | 関連要件 |
| --- | --- | --- | --- | --- |
| 認証 | 匿名インストール登録・トークン更新 | － | アクセストークン、更新トークン | 全 API |
| API-01 | 経路検索 | 4.1 参照 | `Route[]`、`meta` | FR-SRC / FR-CND / FR-CMP |
| API-02 | 1 本前・1 本後の経路 | `routeContext`、`direction`（`previous` / `next`） | `Route`（経路全体を再探索した結果） | FR-DTL-06、FR-LA-20 |
| API-03 | 列車の停車駅一覧 | `trainRunId`、`serviceDate` | `TrainRun` | FR-DTL-07、FR-TT-06 |
| API-04 | 駅の路線・方面一覧 | `stationId` | 路線と方面（`directionId`、`directionName`）の一覧 | FR-TT-01 |
| API-05 | 時刻表 | `stationId`、`lineId`、`directionId`、`dayType` | `Timetable` | FR-TT |
| API-06 | 運行情報の一覧 | `region` | `OperationStatus[]` | FR-STS |
| API-07 | 運行情報の詳細 | `lineId` | `OperationStatus` | FR-STS-04 |
| API-08 | 駅マスタの差分 | `sinceVersion` | 追加・更新・削除された `Station`、`Line`、`Operator`、`TrainType`、削除・統合時の `replacedById`、新しい `version` | FR-SRC-08 |
| API-09 | Live Activity のプッシュトークン登録 | 5.2 参照 | なし | FR-LA-11 |
| API-10 | Live Activity のプッシュトークン登録解除 | `activityId` | なし | FR-LA-11 |
| 追加 | 提供状況 | なし | `LineCapability[]`、地域単位の提供状況 | FR-CAP |
| 追加 | 出典 | なし | `Attribution[]` | FR-MY-08 |

- 経路検索の結果には、応答の中で参照している `Line`・`TrainType` が駅マスタにない場合に備え、その定義も同梱してよい（`includes` など）。
- アプリに同梱する駅マスタは、バックエンドが生成する月次スナップショットから作る。スナップショットの受け渡し方法（ファイル形式、取得場所、`version`）は実装開始前に決める。
- 認証トークンは端末の Keychain に保存する。API はアプリ本体のプロセスから呼ぶ（`LiveActivityIntent` もアプリ本体のプロセスで実行されるため、Widget Extension からは呼ばない）。

### 4.1 経路検索の入力（API-01）

| 項目 | 型 | 必須 | 説明 |
| --- | --- | --- | --- |
| `fromStationId` | string | ○ | |
| `toStationId` | string | ○ | |
| `viaStationIds` | string[] | － | 経由駅（最大 3 つ、指定順） |
| `dateTime` | datetime | ○ | 始発・終電の場合は日付だけを使う |
| `searchType` | string | ○ | `departure` / `arrival` / `firstTrain` / `lastTrain` |
| `useShinkansen` | boolean | ○ | |
| `usePaidExpress` | boolean | ○ | |
| `sort` | string | ○ | `fastest` / `fewestTransfers` / `cheapest`。**候補を集めるためのヒントであり、返す順番は保証しない** |
| `maxResults` | int | － | 返す経路の数（縦比較の横スクロールのため、4 本以上を期待する。上限 10） |

- 最終的な並び順は、フロントが `durationMinutes`・`transferCount`・表示運賃から決める。
- IC 運賃と切符運賃は、得られる場合は両方を返してもらい、表示の切り替えはフロントで行う（再検索しない）。
- 経由駅、始発・終電の検索に対応できない区間では、`FEATURE_UNAVAILABLE` を返す。フロントは地域単位の提供状況（3.15）で、事前に指定できないことを示す。

### 4.2 `routeContext` の有効期限

`routeContext` は署名付きの短寿命な値で、期限を過ぎると API-02・API-09 が `ROUTE_CONTEXT_EXPIRED` を返す。

- お気に入り経路（FR-DTL-03）と検索結果のキャッシュ（FR-OFF-01）には、`routeContext` ではなく**検索条件**を保存する。`routeContext` は表示用に一緒に持ってもよいが、期限切れを前提に扱う。
- 期限切れの `routeContext` で API-02・API-09 を呼ぶ必要が出た場合、フロントは保存した検索条件で API-01 を呼び直し、元の経路と同じ経路（区間の路線・乗車駅・降車駅・出発時刻が一致するもの）を探す。見つかればその新しい `routeContext` で処理を続け、見つからなければ新しい検索結果を表示して選び直してもらう。
- バックエンドには、`routeContext` の有効期限の目安（例：30 分）を決めてもらう。

---

## 5. Live Activity

### 5.1 役割分担

| 担当 | 内容 |
| --- | --- |
| フロントエンド | Live Activity の開始・終了、端末での時刻どおりの表示、プッシュトークンの取得と登録（API-09）・解除（API-10）、プッシュで届いた内容の表示 |
| バックエンド | 登録された経路の遅延を監視し、変化があったときに APNs でプッシュを送る |

- 通知（アラート）は出さない。プッシュは表示を更新するためだけに使う（遅延の通知はしない方針のため）。
- プッシュを送る条件はバックエンド API 提案 10.2 章に従う（見込み時刻、遅延、運休、番線、乗換可能性の変化時のみ。遅延分数の閾値は設けない）。
- 列車単位のリアルタイム情報（capabilities の `tripUpdates`）がない区間にはプッシュが届かない。フロントはその区間を「時刻表どおりの表示」と明示し、プッシュが来ないことを「遅延なし」と見せない。

### 5.2 プッシュトークン登録（API-09）の入力

| 項目 | 型 | 必須 | 説明 |
| --- | --- | --- | --- |
| `activityId` | string | ○ | 端末側の Live Activity の ID |
| `pushToken` | string | ○ | ActivityKit のプッシュトークン（16 進文字列）。トークンが更新されたら再登録する |
| `routeContext` | string | ○ | 監視する経路。期限切れの場合は 4.2 の手順で取り直す |
| `legs` | 監視用の区間情報 | ○ | 乗車区間ごとの `lineId`、`trainRunId`（ある場合のみ）、`serviceDate`、乗車駅・降車駅の `stationId` と予定時刻。サーバーは `routeContext` と照合し、一致しなければ `ROUTE_CONTEXT_MISMATCH` を返す |
| `expiresAt` | datetime | ○ | 到着予定時刻に余裕を足した時刻。これを過ぎたら監視を止めてよい。上限は到着予定時刻の 1 時間後 |

- 同じ `activityId` での再登録は更新として扱われる（冪等）。プッシュトークンが更新されたときは同じ `activityId` で呼び直す。
- `PUT /v1/live-activities/{activityId}` と `DELETE` には `Idempotency-Key` を付ける。

### 5.3 プッシュで送る内容（ContentState）

APNs の Live Activity 用の形式（`apns-push-type: liveactivity`）で送る。`content-state` の中身は、フロントの `ActivityAttributes.ContentState` と完全に一致させる必要がある。

```json
{
  "aps": {
    "timestamp": 1790378040,
    "event": "update",
    "stale-date": 1790380020,
    "content-state": {
      "legs": [
        {
          "index": 0,
          "platform": "3",
          "scheduledDeparture": 1790378100,
          "estimatedDeparture": 1790378400,
          "scheduledArrival": 1790379120,
          "estimatedArrival": 1790379420,
          "delayMinutes": 5,
          "isCancelled": false
        }
      ],
      "disruptionSummary": "人身事故の影響で遅れ",
      "updatedAt": 1790378040
    }
  }
}
```

| 項目 | 型 | 必須 | 説明 |
| --- | --- | --- | --- |
| `event` | string | ○ | `update`（更新）または `end`（終了） |
| `stale-date` | int | ○ | この時刻を過ぎたら、表示を「情報が古い」扱いにする |
| `legs` | 配列 | ○ | 乗車区間ごとの動的な情報。**全乗車区間を毎回送る**（APNs は `content-state` を丸ごと置き換えるため） |
| `legs[].index` | int | ○ | 乗車区間の順番（0 始まり、徒歩区間は数えない）。`ActivityAttributes` の区間と対応させる |
| `legs[].platform` | string | － | 番線 |
| `legs[].scheduledDeparture` / `scheduledArrival` | int | ○ | 予定の発着時刻 |
| `legs[].estimatedDeparture` / `estimatedArrival` | int | － | 見込みの発着時刻。リアルタイムの予測がある場合のみ |
| `legs[].delayMinutes` | int | － | 遅延の分数。リアルタイムの予測がある場合のみ |
| `legs[].isCancelled` | boolean | ○ | 運休かどうか |
| `disruptionSummary` | string | － | 遅延・運休の要約 |
| `updatedAt` | int | ○ | 情報の基準時刻 |

**日時の形式**

- `content-state` の中の日時は、**UNIX 時刻（1970-01-01 UTC からの秒数、整数）**で送る。
- 理由：ActivityKit は `content-state` を `JSONDecoder` の既定設定でデコードするため、ISO 8601 文字列はそのまま Swift の `Date` にならない（既定は 2001-01-01 基準の秒数）。フロントの `ContentState` は日時を `Int` で持ち、`Date` への変換は計算プロパティで行う。
- `content-state` の外の `timestamp`・`stale-date` も UNIX 時刻（APNs の仕様どおり）。

**`ActivityAttributes`（開始後に変わらない情報。プッシュには含めない）**

出発駅・到着駅の名前、乗車区間ごとの路線（名前・記号・色）、種別、行き先、乗車駅・降車駅の名前、その区間にリアルタイム情報があるか（capabilities の `tripUpdates`）。

- APNs のペイロードは 4KB が上限なので、`content-state` は上の項目に限る。
- `content-state` の JSON 例とフロントの Swift 型の一致は、両側の契約テストで確認する。
- 「1本後に変更」（FR-LA-20）で経路の構成（乗車区間の路線・乗車駅・降車駅）が変わらない場合は、フロントが `ContentState` を更新し、新しい `routeContext` で同じ `activityId` のまま API-09 を呼び直す。
- 構成が変わる場合は `ActivityAttributes` を変更できないため、フロントは現在の Live Activity を終了して新しく開始し、API-10 で旧 `activityId` を解除してから、新しい `activityId` で API-09 を呼ぶ。

---

## 6. Repository のプロトコル（フロントエンド側）

`Domain` モジュールに置くプロトコルの案。`Data` モジュールに、本物の API 実装とモック実装を用意する。

```swift
public protocol RouteRepository: Sendable {
    func searchRoutes(_ query: RouteSearchQuery) async throws -> RouteSearchResult
    func adjacentRoute(context: RouteContext, direction: AdjacentDirection) async throws -> Route
    func trainRun(id: TrainRun.ID, serviceDate: ServiceDate) async throws -> TrainRun
}

public protocol TimetableRepository: Sendable {
    func directions(stationID: Station.ID) async throws -> [LineDirection]
    func timetable(stationID: Station.ID, lineID: Line.ID, directionID: LineDirection.ID, dayType: DayType) async throws -> Timetable
}

public protocol OperationStatusRepository: Sendable {
    func statuses(region: Region) async throws -> [OperationStatus]
    func status(lineID: Line.ID) async throws -> OperationStatus
}

public protocol StationRepository: Sendable {
    /// 同梱の駅マスタを端末内で検索する（オフラインで動く）
    func search(text: String, preferredRegion: Region) async throws -> [Station]
    func nearest(to coordinate: Coordinate, limit: Int) async throws -> [Station]
    func applyUpdates() async throws
}

public protocol LiveActivityRegistrationRepository: Sendable {
    func register(_ registration: LiveActivityRegistration) async throws
    func unregister(activityID: String) async throws
}

public protocol CapabilityRepository: Sendable {
    /// キャッシュがあればそれを返し、古ければ API から取り直す
    func capabilities() async throws -> CapabilitySnapshot
}

public protocol AttributionRepository: Sendable {
    func attributions() async throws -> [Attribution]
}
```

- `RouteSearchResult`・`Timetable`・`OperationStatus` などの取得結果は、2.1 の `meta`（`asOf`、`partialResult`、`isStale`、`attributions`）を保持する。
- 認証（インストール登録、トークン更新、401 時の再送）は `Data` モジュールの API クライアントの内部で扱い、Repository のプロトコルには出さない。
- `ROUTE_CONTEXT_EXPIRED` 時の再検索（4.2）は、`Domain` のユースケースとして実装し、画面ごとに重複させない。

---

## 7. モックの要件

フロントエンドの開発とテスト（特にスナップショットテスト）のため、モックは少なくとも次の場面を再現できること。

| # | 場面 | 確認したいこと |
| --- | --- | --- |
| 1 | 通常：3 本の経路 | 縦比較の基本表示、「早・楽・安」のバッジ |
| 2 | 経路が 5 本以上 | 横スクロール |
| 3 | 所要時間の差が大きい経路の組み合わせ | 共通の時間軸の縮尺 |
| 4 | 終電で日付をまたぐ経路 | 時間軸の連続性、運行日の扱い |
| 5 | 乗換 0 回と 3 回以上 | 列の描画、タイムライン |
| 6 | 遅延を含む経路 | 警告バッジ、見込みの時刻、Live Activity の遅延表示 |
| 7 | 乗車位置・番線がない区間 | 任意項目がないときの表示 |
| 8 | 通信エラー（再試行できる / できない） | 画面内のエラー表示 |
| 9 | 検索結果が 0 件 | 空の状態 |
| 10 | 応答の遅延（数秒） | スケルトン表示 |
| 11 | 路線記号・路線色がない路線（`symbol`・`color` が `null`） | `displayCode` や路線名での代替表示、既定色 |
| 12 | 運賃が概算のみ（`estimated`）・不明（`unavailable`）、種別が混在する経路の組み合わせ | 「約◯円」「運賃不明」、「安」バッジを付けない |
| 13 | `partialResult: true`・`isStale: true` の応答、`warnings` を含む経路 | 一部欠損・古い情報の表示 |
| 14 | 運行情報が `unknown` の路線 | 「平常」と区別した表示 |
| 15 | capabilities で機能が `unavailable` の路線・地域（時刻表、停車駅一覧、経由駅、始発・終電、リアルタイム） | 非対応の表示、操作できない状態 |
| 16 | `trainRunId` がない区間 | 停車駅一覧を開けない状態 |
| 17 | `FEATURE_UNAVAILABLE`・`ROUTE_CONTEXT_EXPIRED` のエラー | 条件を外した再検索の導線、自動再検索 |
| 18 | 1 本後の経路で構成が変わる場合・変わらない場合 | Live Activity の更新と、終了・再開始 |

- 同じ場面をバックエンドの契約 fixture としても共有する（バックエンド構成設計 11 章）。

---

## 8. 未決事項（バックエンドとの調整が必要なもの）

| # | 内容 | 状況 |
| --- | --- | --- |
| 1 | 経路データの提供元と、出典・ライセンスの表示内容 | 提供元は[データ提供元・運用設計](../design/data-provider-operations.md)で提案済み。出典の文言は未確定 |
| 2 | 実際のエンドポイント、認証方式、API のバージョン管理 | [バックエンド API 提案](../design/backend-api-proposal.md) 2〜4 章で解決（合意待ち） |
| 3 | 駅マスタの差分更新の頻度と、差分の形式 | 月次＋臨時で解決（合意待ち）。同梱用スナップショットの受け渡し方法は未定 |
| 4 | エラーコードの一覧 | 2.3 で解決（合意待ち） |
| 5 | 乗車位置データの対象範囲（どの路線・駅まで用意できるか） | capabilities の `boardingPosition` で路線ごとに返す。初期は大半が `unavailable` の見込み |
| 6 | 遅延を監視する間隔と、プッシュを送る条件 | 60 秒間隔、見込み時刻の変化で送信（閾値なし）で解決（合意待ち） |
| 7 | `routeContext` の有効期限の目安 | バックエンドに確認 |
| 8 | 地域単位の提供状況（`viaStations`、`firstLastTrain`）を capabilities に含めること | フロントからの追加要求 |
| 9 | 機能 `stopList` を capabilities に含めること | フロントからの追加要求 |
| 10 | 始発・終電の検索（`searchType: firstTrain / lastTrain`）の実現方法 | バックエンド提案に記載がないため確認。Google Routes には該当機能がない |
| 11 | `RouteWarning` の項目と `code` の一覧 | 3.5 のフロント案で合意したい |
| 12 | `ContentState` の最終 Swift 型 | 5.3 の案（日時は UNIX 時刻）で合意したい |
