# ADR 0013: health check パスを `/healthz` から `/health` に変更する

- **Date**: 2026-06-22
- **Status**: Accepted
- **Supersedes**: [0012](0012-healthz-wildcard-path-routing.md)

## Context

[ADR 0012](0012-healthz-wildcard-path-routing.md) の決定（`GET /{healthz_path}` wildcard + `APPEND_PATH_TO_ADDRESS`）を apply し実測した結果が以下だった。

```text
GET /healthz   -> 404 (Google Frontend HTML)
GET /healthz/  -> 405 Method Not Allowed (API Gateway 応答)
```

`GET /healthz` は引き続き API Gateway の request log に出ず、Google Frontend 層で 404 を返した。wildcard routing への変更でも改善しなかった。

調査の結果、GCP Cloud Run の公式 known issues に以下の記載が存在することを確認した。

> 末尾が z のパス。予約済みのパスとの競合を防ぐため、末尾が z のパスは避けることをおすすめします。
>
> — [Cloud Run の既知の問題](https://cloud.google.com/run/docs/known-issues?hl=ja)

Cloud Functions Gen2 は Cloud Run 上で動作する。API Gateway の ESP も Google のインフラ上に乗っているため、`/healthz`（末尾が z）は Google Frontend 層でインフラ予約済みパスとして処理され、アプリケーションに到達しない。これが一連の 404 の根本原因である。

## Decision

health check の公開パスを `GET /healthz` から `GET /health` に変更する。

- OpenAPI `paths` を `/health` に変更する
- `healthz_backend` を `CONSTANT_ADDRESS`、`address: ${healthz_url}/` に戻す（wildcard routing は不要）
- Cloud Function の path 検証は削除する（`CONSTANT_ADDRESS` では root に転送されるため不要）
- `operationId` は `healthz` のまま維持する（内部識別子のため公開パスと合わせる必要はない）

## Consequences

- 公開 API の health check contract が `GET /health` に変わる
- `GET /healthz` は廃止（API Gateway が 404 を返す）
- Cloud Function の実装はシンプルになる（method チェックのみ）
- API Gateway config の差し替えと Cloud Function の再デプロイが必要

## References

- [Cloud Run の既知の問題 — 予約済みの URL パス](https://cloud.google.com/run/docs/known-issues?hl=ja)
- [ADR 0008](0008-healthz-api-key-required.md): `/healthz` に API Key 必須とした経緯
- [ADR 0012](0012-healthz-wildcard-path-routing.md): wildcard routing を試みた経緯
