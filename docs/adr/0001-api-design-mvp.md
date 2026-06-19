# ADR 0001: API MVP 設計

- **Date**: 2026-06-19
- **Status**: Accepted

## Context

`riri-vector-lab-2026` のベクトル検索 API について、MVP として最初に公開するエンドポイント仕様、ドキュメントモデル、レスポンス形式の基本方針を決める必要がある。

ここが後から崩れると Firestore のドキュメント構造、Cloud Functions のハンドラ、API Gateway の OpenAPI 設定がすべて巻き戻るため、最初に契約を固める。

## Decision

### エンドポイント

MVP では以下の3本のみを提供する：

| メソッド | パス | 用途 | 認証 |
|----------|------|------|------|
| `POST` | `/v1/documents` | テキスト1件をベクトル化して保存 | 必要 |
| `POST` | `/v1/search`    | 自然言語クエリで近傍検索        | 必要 |
| `GET`  | `/healthz`      | 死活監視                       | 不要 |

検索が成立することを最短で確認するための最小セット。`GET/DELETE /v1/documents/{id}` やバルク登録は後追いで足す。

### ドキュメント ID

**サーバー側で UUID v4 を生成して返す**。クライアントから ID を指定する経路は MVP では用意しない。

- UUID v4 は 2^122 のエントロピーがあり、個人ラボ規模では衝突は事実上発生しない（隕石にあたって死ぬ確率より低い）
- Firestore が自前で `createTime` / `updateTime` を持つ（Cosmos DB の `_ts` 相当）ので、API レスポンスには `created_at` として返す

### メタデータ

**自由形式の JSON object** として保存する。スキーマは固定しない (`additionalProperties: true`)。

- 上限: シリアライズ後 **約 4KB** を目安
- 用途例: `source` (URL)、`category`、`tags[]`、`author` 等
- 検索結果に同梱して返す

**固定スキーマにしない理由**: 一度固いスキーマで公開すると後から緩めるのが難しい（既存クライアントが壊れる）。逆に緩いスキーマを後から段階的に絞ることは比較的容易。実務でスキーマ変更の地獄を見たことがあるため、初期は意図的にユルくする。

### スコア（検索結果）

`score` フィールドで **cosine similarity (0〜1、1 が同一)** を返す。

Firestore の `find_nearest` は cosine **distance** を返すため、Cloud Functions 側で `score = 1 - distance` に変換する。「距離」より「類似度」の方が API 利用者に直感的という判断。

### エラーフォーマット

RFC 7807 風の `application/problem+json` 形式を採用する。ただし `type` は URI ではなく短いスラグ文字列とする簡易版：

```json
{
  "type": "validation_error",
  "title": "Text exceeds max length",
  "status": 400,
  "detail": "field 'text' must be at most 8000 characters"
}
```

| フィールド | 必須 | 内容 |
|-----------|------|------|
| `type`   | ✓ | エラー種別のスラグ。`validation_error` / `unauthorized` / `payload_too_large` / `internal_error` 等 |
| `title`  | ✓ | 人間可読の簡潔メッセージ |
| `status` | ✓ | HTTP ステータスコード |
| `detail` |   | 詳細メッセージ（任意） |

シンプルな `{error, message}` 形式より将来の拡張余地（`detail`, `instance` 等）を確保できる。

## Consequences

- **Firestore のドキュメント構造**は概ね以下で固まる：

  ```text
  documents/{uuid}:
    text:       string
    metadata:   object  (自由形式)
    embedding:  vector(1536)
    // createTime / updateTime は Firestore が自動付与
  ```

- **Cloud Functions のハンドラ実装**はこの仕様を満たす形で書けばよい
- 取得 / 削除 / バルク登録 / メタデータフィルタ検索などは MVP に含めない。必要になったら別 ADR で議論
- メタデータの自由形式は将来「絞る方向」の変更余地を残す設計
- スコアを similarity に統一したため、Firestore から取得後に変換するコードが Cloud Functions に1行入る
