# バックエンド API 提案書

| 項目 | 内容 |
| --- | --- |
| 版 | v0.1（レビュー案） |
| 作成日 | 2026-09-26 |
| 対象文書 | [API 要件定義書 v1.0](../requirements/api-contract.md) |
| 互換性方針 | 既存要求を尊重し、取得不能データと運用上必要な情報を明示する |

## 1. 目的

フロントエンドが定義した論理 API とモデルを、複数の交通データ提供元、匿名認証、Live Activity の運用に耐える HTTP API 契約へ具体化する。

本書は提案であり、レビュー完了までは `api-contract.md` を変更しない。

## 2. 共通仕様

| 項目 | 提案 |
| --- | --- |
| ベースパス | `/v1` |
| 形式 | JSON / UTF-8 / camelCase |
| 日時 | ISO 8601、タイムゾーン付き |
| リクエスト ID | 全応答に `X-Request-Id` を付与 |
| 冪等性 | 登録・解除系は `Idempotency-Key` を受理 |
| 圧縮 | gzip または Brotli |
| バージョン | `/v1` 内では任意項目の追加のみ。削除、型変更、意味変更は `/v2` |

### 2.1 共通メタデータ

変動するデータの応答には、次のメタデータを持たせる。

```json
{
  "meta": {
    "asOf": "2026-09-26T08:14:00+09:00",
    "partialResult": false,
    "isStale": false,
    "sources": ["google-routes"],
    "attributions": [
      {
        "provider": "example",
        "displayText": "データ提供: Example",
        "licenseUrl": "https://example.com/license"
      }
    ]
  },
  "data": {}
}
```

- `partialResult`: 一部 Provider の失敗や機能欠損があっても、有効な結果を返したことを示す。
- `isStale`: キャッシュの有効期限を過ぎていることを示す。最新情報として扱わない。
- `sources`: デバッグ・監査用の Provider 識別子。表示義務は `attributions` に集約する。
- `attributions`: フロントが「データの提供元」に表示する文言とリンク。

## 3. 認証

### 3.1 初期段階

1. アプリは匿名インストール登録を行う。
2. サーバーは短寿命アクセストークンと更新トークンを返す。
3. 各 API は Bearer トークンを検証し、端末単位・IP 単位のレート制限を行う。
4. 外部 API キーや APNs 秘密鍵をアプリへ配布しない。

### 3.2 一般公開前

- Apple App Attest の検証を追加する。
- App Attest が一時的に利用できない場合の再試行と制限付きフォールバックを設ける。
- アカウントは必須にせず、将来 Sign in with Apple と匿名インストールを統合できる構造にする。

## 4. エンドポイント

| 論理 ID | Method / Path | 概要 |
| --- | --- | --- |
| 認証 | `POST /v1/installations` | 匿名インストール登録 |
| 認証 | `POST /v1/auth/refresh` | トークン更新 |
| API-01 | `POST /v1/routes/search` | 経路検索 |
| API-02 | `POST /v1/routes/adjacent` | 直前・直後に出発可能な経路全体を再探索 |
| API-03 | `GET /v1/train-runs/{trainRunId}` | 全停車駅一覧 |
| API-04 | `GET /v1/stations/{stationId}/directions` | 路線・方面一覧 |
| API-05 | `GET /v1/timetables` | 駅・路線・方面別時刻表 |
| API-06 | `GET /v1/operation-statuses` | 地域別運行情報 |
| API-07 | `GET /v1/operation-statuses/{lineId}` | 路線別運行情報詳細 |
| API-08 | `GET /v1/master-data/changes` | 駅・路線等の差分 |
| API-09 | `PUT /v1/live-activities/{activityId}` | Live Activity 登録・再登録 |
| API-10 | `DELETE /v1/live-activities/{activityId}` | Live Activity 登録解除 |
| 追加 | `GET /v1/capabilities` | 路線・機能別の提供状況 |
| 追加 | `GET /v1/attributions` | 現在有効な出典・ライセンス表示 |

## 5. API-01 経路検索

既存の入力項目を維持し、次を明確化する。

- `sort` は Provider から候補の多様性を得るための検索ヒントであり、最終表示順を保証しない。
- バックエンドは、最低乗換時間、運休、重複候補を検証した最大 10 件を返す。
- フロントエンドは `durationMinutes`、`transferCount`、`fare` を使って最終的に並べ替える。
- Google Routes の公共交通検索で扱えない経由駅指定は、別 Provider または自前エンジンへルーティングする。対応不能なら `FEATURE_UNAVAILABLE` を返す。
- 通常 2 秒以内を目標とし、外部 Provider 呼び出しを含め最大 5 秒で打ち切る。

### 5.1 Provider 非依存の Route

`Route` は次を追加する。

| 項目 | 型 | 必須 | 説明 |
| --- | --- | --- | --- |
| `availability` | `DataAvailability` | ○ | 経路全体のデータ充足状況 |
| `warnings` | `RouteWarning[]` | ○ | 欠損・古い情報・運行障害など |
| `routeContext` | string | ○ | 署名付き、不透明、短寿命の値 |

`routeContext`には Provider の生レスポンスや秘密情報を含めず、改ざん検知と有効期限を持たせる。

## 6. 条件付き項目への変更提案

Provider が保証できない項目を必須のままにすると、不正確な値を生成する原因になる。次を条件付きへ変更する。

