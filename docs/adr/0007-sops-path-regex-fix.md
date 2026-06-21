# ADR 0007: `.sops.yaml` の `path_regex` を素ファイルにマッチさせる (ADR 0006 訂正)

- **Date**: 2026-06-21
- **Status**: Accepted
- **Supplements**: [0006](0006-secret-management-sops-kms.md)

## Context

[ADR 0006](0006-secret-management-sops-kms.md) で `.sops.yaml` のサンプルを次のように記載した:

```yaml
creation_rules:
  - path_regex: secrets/.*\.enc\.yaml$
    ...
```

この `path_regex` は暗号化済みファイル (`.enc.yaml`) **のみ** にマッチする。しかし `sops --encrypt <INPUT>` が `creation_rules` を解決する際は **入力ファイル名** に対して `path_regex` を評価する仕様であり、ユーザーが `secrets/gemini-api-key.yaml` (素ファイル) を入力に渡すと一致せず、以下のエラーで暗号化に失敗する:

```
error loading config: no matching creation rules found
```

PR-β1 (KMS / SOPS スタック追加) マージ後の初回 encrypt 試行で顕在化した。

## Decision

`.sops.yaml` の `path_regex` を **素ファイル `.yaml` にマッチするパターン** に修正する:

```yaml
creation_rules:
  - path_regex: secrets/.*\.yaml$
    encrypted_regex: ^.*$
    gcp_kms: projects/riri-vector-lab-2026/locations/global/keyRings/sops/cryptoKeys/sops-key
```

この regex は素ファイル (`secrets/foo.yaml`) と暗号化済みファイル (`secrets/foo.enc.yaml`) の両方にマッチするが、SOPS は **既に暗号化済みのファイルを再暗号化しようとしない** ため衝突しない。

ADR 0006 本文は **マージ済み (Accepted) の immutability ルール** に従い編集しない。実装側 (`.sops.yaml`) を ground truth とし、本 ADR で訂正を記録する。

## Consequences

- `sops --encrypt secrets/<name>.yaml > secrets/<name>.enc.yaml` のフローが正しく動作する
- ADR 0006 のサンプル 1 行は **本 ADR で上書き** として扱う。0006 を読む読者は本 ADR を併せて参照する必要がある (README index で本 ADR が 0006 を Supplement する旨を明示)
- 同様のサンプル誤記が将来発覚したら、同じパターンで「Supplements: X」付きの新 ADR を起こす
