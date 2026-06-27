# Modality Gap 計測 — 2026-06-23

[ADR 0019](../adr/0019-mix-modalities-filter-based-cross-modal.md) の Context セクションで参照する実測データの詳細記録。

## 環境

| 項目 | 値 |
|---|---|
| 経路 | `https://vector-search.riri-inferno.com` (Cloudflare → API Gateway → Cloud Function) |
| データ | `documents` コレクションに約 100 件 (Kaggle 動物画像 50 枚 + 青空文庫テキスト数十件) |
| 埋め込みモデル | `gemini-embedding-2` / 出力次元 2048 |
| 検索エンジン | Firestore `find_nearest` / 距離関数 COSINE |
| 計測時刻 | 2026-06-23 15:08〜16:24 (JST) |

## 計測コマンド (再現用)

```bash
PROD=https://vector-search.riri-inferno.com
KEY=<API Key>   # terraform output -raw api_key

curl -sX POST "$PROD/v1/search" -H "x-api-key: $KEY" \
  -H 'Content-Type: application/json' \
  -d '{"query": "猫", "top_k": 50}' | \
  jq -r '.results | sort_by(-.score) | .[] | "\(.score | tostring | .[0:7]) \(if .gcs_uri then "IMG" else "TXT" end)"' | nl -ba
```

`{"query": "..."}` 部分を別クエリに差し替えて複数パターンを計測。

## 結果サマリ

| クエリ | TXT 件数 | IMG 件数 | score 最大 | score 最小 |
|---|---|---|---|---|
| `"猫"` | 50 | 0 | 0.7247 | 0.5504 |
| `"犬"` | 50 | 0 | (記録漏れ) | 0.5651 |
| `"吾輩は猫である"` | 50 | 0 | 0.7895 | 0.4937 |
| `"動物"` | 50 | 0 | (sample 取れず、画像 1 件もヒットせず) | (同左) |

**4 クエリ全てで top_k=50 が 100% TXT、画像が 1 件もランクインしない**。

## `"猫"` クエリの全 50 件 score (上位順)

```
rank   score    modality
   1   0.7247   TXT
   2   0.7119   TXT
   3   0.6993   TXT
   4   0.6603   TXT
   5   0.6551   TXT
   6   0.6406   TXT
   7   0.6390   TXT
   8   0.6364   TXT
   9   0.6345   TXT
  10   0.6331   TXT
  11   0.6285   TXT
  12   0.6233   TXT
  13   0.6233   TXT
  14   0.6226   TXT
  15   0.6222   TXT
  16   0.6219   TXT
  17   0.6203   TXT
  18   0.6191   TXT
  19   0.6170   TXT
  20   0.6162   TXT
  21   0.6153   TXT
  22   0.6140   TXT
  23   0.6137   TXT
  24   0.6136   TXT
  25   0.6121   TXT
  26   0.6116   TXT
  27   0.6113   TXT
  28   0.6107   TXT
  29   0.6100   TXT
  30   0.6087   TXT
  31   0.6084   TXT
  32   0.6066   TXT
  33   0.6062   TXT
  34   0.6061   TXT
  35   0.6056   TXT
  36   0.6023   TXT
  37   0.6018   TXT
  38   0.6017   TXT
  39   0.6012   TXT
  40   0.6007   TXT
  41   0.5996   TXT
  42   0.5974   TXT
  43   0.5960   TXT
  44   0.5935   TXT
  45   0.5895   TXT
  46   0.5871   TXT
  47   0.5853   TXT
  48   0.5843   TXT
  49   0.5801   TXT
  50   0.5504   TXT
```

## `"犬"` クエリの下位 15 件 score

(上位は記録漏れ、下位のみ取得)

```
rank   score    modality
  36   0.6076   TXT
  37   0.6075   TXT
  38   0.6075   TXT
  39   0.6071   TXT
  40   0.6062   TXT
  41   0.6033   TXT
  42   0.6028   TXT
  43   0.6011   TXT
  44   0.5984   TXT
  45   0.5983   TXT
  46   0.5969   TXT
  47   0.5937   TXT
  48   0.5928   TXT
  49   0.5896   TXT
  50   0.5651   TXT
```

## `"吾輩は猫である"` クエリ サマリ

```json
[
  {
    "modality": "TXT",
    "count": 50,
    "max": 0.7895386386397449,
    "min": 0.49367876866259053
  }
]
```

(IMG modality の集計エントリ自体が存在しない = 50 件中 IMG 0 件)

## 結論

- 全 4 クエリで 50 件中 50 件が同一モダリティ (TXT) で埋まり、画像が一切 `top_k=50` に入らない
- score 最低でも `0.4937` (`"吾輩は猫である"`) ── これより低いところに IMG が埋もれていると推定
- **計算工夫 (距離メトリクス変更 / centering / クエリ拡張) では実用上覆らないレベルの modality gap**
- 真の解決は Vertex AI `multimodalembedding@001` 等の CLIP ベースモデル切替だが、個人開発で API 直接課金が発生するため見送り
- 本計測の結果が ADR 0019 の filter ベースアプローチ採択の根拠となった