| モデル | 項目 | 提案 |
| --- | --- | --- |
| `Line` | `symbol` | 記号がない路線は `null`。表示用略称は別の `displayCode` を任意で返す |
| `Line` | `color` | 公式色がない場合は `null`。フロントが既定色を使う |
| `Leg` | `trainRunId` | 全停車駅を提供できる場合のみ |
| `StopPoint` | `estimatedTime` | リアルタイム予測がある場合のみ |
| `StopPoint` | `platform` | Provider が提供する場合のみ |
| `Fare` | `icTotal` | IC 運賃を確認できる場合のみ |
| `Fare` | `ticketTotal` | 切符運賃を確認できる場合のみ |
| `Fare` | `expressTotal` | 内訳を確認できる場合のみ |
| `BoardingPosition` | 全項目 | 対応路線のみ。推定値を入れない |

運賃が一種類しか得られない場合は、新設する `estimatedTotal` と `fareType: "estimated"` を使用し、IC または切符運賃として偽装しない。

## 7. データ可用性

```text
DataAvailability = available | partial | stale | unavailable
```

`OperationStatusKind` には `unknown` を追加する。これは「平常運転」ではなく「運行情報を確認できない」を表す。

### 7.1 capabilities

`GET /v1/capabilities` は、地域、事業者、路線ごとに次の機能を返す。

```json
{
  "lineId": "jp.line.tokyo-metro.ginza",
  "features": {
    "routeSearch": "available",
    "timetable": "available",
    "fare": "partial",
    "operationAlerts": "available",
    "tripUpdates": "unavailable",
    "vehiclePositions": "unavailable",
    "platform": "partial",
    "boardingPosition": "unavailable"
  },
  "asOf": "2026-09-26T08:14:00+09:00"
}
```

## 8. API-02 隣接経路

「1 本前・1 本後」は、最初の列車だけの差し替えではなく、元の条件に近い直前または直後の出発候補として経路全体を再探索する。後続の乗換や到着時刻は変化し得る。

Provider に専用機能がない場合は、元の検索条件と時刻を使った再探索で実現する。正確な隣接候補を保証できない場合は警告を返す。

## 9. API-08 マスタ差分

- Canonical ID をバックエンドが発行し、Google、NAVITIME、GTFS 等の ID は対応表で管理する。
- 初期対象は首都圏・関西圏の JR、大手私鉄、地下鉄の駅とする。
- 通常は月次スナップショットと差分を生成し、重大変更時は臨時配信する。
- 廃止・統合では単純削除に加えて `replacedById` を返せるようにする。
- バス停は駅と同じモデルに無理に入れず、将来別種別として追加する。

## 10. Live Activity

### 10.1 登録

API-09 は `routeContext` と監視対象 `legs` の両方を受け取る。

- `routeContext` で、直前にサーバーが生成した経路であることを検証する。
- `legs` は監視継続用のスナップショットとして保存する。
- 両者が一致しない場合は `ROUTE_CONTEXT_MISMATCH` を返す。
- 同一 `activityId` の再登録は更新として扱い、冪等にする。
- `expiresAt` は到着予定時刻の 1 時間後を上限とし、異常終了時も 24 時間以内に強制削除する。

### 10.2 Push 条件

- 通常のカウントダウンと区間進行は端末で処理する。
- 見込み時刻、遅延、運休、番線、乗換可能性が変化した場合だけ Push する。
- 同一内容は再送しない。
- 短時間の連続変化は 30〜60 秒でまとめる。ただし運休、乗換不能、重要な番線変更は即時送信する。
- Provider が新しい見込み時刻を返した場合、遅延分数の大小にかかわらず更新対象とする。
- 通常の通知アラートは送らず、Live Activity の表示更新だけを行う。

### 10.3 APNs ContentState

`api-contract.md` の ContentState を出発点とし、最終的な Swift 型と完全一致させる。APNs 制限に備え、全区間ではなく「現在区間と次区間」を中心とする縮小案もフロントレビューで比較する。

## 11. エラー

| code | HTTP | retryable | 意味 |
| --- | --- | --- | --- |
| `INVALID_REQUEST` | 400 | false | 入力形式または組合せが不正 |
| `STATION_NOT_FOUND` | 404 | false | Canonical ID に対応する駅がない |
| `ROUTE_NOT_FOUND` | 404 | false | 条件に合う経路がない |
| `FEATURE_UNAVAILABLE` | 422 | false | 対象路線・Provider では機能を提供できない |
| `ROUTE_CONTEXT_EXPIRED` | 410 | false | routeContext の期限切れ |
| `ROUTE_CONTEXT_MISMATCH` | 409 | false | 登録内容が検索結果と一致しない |
| `AUTHENTICATION_REQUIRED` | 401 | true | トークンが無効または期限切れ |
| `ATTESTATION_FAILED` | 403 | false | App Attest 検証失敗 |
| `RATE_LIMITED` | 429 | true | 端末または IP の制限超過 |
| `PROVIDER_QUOTA_EXCEEDED` | 503 | true | 外部 API の割当上限 |
| `PROVIDER_UNAVAILABLE` | 503 | true | 外部 Provider 障害 |
| `INTERNAL_ERROR` | 500 | true | 内部エラー |

Provider 固有のエラー本文、API キー、内部 URL はクライアントへ返さない。

## 12. フロントエンドとの合意チェックリスト

- [ ] 条件付きへ変更するモデル項目を Swift 側で表現できる
- [ ] `unknown` と `normal` を異なる状態として表示できる
- [ ] `partialResult`、`isStale`、`asOf` の表示ルールが決まっている
- [ ] `sort` が最終表示順の保証ではないことを了承している
- [ ] API-02 が経路全体を再探索することを了承している
- [ ] API-09 の登録モデルと Swift 型が一致している
- [ ] ContentState の最終サイズとフィールドが確定している
- [ ] 出典表示の配置と文言が確定している
- [ ] `/v1/capabilities` を使った未対応機能の表示が決まっている
- [ ] OpenAPI を正本とし、契約テストを両側で実行することに合意している

