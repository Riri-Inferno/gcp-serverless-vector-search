# ADR 0008: `/healthz` も API Key 必須に変更 (ADR 0001 訂正)

- **Date**: 2026-06-22
- **Status**: Accepted
- **Supplements**: [0001](0001-api-design-mvp.md)

## Context

[ADR 0001](0001-api-design-mvp.md) で `/healthz` は「認証不要」と決定した。OpenAPI の operation-level `security: []` で global security を override することで実現できる前提だった。

しかし GCP API Gateway 経由でデプロイした際に以下が起きた:

1. `terraform apply` 時に警告:
   > Operation does not require an API key; callers may invoke the method without specifying an associated API-consuming project. To enable an API key, all Security Requirements Objects for the operation must reference at least one Security Scheme of type 'apiKey'.
2. apply 自体は通る (warning 扱い)
3. 本番テストで `GET /healthz` が **HTTP 404** を返す (Google Frontend HTML、API Gateway の handler に届かない)
4. つまり API Gateway は **API Key 認証を持たない operation を service config に含めない** 仕様。`/healthz` operation は config から落とされ、結果 routing table に存在しない

GCP API Gateway は「すべての operation は API 消費者プロジェクトを識別できる必要がある」という設計で、API Key も JWT もない anonymous operation は受け付けない。warning は **実質 ERROR と同等の効果** だった。

## Decision

`/healthz` も **API Key 認証を必須にする**:

- `api/openapi.yaml` の `/healthz` から `security: []` を削除
- global `security: [google_api_key: []]` を継承させる

ADR 0001 の本文は immutability ルールに従い編集しない。本 ADR を Supplements として併読する形にする。

## Consequences

- 外形監視ツール (Cloudflare Worker / Healthcheck.io / GCP Uptime Check 等) は `X-API-Key` ヘッダに API Key を含めて `/healthz` を叩く必要がある
- [docs/security.md](../security.md) D1 の「`/healthz` は Cloudflare 側で Cache / Rate Limit を効かせる」方針は、Cache rule のみ機能継続。Rate Limit は API Gateway の API Key 検証で代替され、Cloudflare 側で別途 Rate Limit を入れる必要性は薄れる (D5 の `max_instance_count` 物理キャップで吸収される)
- API Key が漏洩すると `/healthz` も無制限で叩けるので、key rotation の運用設計時にこの operation も含めて考える
- 「API Gateway を介さず Cloudflare Worker で `/healthz` の固定レスポンスを返す」案は将来検討余地あり (本 ADR では採用しない、外形監視に Cloud Function 起動まで含めた疎通確認をしたい意図)
- 別 ADR で「`/healthz` を API Gateway 経由ではなく Cloudflare Worker で完結させる」方針に転換する選択肢を残す
