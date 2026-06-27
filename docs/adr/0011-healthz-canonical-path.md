# ADR 0011: `/healthz` を canonical health check path とする

- **Date**: 2026-06-22
- **Status**: Accepted
- **Supersedes**: [0010](0010-healthz-trailing-slash-compatibility.md)
- **Supplements**: [0008](0008-healthz-api-key-required.md)

## Context

[ADR 0010](0010-healthz-trailing-slash-compatibility.md) では `GET /healthz` と `GET /healthz/` を OpenAPI `paths` に両方定義する方針にした。

しかし、Terraform apply 時の API Gateway config 作成で以下のエラーになった。

```text
Cannot convert to service config.
http: In path template '/healthz/': unexpected end of input '/'
```

GCP API Gateway の path templating は exact match と wildcard match を前提にしている。OpenAPI `paths` に末尾 slash の literal path を別 operation として定義する方式は採用しない。

## Decision

公開 API contract の health check は `GET /healthz` のみとする。

API Gateway から healthz Cloud Function へは `CONSTANT_ADDRESS` で転送する。backend の root path を明示するため、`healthz_backend.address` は `${healthz_url}/` とする。

`jwt_audience` は Cloud Run / Cloud Functions の audience として `${healthz_url}` のまま維持する。

## Consequences

- OpenAPI `paths` には `GET /healthz` のみを定義する
- `GET /healthz/` は正式な API contract に含めない
- Cloud Function 実装は path を厳格に固定しないまま維持する
- API Gateway config の差し替えが必要

## References

- [API Gateway path templating](https://cloud.google.com/api-gateway/docs/path-templating)
- [API Gateway OpenAPI 3.x extensions](https://cloud.google.com/api-gateway/docs/oasv3-extensions)
