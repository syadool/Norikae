# NAVITIME / RapidAPI 接続手順

現在の登録：**NAVITIME Transport / Free**。ODPTは申込済み、承認待ち。

Transportは駅・路線検索用。経路検索には別サービスの **NAVITIME Route(totalnavi)** への登録が必要。同じRapidAPIアカウントでもサービスごとの登録が必要となる。

## まずTransportに接続する

1. RapidAPIで登録済みのNAVITIME TransportのAPI画面を開く。
2. コードサンプルに表示される `X-RapidAPI-Key` を確認する。
3. `backend/.env.example` を `backend/.env` にコピーする。既に `.env` がある場合は上書きせず設定を追加する。
4. `.env` の `RAPIDAPI_KEY=` にキーを記入する。チャット、Swift、Git管理対象のファイルには貼らない。
5. `DATABASE_URL` をローカルPostgreSQLの接続先に設定し、次を実行する。

```powershell
cd C:\Users\tak-m\Documents\Norikae\backend
# Dockerを利用する場合。APIは起動せず、DBだけ起動する。
# Composeの設定読込に必要なので、.envのENCRYPTION_KEYも先に設定する。
# キーの生成: node -e "console.log(require('node:crypto').randomBytes(32).toString('base64'))"
docker compose up -d db
npm run migrate:env
npm run navitime -- stations 東京
```

駅候補の一覧が返ればTransportへの接続成功。キーは出力しない。駅検索は1コマンドにつき最大1リクエストで、自動再試行はしない。

評価対象の残りの駅も次で調べる。

```powershell
npm run navitime -- stations 横浜
npm run navitime -- stations 日比谷
npm run navitime -- stations 神谷町
npm run navitime -- stations 梅田
npm run navitime -- stations 心斎橋
npm run navitime -- usage
```

候補の先頭を自動採用しない。梅田はOsaka Metroの梅田駅として、他の梅田周辺駅と区別する。CLIの `providerStationId` はNAVITIME側のIDであり、アプリ保存用のCanonical IDとは別。

## Route(totalnavi)登録後の経路接続確認

現在のTransport契約だけではこの段階を実行できない。Route(totalnavi)の登録後、駅検索で確認したIDを指定する。

```powershell
# FROM_ID / TO_ID を実際に確認した駅IDに置き換える。
# 日時も試したい日本時間へ変更する。
npm run navitime -- probe FROM_ID TO_ID 2026-09-27T09:00:00+09:00
```

東京→横浜、日比谷→神谷町、梅田→心斎橋について各1回ずつ実行する。これらの確認は利用枠を消費する。コマンドは結果を表示するが、検索結果をDBやファイルへ自動保存しない。認証エラー・未登録は `PROVIDER_UNAVAILABLE`、429またはローカル予算上限は `PROVIDER_QUOTA_EXCEEDED` となる。

平均所要時間による結果は `timeBasis: "average"` として返す。提供元の疑似発着時刻を `scheduledTime` に変換しない。`routeContext` は発行せず、Live Activity登録・1本前後の列車案内には使わない。`fare.unit_0` は種別未確定の参考額として `estimatedTotal` にだけ格納し、IC/切符と断定しない。

## バックエンドHTTP APIへの接続

バックエンド担当の作業：駅検索で確認した駅情報を、次の形のJSON配列にまとめる。

```text
[
  {
    "providerStationId": "確認済みのNAVITIME駅ID",
    "station": {
      "id": "アプリ用の安定Canonical ID",
      "name": "確認済み駅名",
      "reading": "確認済みのひらがな読み",
      "prefecture": "確認済み都道府県",
      "region": "kanto または kansai",
      "lineIds": [],
      "latitude": 実データの緯度,
      "longitude": 実データの経度
    }
  }
]
```

上記は説明用の形であり、値を埋めるまでは投入可能なJSONではない。座標や対応駅を推測しない。既存駅を更新する場合は既存 `lineIds` 等を含む完全な駅レコードを渡す。

```powershell
npm run navitime -- import-stations reviewed-stations.json
```

取込は駅マスタ・差分・ID対応を同一トランザクションで更新する。ID対応の変更は自動では許可しない。

Route(totalnavi)登録とID対応が完了したら、`.env` に次を設定する。

```dotenv
NAVITIME_ENABLED=true
NAVITIME_ATTRIBUTION_TEXT=契約で指定された出典表示文言
NAVITIME_LICENSE_URL=契約に対応する利用条件のURL
```

`NAVITIME_ENABLED` は概算経路HTTP APIの有効化スイッチ。TransportのCLI駅検索には不要。出典表示は本番公開前に契約の指定を確認して設定する。

```powershell
npm run dev:env
```

新規HTTP APIは **`POST /v1/route-estimates/search`**。認証必須で、入力は既存検索と同じCanonical駅IDを使うが、searchTypeはdeparture/arrivalのみ。出力は概算所要時間・乗換回数・区間名・参考運賃で、予定発着時刻を含まない。詳細は `openapi.json`。

既存 `/v1/routes/search` の実ダイヤ契約は変更しない。既存capabilitiesの `routeSearch` も、概算接続だけでは対応済みにしない。概算表示をアプリで使うにはフロント担当による新API対応が別途必要。本作業ではフロントエンドを変更しない。

## 利用枠と検証状態

- `NAVITIME_REQUEST_BUDGET` はサービスごとに累計450回を既定上限とする。APIとCLIでPostgreSQLの同じカウンターを使う。500回を超える設定は拒否。
- 実際の課金期間・アカウント全体の利用数と一致するとは限らない。RapidAPIのコンソールなどから使った回数は含まれない。
- 月初や再起動では自動リセットしない。提供元で枠が更新されたことを確認したうえで、運用担当がカウンターの更新を判断する。DBを削除するとカウンターも消える。
- 通常のテストは合成レスポンスを使い、外部APIや利用枠を消費しない。
- APIキーがまだ設定されていない場合、実通信は未検証。登録済みサービスのキーで `stations` が成功した時点で接続確認済みとする。

公式資料：

- [NAVITIME公式RapidAPI接続サンプル](https://api-sdk.navitime.co.jp/api/specs/api_marketplace/rapid/tutorial/route_totalnavi/route_totalnavi_html-js.html)
- [サービス別機能と契約](https://api-sdk.navitime.co.jp/api/market/)
- [平均所要時間の説明](https://api-sdk.navitime.co.jp/api/specs/tips/averagetime.html)
- [経路検索の仕様](https://api-sdk.navitime.co.jp/api/specs/api_guide/route_transit.html)
