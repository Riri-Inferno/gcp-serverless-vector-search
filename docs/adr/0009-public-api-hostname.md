# ADR 0009: 公開 API ホスト名を `vector-search.riri-inferno.com` に変更

- **Date**: 2026-06-22
- **Status**: Accepted
- **Supplements**: [0001](0001-api-design-mvp.md)

## Context

[ADR 0001](0001-api-design-mvp.md) では API MVP のエンドポイントを決めたが、公開ホスト名は README / OpenAPI 上で `vector-search.api.riri-inferno.com` としていた。

このホスト名は `riri-inferno.com` から見て深いサブドメインであり、Cloudflare Universal SSL の full setup における標準カバレッジ外になる。Cloudflare のドキュメントでは、Universal SSL は root domain と first-level subdomain を対象とし、より深い subdomain には Advanced Certificate Manager / Total TLS などの追加対応が必要とされている。

個人ラボの API で月額オプションを増やすより、first-level subdomain に寄せて無料の Universal SSL 範囲内で運用する方が目的に合う。

参考:

- Cloudflare Universal SSL limitations: <https://developers.cloudflare.com/ssl/edge-certificates/universal-ssl/limitations/>
- Cloudflare Advanced certificates: <https://developers.cloudflare.com/ssl/edge-certificates/advanced-certificate-manager/>

## Decision

公開 API ホスト名を次に変更する:

```text
before: vector-search.api.riri-inferno.com
after:  vector-search.riri-inferno.com
```

Cloudflare DNS は `home-raspi-iac` の `terraform/cloudflare/` で一元管理する。本リポジトリでは Cloudflare resource を持たず、OpenAPI `servers.url` とドキュメント上の公開 URL だけを更新する。

DNS record は以下の CNAME とする:

```text
vector-search.riri-inferno.com -> vector-search-gateway-dzqjqk3y.an.gateway.dev
```

## Consequences

- `api/openapi.yaml` の `servers.url` は `https://vector-search.riri-inferno.com` になる
- README などの利用者向け URL も同じホスト名へ更新する
- Cloudflare 側の DNS record は `home-raspi-iac` で追加し、GCP 側の API Gateway / Cloud Functions とは分離して管理する
- 古い `vector-search.api.riri-inferno.com` は正式な公開 URL として扱わない
- 将来、深いサブドメインを使う必要が出た場合は Advanced Certificate Manager / Total TLS / custom certificate の採用を別 ADR で再評価する
