# ADR 0012: `/{healthz_path}` wildcard で healthz を routing する

- **Date**: 2026-06-22
- **Status**: Accepted
- **Supersedes**: [0011](0011-healthz-canonical-path.md)

## Context

[ADR 0011](0011-healthz-canonical-path.md) の決定（`GET /healthz` exact path、`CONSTANT_ADDRESS`、`healthz_backend.address: ${healthz_url}/`）を apply し、実測した結果が以下だった。

```text
GET /healthz   -> 404 (Google Frontend HTML)
GET /healthz/  -> 200 {"status":"ok"}
```

生成された Service Management config 上は `get: "/healthz"` が存在していた。しかし `/healthz` は API Gateway の request log に出ず、Google Frontend 層で 404 を返していた。ESP が exact path `/healthz`（trailing slash なし）を routing しない挙動が確認された。

## Decision

OpenAPI `paths` の healthz 定義を `GET /{healthz_path}` に変更し、single wildcard routing を使う。

- `path_translation` を `APPEND_PATH_TO_ADDRESS` に変更し、実リクエスト path を backend に渡す
- Cloud Function 側で `request.path` を検証し、`/healthz` 以外は 404 を返す
- `jwt_audience` は `${healthz_url}` のまま維持する

## Consequences

- API Gateway の route が 1 セグメント wildcard になる（`/healthz`、`/healthz/` の両方を同じ operation に流せる）
- `/foo` のような任意の 1 セグメント GET も Gateway routing 上は healthz operation に到達し得るが、Cloud Function が 404 を返す
- Cloud Function の再デプロイが必要（`main.py` の path 検証追加）
- API Gateway config の差し替えが必要

## References

- [API Gateway path templating](https://cloud.google.com/api-gateway/docs/path-templating)
- [API Gateway OpenAPI 3.x extensions](https://cloud.google.com/api-gateway/docs/oasv3-extensions)
