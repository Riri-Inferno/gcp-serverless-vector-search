# ADR 0003: 認証は `X-API-Key` ヘッダ

- **Date**: 2026-06-19
- **Status**: Accepted

## Context

[`docs/security.md`](../security.md) の D2 (API Gateway) で全リクエストを認証する仕組みが必要。

選択肢: API Key（GCP API Gateway 標準）/ Firebase Auth + JWT / OAuth2 / その他。個人ラボの MVP ではユーザー管理は不要で、「使える人 / 使えない人」を区別できれば十分。

## Decision

**API Key** を採用し、**`X-API-Key` ヘッダ**で受ける。

OpenAPI 3.x の `securitySchemes` 記述：

```yaml
components:
  securitySchemes:
    google_api_key:
      type: apiKey
      name: x-api-key
      in: header
security:
  - google_api_key: []
```

- グローバルに `security` を適用し、`/healthz` だけ operation-level で `security: []` で上書きして認証を解除する
- API Key の発行・rotation は GCP コンソール / Terraform で管理する（具体的な管理方法は将来別 ADR）

## Consequences

- Cloud Functions に **認証コードを書かなくてよい**（API Gateway 段で弾かれる）
- Key 漏洩時の被害範囲は D4 (アプリ層バリデーション) + D5 (`max_instance_count`) で限定する（詳細は [`docs/security.md`](../security.md)）
- 既定では GCP API Gateway は API Key を `?key=...` query string で受ける。`in: header / name: x-api-key` を明示することで header 経由に切り替える設計
- 将来 Firebase Auth / JWT 等に切り替える場合は新しい ADR を起こし、`securitySchemes` を `type: openIdConnect` 等に置き換える
