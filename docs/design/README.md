# Norikae バックエンド設計文書

| 項目 | 内容 |
| --- | --- |
| 状態 | フロントエンドとのレビュー前の提案 |
| 作成日 | 2026-09-26 |
| 対象 | 乗り換え案内アプリ Norikae のバックエンド |
| 実装 | 本文書群には含めない |

## 文書構成

1. [バックエンド API 提案](./backend-api-proposal.md)
   - `api-contract.md` に対する追加・変更提案
   - エンドポイント、認証、エラー、可用性表現、Live Activity 契約
2. [バックエンド構成設計](./backend-architecture.md)
   - コンポーネント、データモデル、処理フロー、セキュリティ、テスト方針
3. [データ提供元・運用設計](./data-provider-operations.md)
   - Google Routes、NAVITIME、ODPT / GTFS の役割、制約、更新・監視・予算

関連するフロントエンド側の文書は次のとおり。

- [API 要件定義書](../requirements/api-contract.md)
- [フロントエンド要件定義書](../requirements/frontend.md)

## 合意済みの前提

- 個人開発で、初期の月額上限は 5,000 円を目安とする。
- 対象は首都圏・関西圏から始め、将来は全国へ拡張する。
- iOS / watchOS クライアント向けだが、API は将来の Web / Android からも利用可能な形にする。
- バックエンドは TypeScript、Fastify、PostgreSQL を基本構成とする。
- API は Cloud Run、DB は初期段階では外部の無料枠 PostgreSQL を想定する。
- API-01〜10 と `/v1/capabilities` を同じ初期設計範囲に含める。
- 広域経路検索は外部 API、公開データが揃う事業者は GTFS 系データによる自前処理を段階的に増やす。
- 最初の公開データ実証対象は東京メトロと都営地下鉄とする。
- 関西圏は初期段階では外部 API による経路検索を実データ対応範囲とする。
- 取得できない情報は推測せず、`null`、`unavailable`、または明示的なエラーで表す。
- 検索履歴、お気に入り、位置情報はサーバーに保存しない。
- Live Activity は通常進行を端末で計算し、遅延・運休・番線などの実データ変更時だけ APNs で更新する。
- 実装は、フロントエンドとの契約合意後に別セッションで行う。

## レビューで合意が必要な事項

- 必須項目を条件付き項目へ変更する範囲
- `sort` を検索ヒントとして残すこと
- `availability`、`capabilities`、`attributions` の追加
- API-09 で `routeContext` と監視対象区間を併送すること
- API-02 の「1 本前・1 本後」を経路全体の再探索と定義すること
- 実データを取得できない路線・機能の画面表現
- Live Activity の `ContentState` の最終 Swift 型

