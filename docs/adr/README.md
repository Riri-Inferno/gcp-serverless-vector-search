# Architecture Decision Records (ADR)

本リポジトリの設計判断を時系列で記録する場所。コードや構成だけでは追えない「なぜそうしたか」を残す。

## ADR とは

1ファイル = 1つの設計判断を、軽量なテンプレートで残すドキュメント形式。

典型的なセクション：

- **Context**: なぜこの決定が必要になったか / 何が問題か
- **Decision**: 何を決めたか
- **Consequences**: その決定により何が起きるか / 何を諦めるか

## このリポジトリでの運用ルール

- ファイル名は `NNNN-kebab-case-title.md`（連番）
- **一度 Accepted になった ADR 本文は削除・編集しない**。方針を変える場合は新しい ADR を起こし、supersede 関係は新 ADR とこの index で示す
- 相互依存の強い決定は1ファイルにまとめて構わない（例: API MVP 設計セット）

## インデックス

| 番号 | タイトル | Status |
|------|----------|--------|
| [0001](0001-api-design-mvp.md) | API MVP 設計（エンドポイント / ID / メタデータ / スコア / エラー） | Accepted |
| [0002](0002-openapi-version.md) | OpenAPI バージョンは 3.0.4 を採用 | Accepted |
| [0003](0003-authentication.md) | 認証は `X-API-Key` ヘッダ | Accepted |
| [0004](0004-firestore-embedding-model-field.md) | Firestore ドキュメントに `embedding_model` フィールドを追加 (0001 を補足) | Accepted |
| [0005](0005-cloud-functions-runtime-stack.md) | Cloud Functions 実装スタック (Python 3.13 / functions-framework + Flask / Pydantic v2 / google-genai / sync) | Accepted |
| [0006](0006-secret-management-sops-kms.md) | シークレット管理は SOPS + Cloud KMS で暗号化して git に置く | Accepted |
| [0007](0007-sops-path-regex-fix.md) | `.sops.yaml` の `path_regex` を素ファイルにマッチさせる (0006 訂正) | Accepted |
| [0008](0008-healthz-api-key-required.md) | `/healthz` も API Key 必須に変更 (0001 訂正、GCP API Gateway 制約) | Accepted |
| [0009](0009-public-api-hostname.md) | 公開 API ホスト名を `vector-search.riri-inferno.com` に変更 (0001 補足) | Accepted |
| [0010](0010-healthz-trailing-slash-compatibility.md) | `/healthz` と `/healthz/` を両方受ける (0008 補足) | Accepted (superseded by 0011) |
| [0011](0011-healthz-canonical-path.md) | `/healthz` を canonical health check path とする (0010 差し戻し) | Accepted (superseded by 0012) |
| [0012](0012-healthz-wildcard-path-routing.md) | `/{healthz_path}` wildcard で healthz を routing する (0011 差し戻し) | Accepted (superseded by 0013) |
| [0013](0013-rename-healthz-path-to-health.md) | health check パスを `/healthz` から `/health` に変更する (0012 差し戻し) | Accepted |
| [0014](0014-cloudflare-worker-host-rewrite.md) | Cloudflare Worker で Host ヘッダを書き換えてカスタムドメインを GCP API Gateway に接続する | Accepted |
