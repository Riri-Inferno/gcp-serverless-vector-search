# ADR 0004: Firestore ドキュメントに `embedding_model` フィールドを追加

- **Date**: 2026-06-20
- **Status**: Accepted
- **Supplements**: [0001](0001-api-design-mvp.md)

## Context

[0001](0001-api-design-mvp.md) で確定した Firestore ドキュメント構造は以下：

```text
documents/{uuid}:
  text:       string
  metadata:   object
  embedding:  vector(1536)
```

このスキーマには「**どのエンベディングモデルで生成されたベクトルか**」を示すフィールドが無い。

`gcp-serverless-vector-search` は将来的に以下のシナリオを抱える：

- `gemini-embedding-2` から後継モデル (例: `gemini-embedding-3`) への切替
- Google AI Studio 経由から Vertex AI 経由への切替（同モデルでもエンドポイント変更）
- マルチモーダル拡張に伴う `multimodal-embedding-001` 等への部分置換

これらが起きたとき、**既存ドキュメントがどのモデルで埋め込まれたかを判別できないと**、再エンベディング判断や検索結果のバージョン混在検出ができなくなる。違うモデルのベクトル空間は互換性が無いため、混在すると検索精度が壊滅する。

## Decision

Firestore ドキュメントに `embedding_model` フィールド (string) を**必須**で追加する。

```text
documents/{uuid}:
  text:             string
  metadata:         object         (自由形式)
  embedding:        vector(1536)
  embedding_model:  string         (例: "gemini-embedding-2")
  // createTime / updateTime は Firestore が自動付与
```

### 書き込み時の動作

- Cloud Functions の登録ハンドラが、設定/環境変数で持っている**現在のエンベディングモデル名**をそのまま値として書き込む
- 値の例: `"gemini-embedding-2"`（ハイフン付きの公式モデル ID をそのまま使用）
- バージョン番号やリージョン情報は含めない（モデル名 1 文字列のみ）

### API レスポンスへの露出

**しない** ([0001](0001-api-design-mvp.md) の `Document` / `SearchResult` スキーマは変更しない)。`embedding_model` は内部実装詳細であり、クライアント側で扱う想定がない。将来「同モデルのドキュメントのみで検索」のような機能を出す段で expose を再検討する。

### 検索時の扱い

MVP では検索時に `embedding_model` でのフィルタリングはしない（クエリ側でクライアントが現在のモデルで埋め込みベクトルを作って投げ、Firestore の `find_nearest` を実行するだけ）。

ただし**運用上の前提**として「インデックス内の全ドキュメントが同じ `embedding_model` 値」を保つ。モデル切替時は全件再エンベディングまたは並走運用（別コレクション）を選択する。

## Consequences

- Cloud Functions の登録ハンドラ実装に、現在のモデル名を `embedding_model` として書き込む 1 行が増える
- OpenAPI 仕様 (`api/openapi.yaml`) は変更不要（API には露出しないため）
- Firestore のベクトルインデックス自体は `embedding` フィールドのみが対象なので、インデックス定義の変更も不要
- 将来モデル切替時、`embedding_model` フィールドを WHERE 句相当（Firestore では `where()` メソッド）で絞り込みつつ並走運用する余地が生まれる
- ストレージコスト微増（1 ドキュメントあたり数十バイト）— 個人ラボ規模では誤差
