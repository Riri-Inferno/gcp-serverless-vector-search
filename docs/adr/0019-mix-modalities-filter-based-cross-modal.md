# ADR 0019: クロスモーダル検索を filter ベースで実装 (`mix_modalities`)

- **Date**: 2026-06-24
- **Status**: Accepted
- **Supplements**: [0001](0001-api-design-mvp.md), [0017](0017-multimodal-media-upload-pattern.md)

## Context

[ADR 0001](0001-api-design-mvp.md) で API 仕様を確定し、[ADR 0017](0017-multimodal-media-upload-pattern.md) でマルチモーダルメディア (画像 / PDF / 動画 / 音声) のアップロード経路を実装した。デモ UI からテキスト / 画像両方の登録・検索ができる状態に到達した。

しかし 2026-06-23 の実測で、Gemini Embedding API (`gemini-embedding-2`) の **modality gap が極端に大きい** ことが判明した。

### 実測データ (2026-06-23)

3 種類のテキストクエリで `top_k=50` を計測したところ、**すべてのケースで 50 / 50 件が TXT modality、IMG が 1 件もヒットしない** 結果になった:

| クエリ | TXT | IMG | score range |
|---|---|---|---|
| `"猫"` | 50 | 0 | 0.55 〜 0.72 |
| `"犬"` | 50 | 0 | 0.56 〜 上位不明 |
| `"吾輩は猫である"` | 50 | 0 | 0.49 〜 0.79 |
| `"動物"`（抽象クエリ） | 50 | 0 | (sample 取れず) |

公式ドキュメントは "All modalities are mapped into the same embedding space, enabling cross-modal search and comparison." と謳っているが、**実態としてはテキスト / 画像クラスタが cosine 距離上で大きく分離しており、テキストクエリで画像が `top_k=50` に入ることがない**。これは distance metric 変更や centering のような軽量な計算工夫では太刀打ちが難しいレベルの gap。

計測コマンドおよび全 50 件のスコア詳細は [`docs/measurements/2026-06-23-modality-gap.md`](../measurements/2026-06-23-modality-gap.md) を参照。

### 検討した代替手段

| 手段 | 評価 |
|---|---|
| 距離メトリクス変更 (COSINE → DOT_PRODUCT / EUCLIDEAN) | 効果限定的と判断 (gap が大きすぎる) |
| Centering / 再ランキング | 中央化に必要な平均ベクトルの保守が複雑、効果も実測未確認 |
| クエリ拡張 (`"a photo of {query}"` を併用) | 効果未知、small 改善見込み |
| **Vertex AI `multimodalembedding@001` への切替** | **真の解決** だが、Vertex AI は個人開発で直接的な API 課金が発生するため見送り。実務知見でカバー可能 |
| **filter ベースで擬似クロスモーダル** (本 ADR) | joint embedding 思想を妥協する代わりに demo を成立させる現実解 |

## Decision

`/v1/search` に **`mix_modalities`** パラメータ (bool, default `false`) を追加し、`true` のとき **同モダリティで `top_k/2` + 異モダリティで `top_k/2`** を Firestore に 2 回問い合わせて merge する。

### データモデル拡張

documents コレクションに **`modality`** フィールド (string) を追加する:

```text
documents/{uuid}:
  text:             string | null
  gcs_uri:          string | null
  metadata:         object  (自由形式)
  embedding:        vector(2048)
  embedding_model:  string         ("gemini-embedding-2")
  modality:         string         ("text" | "image" | "audio" | "video" | "pdf")
  created_at:       timestamp      (Firestore 自動)
```

`modality` の派生ルール:

| 入力 | modality |
|---|---|
| `text` のみ                 | `text`  |
| `gcs_uri` に `image/*`     | `image` |
| `gcs_uri` に `video/*`     | `video` |
| `gcs_uri` に `audio/*`     | `audio` |
| `gcs_uri` に `application/pdf` | `pdf` |
| `text` + `gcs_uri` 両方        | **`gcs_uri` 側のモダリティを優先** (主たるメディア種別を採用) |

### Firestore composite vector index 追加

```hcl
resource "google_firestore_index" "documents_modality_embedding" {
  collection  = "documents"
  query_scope = "COLLECTION"

  fields {
    field_path = "modality"
    order      = "ASCENDING"
  }
  fields {
    field_path = "__name__"
    order      = "ASCENDING"
  }
  fields {
    field_path = "embedding"
    vector_config {
      dimension = 2048
      flat {}
    }
  }
}
```

既存の single field vector index (`__name__` + `embedding`) は **そのまま残す**。`mix_modalities=false` のとき従来通り使う。

### Search ロジック

`mix_modalities=true` のとき:

```python
query_modality = derive_modality(payload.gcs_uri, payload.query)  # "image" or "text" 等
same_modality_results  = collection.where("modality", "==", query_modality) \
                                   .find_nearest(..., limit=top_k // 2)
other_modality_results = collection.where("modality", "!=", query_modality) \
                                   .find_nearest(..., limit=top_k - top_k // 2)
results = sorted(same + other, key=lambda r: r.score, reverse=True)
```

`mix_modalities=false` のとき: 従来通り (single index で `find_nearest`)、フィルタなし。

### フロント UI

検索エリアに **「クロスモーダル表示」トグル** を追加。`true` のとき API リクエストに `mix_modalities: true` を含める。

## Consequences

### Positive

- **demo として「テキストクエリで画像も出る / 画像クエリでテキストも出る」が成立する**
- `mix_modalities=false` がデフォルトのため、既存クライアントへの後方互換性を維持
- `modality` フィールドは将来 Vertex AI multimodal 切替時にも残せる (strict joint embedding でも害がない)
- Firestore composite vector index のサポートを実証できる (技術的 showcase 価値)

### Negative / Trade-offs

- **joint embedding 思想の一部妥協**: 「同じベクトル空間に射影される」のが売りだったが、検索時に modality で物理的に分離して取得することになる
- 既存 documents コレクションは全削除し、`modality` フィールド付きで再投入が必要 (本 ADR 採択前にユーザーが実施済み)
- composite vector index の apply 待ちが発生 (数分)
- Cloud Function の保存ロジックで `modality` 派生処理が追加される (軽量)
- 真のクロスモーダル能力の解決ではなく **demo を成立させるための迂回策**。将来 Vertex AI `multimodalembedding` 等への切替で本質的に解決する可能性は残す (低優先、別 ADR で検討)

### 思想変更の正直な記録

ADR 0001 / 0017 では「joint embedding を活かしたクロスモーダル検索」を想定していたが、本 ADR で **filter ベースの擬似クロスモーダルに方針転換** する。これは Gemini Embedding API の実測 modality gap が想定より大きかったための判断であり、設計思想の妥協を含む。

将来、より強いクロスモーダル能力を持つモデル (例: Vertex AI `multimodalembedding@001`) への切替が実行可能になった場合、`mix_modalities` パラメータは廃止せず、「modality filter として明示的に使いたい用途」(例: 「画像だけ検索」「テキストだけ検索」) に転用できる。

## References

- [ADR 0001](0001-api-design-mvp.md): API MVP 設計
- [ADR 0006](0006-secret-management-sops-kms.md): Gemini API Key 管理 (本 ADR で維持)
- [ADR 0017](0017-multimodal-media-upload-pattern.md): マルチモーダルメディアアップロード経路
- [Firestore Vector Search docs (公式)](https://firebase.google.com/docs/firestore/vector-search): WHERE filter + find_nearest の composite index サポート
