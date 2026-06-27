# ADR 0016: 埋め込みベクトルの次元数を 3072 → 2048 に修正（Firestore インデックス上限）

- **Date**: 2026-06-23
- **Status**: Accepted
- **Supersedes**: [0015](0015-embedding-dimension-3072.md)

## Context

[ADR 0015](0015-embedding-dimension-3072.md) で埋め込み次元を `3072` に変更することを決定し、実際に `terraform apply` を実行した。しかし以下のエラーで apply が失敗した：

```
Error: Error creating Index: googleapi: Error 400: Invalid dimension 3072 on field path embedding.
The dimension must be larger than 0 and less than or equal to 2048.
```

**Firestore のベクトルインデックスは最大 2048次元が上限**であることが判明した。`gemini-embedding-2` モデル自体は `output_dimensionality` に 3072 を指定できるが、インデックス側が受け付けない。この制約は公式ドキュメントに明記されておらず、apply 時に初めて判明した。

## Decision

`output_dimensionality` および Firestore インデックスの `dimension` を `3072` → `2048` に修正する。

- `2048` は Firestore が許容する最大次元数
- `output_dimensionality` は切り詰め処理のため、3072 も 2048 も モデル側の計算コストは変わらない
- 1536（旧値）より高精度、3072（Firestore 非対応）の次善策として最大値を採用

**変更箇所:**

| ファイル                       | 変更内容                              |
| ------------------------------ | ------------------------------------- |
| `functions/vector-api/main.py` | `EMBEDDING_DIMENSION = 3072` → `2048` |
| `terraform/gcp/firestore.tf`   | `dimension = 3072` → `2048`           |
| `docs/multimodal-design.md`    | 図・本文の `3072` を `2048` に修正    |
| `README.md`                    | `3072次元` → `2048次元`               |

## Consequences

- Firestore ベクトルインデックスは apply 失敗時に既に削除されていたため、再作成される
- `documents` コレクションは apply 前に削除済み（ADR 0015 適用時に実施）
- 将来 Firestore がインデックス次元上限を 3072 以上に引き上げた場合、再度移行を検討する
