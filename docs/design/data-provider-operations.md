# データ提供元・運用設計

| 項目 | 内容 |
| --- | --- |
| 版 | v0.1（レビュー案） |
| 作成日 | 2026-09-26 |
| 初期予算 | 月額 5,000 円以内を目安 |

## 1. 結論

単一の Provider だけでは、首都圏・関西圏について、経路、正確な運賃、駅時刻表、全停車駅、番線、乗車位置、運行情報、リアルタイム遅延をすべて供給できない。

初期構成は次の併用とする。

| 用途 | 第一候補 | 補足 |
| --- | --- | --- |
| 首都圏・関西圏の広域経路検索 | Google Routes | 公共交通＋徒歩。候補数や運賃項目に制約あり |
| 比較検証・運賃 | NAVITIME API Marketplace | 無料500アクセスは固定評価ケースに限定 |
| 公開データ対応路線の時刻表・運行情報 | ODPT / GTFS / GTFS-Realtime | データセットごとにライセンスと提供項目を確認 |
| 自前経路計算 | GTFS対応ルーター | 東京メトロ・都営地下鉄から段階導入 |
| Live Activity | GTFS-RT等の実データがある路線のみ | Alertだけの場合は列車単位の遅延を生成しない |

## 2. Provider 機能比較

`supported`は要求を概ね満たす、`partial`は一部のみ、`unsupported`は専用データ源として使えない、`unknown`は契約前確認が必要、を表す。

| 要求 | Google Routes | NAVITIME Marketplace 基本機能 | ODPT / GTFS 系 |
| --- | --- | --- | --- |
| 広域経路検索 | supported | supported / partial | 公開フィード範囲のみ |
| 複数候補 | 最大4候補 | 件数保証は要検証 | ルーター実装次第 |
| 経由駅 | 公共交通ではunsupported | supported | ルーター実装次第 |
| 直前・直後の経路 | 再検索による近似 | 基本プランではunsupported | 自前再探索 |
| 全停車駅 | unsupported | Marketplaceではunsupported | 静的GTFSで可能 |
| 駅時刻表 | unsupported | Marketplaceではunsupported | 静的GTFSで可能 |
| 路線別運行情報 | unsupported | Marketplaceではunsupported | フィード提供時のみ |
| IC / 切符運賃 | 区別なし | partial〜supported | フィード内容次第 |
| 番線 | unsupported | unknown | フィード内容次第 |
| 乗車位置 | unsupported | partial | 通常は別データが必要 |
| 列車単位の遅延 | unsupported | Marketplaceではunsupported | Trip Updates提供時のみ |
| 安定ID | 独自IDが必要 | 独自IDが必要 | Feed変更に備え独自IDが必要 |

## 3. NAVITIME 無料枠の扱い

- API Marketplaceには、APIグループごとに月500アクセス上限の無料プランがある。
- 上限はハードリミットであり、通常ユーザーの検索へ直接割り当てない。
- 首都圏・関西圏の固定ODペア、始発・終電、経由駅、有料特急、日跨ぎ等の評価ケースに使う。
- Google、自前計算、NAVITIMEの候補・時刻・運賃を比較し、差異を記録する。
- 有料プランは初期予算を超えるため、自動アップグレードしない。
- Marketplaceと直販ではAPIの範囲、URL、パラメータ、サポートが異なるため、同一契約として扱わない。

## 4. ODPT / GTFS の扱い

- GTFS仕様が公開されていることと、各事業者のデータが恒久公開されていることは別である。
- カタログの各データセットについて、ライセンス、再配布、キャッシュ、更新期限、表示義務を記録する。
- 期間限定・コンテスト限定データを本番の恒久依存先にしない。
- `Alerts`、`Trip Updates`、`Vehicle Positions` のどれが提供されるかを別々に管理する。
- Alertしかない場合、列車位置や遅延分数を推定しない。
- 静的データ更新に失敗した場合は直前の正常版を維持し、`asOf`を表示する。

### 4.1 初期対象

- 東京メトロ
- 都営地下鉄

対象路線ごとに、次の機能表を作成してから公開する。

| 機能 | 確認内容 |
| --- | --- |
| schedule | 時刻表と運行日の有無 |
| fare | IC、切符、特急料金、内訳 |
| alert | 遅延・運休の概要と原因 |
| tripUpdate | 列車単位の予想到着・出発 |
| vehiclePosition | 車両位置 |
| platform | 番線 |
| boardingPosition | 号車・出口・乗換位置 |

## 5. 関西圏

初期段階では、関西圏のAPI-01を外部経路APIで提供する。駅時刻表、全停車駅、運行情報等は、恒久利用可能かつ一般公開アプリで利用可能なデータが確認できた路線から追加する。

