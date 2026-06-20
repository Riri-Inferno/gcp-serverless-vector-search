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
- **一度 Accepted になった ADR は書き換えない**。方針を変える場合は新しい ADR を起こし、古い ADR の `Status` を `Superseded by NNNN` に更新する
- 相互依存の強い決定は1ファイルにまとめて構わない（例: API MVP 設計セット）

## インデックス

| 番号 | タイトル | Status |
|------|----------|--------|
| [0001](0001-api-design-mvp.md) | API MVP 設計（エンドポイント / ID / メタデータ / スコア / エラー） | Accepted |
| [0002](0002-openapi-version.md) | OpenAPI バージョンは 3.0.4 を採用 | Accepted |
| [0003](0003-authentication.md) | 認証は `X-API-Key` ヘッダ | Accepted |
| [0004](0004-firestore-embedding-model-field.md) | Firestore ドキュメントに `embedding_model` フィールドを追加 (0001 を補足) | Accepted |
| [0005](0005-cloud-functions-runtime-stack.md) | Cloud Functions 実装スタック (Python 3.13 / functions-framework + Flask / Pydantic v2 / google-genai / sync) | Accepted |
