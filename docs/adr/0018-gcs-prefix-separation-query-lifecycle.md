# ADR 0018: GCS プレフィックス分離と検索クエリ画像の自動削除

- **Date**: 2026-06-25
- **Status**: Accepted
- **Related**: ADR 0017 (GCS Signed URL 直アップロード)

## Context

ADR 0017 で導入した Signed URL アップロードは、登録用途（`POST /v1/documents`）と検索クエリ用途（`POST /v1/search` の画像クエリ）の両方で同じフローを使う。しかし現状はいずれも `inputs/{uuid}.ext` という同一プレフィックスに書き込まれており、次の問題がある。

1. **検索クエリ画像が無期限蓄積される**: 検索のたびに GCS オブジェクトが増える。検索クエリ画像は埋め込み生成後に参照されることはなく、Firestore には保存もされないため、保持コストに対してリターンがゼロ。
2. **プレフィックスが同じため lifecycle を用途別に設定できない**: 登録データは長期保持したい一方、クエリ画像は短命で良い。現状の `age = 30` は用途を問わず一律に適用されている。

## Decision

`/v1/documents/upload-url` リクエストに `purpose` フィールド（`"document"` | `"query"`）を追加し、用途別にプレフィックスを振り分ける。

| `purpose`                          | GCS プレフィックス | 用途                                                    |
| ---------------------------------- | ------------------ | ------------------------------------------------------- |
| `"document"`（省略可・デフォルト） | `inputs/`          | ドキュメント登録（Firestore に `gcs_uri` が記録される） |
| `"query"`                          | `queries/`         | 検索クエリ画像（Firestore には保存されない）            |

GCS Lifecycle Rule に `queries/` プレフィックス条件を追加し、`age = 1`（翌日削除）を設定する。GCS Lifecycle の最小粒度が 1 日であるため、「1 時間後削除」は仕様上実現できない。翌日削除で実用上十分と判断した。

既存の `age = 30` (全オブジェクト対象) は登録データのフォールバックとして維持する。

## Rationale

- `purpose` フィールドをサーバー側で判断することで、クライアントがプレフィックスの存在を意識しなくて済む
- `"document"` をデフォルト値にすることで既存クライアント（API 経由の登録スクリプト等）への後方互換性を保つ
- Signed URL 発行後にサーバー側でオブジェクトを削除することも考えたが、GCS の非同期性やエラーハンドリングが複雑になるため却下
- GCS Object Lifecycle は GCP マネージドかつゼロコスト。Cloud Scheduler + Cloud Functions による定期削除と比べて運用負荷が低い

## Consequences

- `api/openapi.yaml` の `UploadUrlRequest` スキーマに `purpose` を追加（任意フィールド）
- `functions/vector-api/models.py` の `UploadUrlRequest` に `purpose: Literal["document", "query"] = "document"` を追加
- `functions/vector-api/main.py` の `handle_get_upload_url()` でプレフィックスを切り替え
- `terraform/gcp/media_bucket.tf` に `queries/` プレフィックス向け `lifecycle_rule` を追加
- フロントエンドは検索用途の `uploadFile()` 呼び出し時に `purpose: "query"` を渡す（登録用途はデフォルトのまま）
- `queries/` に書かれたオブジェクトは Firestore に記録されないため、削除 API（ADR 0017 相当）の対象外となる