京都等の期間限定データを利用可能範囲の根拠にしない。関西圏で機能が不足する場合は、`capabilities`と画面表示で明示する。

## 6. データ品質ゲート

新しいフィードは、次をすべて満たしてから公開する。

1. ライセンスと表示義務を記録済み。
2. ID、参照先、座標、時刻、運行日の検証に合格。
3. 前回版との件数差が許容範囲内。
4. Canonical IDの自動対応と手動レビューが完了。
5. サンプル経路と時刻表を実際の公表情報と照合。
6. `capabilities`を実際の提供項目に合わせて更新。
7. ロールバック可能な状態で公開。

## 7. 更新と監視

| 対象 | 基本周期 | 異常時 |
| --- | --- | --- |
| 静的GTFS | 毎日更新確認 | 直前正常版を維持 |
| GTFS-RT / 運行情報 | 60秒 | 障害中は許容範囲で30秒 |
| Live Activity差分評価 | フィード更新時 | 同一内容は抑止 |
| 駅マスタ差分 | 月次 | 重大変更時は臨時配信 |
| Providerクォータ | 継続監視 | 別Provider→自前→明示エラー |

監視画面では少なくとも、フィード最終成功時刻、失敗回数、現在公開中の版、データ件数、APIエラー率、APNs失敗分類を確認できるようにする。

## 8. 月額上限

初期予算は次の方法で守る。

- Cloud Runは低トラフィック時に縮退する設定とする。
- PostgreSQLは外部サービスの無料枠から開始し、休止・容量・接続数の条件を監視する。
- Google Routesには日次クォータと予算アラートを設定する。
- NAVITIMEは無料500件のハードリミットを維持する。
- Providerごと、端末ごと、IPごとにレート制限する。
- 予算上限接近時は、自前対応地域への縮退を優先する。
- 予算超過を伴う自動アップグレードは行わない。

ユーザー数の増加後は、収益または明示的に承認した予算に合わせて上限を見直す。

## 9. ライセンス・出典

- データセット単位で、提供者、ライセンスURL、表示文言、再配布可否、キャッシュ期限、更新義務をDBまたは設定として管理する。
- API応答の`attributions`からフロントへ必要な表示を渡す。
- 元データや復元可能な派生データを、許可なく再配布しない。
- Providerの検索結果を保存、加工、再順位付け、Live Activityへ再表示できるかを、本番接続前に規約と契約で確認する。
- 競合サービス制限のある期間限定データを採用しない。

## 10. 公式参照先

- [国土交通省 GTFS-JP](https://www.mlit.go.jp/sogoseisaku/transport/sosei_transport_tk_000067.html)
- [公共交通オープンデータセンター データカタログ](https://ckan.odpt.org/ja/dataset)
- [ODPT 基本ライセンス](https://developer.odpt.org/terms/data_basic_license.html)
- [ODPT 基本ライセンス利用ガイドライン](https://developer.odpt.org/terms/data_basic_use_guideline.html)
- [Google Routes 公共交通経路](https://developers.google.com/maps/documentation/routes/transit-route)
- [Google Maps Platform 料金](https://developers.google.com/maps/billing-and-pricing/pricing)
- [NAVITIME API Marketplace](https://api-sdk.navitime.co.jp/api/market/)
- [NAVITIME API一覧と料金](https://api-sdk.navitime.co.jp/api/specs/description/about_navitime_api.html)
- [NAVITIME 公共交通ルート検索](https://api-sdk.navitime.co.jp/api/specs/api_guide/route_transit.html)
- [NAVITIME 時刻表API](https://api-sdk.navitime.co.jp/api/specs/api_guide/transport_diagram-segment.html)
- [NAVITIME 全停車駅API](https://api-sdk.navitime.co.jp/api/specs/api_guide/transport_stops.html)
- [NAVITIME 運行情報API](https://api-sdk.navitime.co.jp/api/specs/api_guide/operation_train-link.html)

## 11. 実装開始前の外部確認

- [ ] Googleの規約上、検索結果の保存・加工・再順位付け・Live Activity表示が可能
- [ ] NAVITIME Marketplaceで必要なAPIグループとパラメータが利用可能
- [ ] ODPT各データセットの一般公開アプリ利用条件を確認済み
- [ ] 東京メトロ・都営地下鉄の各フィードで得られる実項目を確認済み
- [ ] フロントに必要な出典文言を確定済み
- [ ] APNs鍵、Bundle ID、Environmentの受け渡し方法を確定済み
- [ ] 月額上限と各Providerのクォータを設定済み

