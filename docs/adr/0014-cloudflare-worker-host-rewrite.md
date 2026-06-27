# ADR 0014: Cloudflare Worker で Host ヘッダを書き換えてカスタムドメインを GCP API Gateway に接続する

- **Status**: Accepted
- **Date**: 2026-06-22

## Context

ADR 0009 でカスタムドメイン `vector-search.riri-inferno.com` を公開 API ホスト名として採用した。
DNS は Cloudflare で `CNAME → vector-search-gateway-dzqjqk3y.an.gateway.dev`（proxied）として設定済みだが、
`https://vector-search.riri-inferno.com/health` を叩いても GCP API Gateway から 404 が返る問題が発覚した。

### 根本原因: HTTP Host ヘッダの不一致

Cloudflare がプロキシとして動作するとき、**クライアントが送った Host ヘッダ**（`vector-search.riri-inferno.com`）を
そのままオリジンに転送する。GCP API Gateway (ESP) は `*.gateway.dev` の Host ヘッダしか受け付けないため、
`vector-search.riri-inferno.com` が届くと 404 を返す。

DNS の CNAME はトラフィックをどの IP に届けるかを決めるだけであり、
HTTP レイヤーの Host ヘッダには影響しない。

### 検討した代替手段

| 手段                                                    | 結果                                                                          |
| ------------------------------------------------------- | ----------------------------------------------------------------------------- |
| Cloudflare Origin Rules（Host ヘッダ上書き）            | **Enterprise プラン専用**。Free/Pro/Business は宛先ポートの変更のみ対応       |
| Cloudflare Transform Rules（HTTP リクエストヘッダ変更） | `Host` ヘッダは HTTP 仕様上の forbidden header のため変更不可                 |
| 別の DNS プロバイダ経由でルートを変える                 | Host ヘッダの問題は DNS レイヤーでは解決できない。本質的に同じ問題が残る      |
| Cloudflare Workers                                      | Free プランで 100k req/day 無料。超過時は課金ではなく 1015 エラーで拒否される |

## Decision

**Cloudflare Worker** を使い、URL の hostname を `vector-search-gateway-dzqjqk3y.an.gateway.dev` に書き換えてから
GCP API Gateway へ転送する。

Workers runtime は `fetch()` の URL hostname から Host ヘッダを自動的に設定するため、
オリジンには正しい `Host: vector-search-gateway-dzqjqk3y.an.gateway.dev` が届く。

Worker スクリプト（`home-raspi-iac/terraform/cloudflare/workers/vector-search-proxy.js`）:

```javascript
const ORIGIN = "vector-search-gateway-dzqjqk3y.an.gateway.dev";

export default {
  async fetch(request) {
    const url = new URL(request.url);
    url.hostname = ORIGIN;
    return fetch(new Request(url.toString(), request));
  },
};
```

Terraform リソースは `home-raspi-iac/terraform/cloudflare/workers.tf` で管理し、
`cloudflare_workers_route` により `vector-search.riri-inferno.com/*` にバインドする。

## Consequences

### Positive

- Free プランで動作する（既存コスト増なし）
- API Key やパスはそのまま透過的に転送されるため、既存の認証・ルーティング設計（ADR 0003, 0009）に変更不要
- 超過時は課金ではなくエラーで失敗するため、コスト上振れのリスクがない

### Negative / Trade-offs

### Negative / Trade-offs

- **100k req/day の上限**: 個人ラボの外形監視用途では問題にならない想定だが、
  公開トラフィックが増えた場合は Workers Paid ($5/月) への移行が必要
- **Worker が経路に追加される**: Cloudflare エッジ → Worker → GCP の 2 ホップになるが、
  同一エッジ内での処理のため実測レイテンシへの影響は軽微
- **管理リポジトリが分かれる**: Worker の実装は `home-raspi-iac`、API の仕様は本リポジトリで管理する
