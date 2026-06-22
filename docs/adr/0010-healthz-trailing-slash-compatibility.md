# ADR 0010: `/healthz` と `/healthz/` を両方受ける

- **Date**: 2026-06-22
- **Status**: Accepted
- **Supplements**: [0008](0008-healthz-api-key-required.md)

## Context

[ADR 0008](0008-healthz-api-key-required.md) で `/healthz` も API Key 必須にした。その後、GCP API Gateway へ apply 済みの gateway を実測したところ、以下の挙動になった。

```text
GET /healthz   -> 404 Google Frontend HTML
GET /healthz/  -> 200 {"status":"ok"}
```

API Key は正しく付与した状態で確認しているため、これは認証エラーではない。Cloudflare 経由だけでなく API Gateway default hostname 直でも同じ挙動だったため、DNS / Cloudflare でもない。

`x-google-backend.path_translation` は backend へ渡す URL の制御であり、API Gateway が operation を見つける前段の path matching を解決しない。

## Decision

`api/openapi.yaml` に以下の2つを明示的に定義する。

- `GET /healthz`
- `GET /healthz/`

どちらも同じ `healthz_backend` を参照し、global `security` を継承して API Key 必須とする。

`operationId` は OpenAPI 上で一意にする必要があるため、`/healthz/` 側は `healthzTrailingSlash` とする。

## Consequences

- 利用者や監視ツールは `/healthz` / `/healthz/` のどちらでも疎通確認できる
- Cloud Function 側は path を見ないため、backend 実装は変更しない
- API Gateway config の差し替えが必要
- 今後、他の endpoint では末尾スラッシュ有無を安易に両対応しない。今回の対応は health check の互換性と運用安定性を優先した例外とする
