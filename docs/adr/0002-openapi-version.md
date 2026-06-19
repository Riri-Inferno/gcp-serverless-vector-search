# ADR 0002: OpenAPI バージョンは 3.0.4 を採用

- **Date**: 2026-06-19
- **Status**: Accepted

## Context

GCP API Gateway の OpenAPI 設定として使うバージョンを決める必要がある。

歴史的経緯として、API Gateway は長らく **OpenAPI 2.0 (Swagger 2.0) のみ** をサポートしていたが、現在は **3.x もサポートされている**（公式ドキュメントに 3.x 用の API Key 認証サンプルが掲載されている）。

参考: [Authenticate API requests with API keys (OpenAPI 3.x)](https://docs.cloud.google.com/api-gateway/docs/authenticate-api-keys?hl=ja#openapi-3.x)

参考: [Stop Downgrading Your Specs: Is Your API Gateway Speaking Modern OpenAPI?](https://discuss.google.dev/t/stop-downgrading-your-specs-is-your-api-gateway-speaking-modern-openapi/298523)

## Decision

**OpenAPI 3.0.4** を採用する。

決定理由は **GCP 公式ドキュメントの API Gateway サンプル（OpenAPI 3.x + API Key 認証）がそのまま `openapi: 3.0.4` で記述されており、これを素直に踏襲する** こと。公式が「動く前提」で示している記法・バージョンに揃えることで、ベンダー側の保証範囲内に留まり、追従コストを最小化できる。

補足として 3.1 系は採用しない: 公式サンプル上に 3.1 の例が現れておらず、また 3.1 は JSON Schema との互換ルールが 3.0 から変わるため、サポート可否と挙動差分の両面でリスクがある。現時点では 3.0 系に留めるのが妥当。

## Consequences

- 3.x の構造化された記述（`components/schemas`、`requestBody`、`oneOf` 等）が使える
- GCP 固有拡張（`x-google-backend` / `x-google-api-management` / `securitySchemes`）は 3.x 流儀で書く
- 2.x 用の古い Swagger ツールチェーン互換性は失うが、本リポジトリでは Swagger 2.x ツール依存はない
- 将来 3.1 / 4.x にアップグレードする場合は再評価し、新しい ADR を起こす
