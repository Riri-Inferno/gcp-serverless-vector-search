# マルチモーダル対応設計（メディア登録 / 検索）

テキスト専用だった MVP に対して、画像・音声などのメディアを登録・検索できるようにする拡張。
クライアントからバックエンドへのバイナリ直送を避け、GCS 署名付き URL 経由でブラウザから直接アップロードさせる設計を採用する。

---

## 全体アーキテクチャ

```mermaid
flowchart TD
    Client([クライアント<br/>ブラウザ / アプリ])

    subgraph Step1["① 署名付きURL取得"]
        GW1["API Gateway<br/>POST /v1/documents/upload-url"]
        Fn1["Cloud Functions<br/>vector-api<br/>handle_get_upload_url()"]
    end

    subgraph Step2["② GCSへ直接PUT"]
        GCS["GCS<br/>media-inputs バケット<br/>inputs/{uuid}.ext"]
    end

    subgraph Step3["③ ドキュメント登録"]
        GW2["API Gateway<br/>POST /v1/documents"]
        Fn2["Cloud Functions<br/>vector-api<br/>handle_create_document()"]
        Gemini["Gemini Embedding API<br/>gemini-embedding-2<br/>インターリーブ入力"]
        FS["Firestore<br/>documents/{uuid}"]
    end

    Client -->|X-API-Key + filename + content_type| GW1 --> Fn1
    Fn1 -->|upload_url + gcs_uri| Client
    Client -->|Content-Type ヘッダ付き PUT| GCS
    Client -->|X-API-Key + gcs_uri + text| GW2 --> Fn2
    Fn2 -- "Part.from_uri(gcs_uri) + text?" --> Gemini
    Gemini -->|1536次元ベクトル| Fn2
    Fn2 -->|embedding + gcs_uri + text| FS

    style Step1 fill:#dbeafe,stroke:#1e40af
    style Step2 fill:#fef3c7,stroke:#92400e
    style Step3 fill:#dcfce7,stroke:#166534
```

---

## メディア登録フロー（詳細）

### ① 署名付き URL 取得

クライアントはファイル名と MIME タイプを申告し、バックエンドが5分間だけ有効なGCS直アップ用URLを発行する。

```mermaid
sequenceDiagram
    participant C as クライアント
    participant GW as API Gateway
    participant Fn as Cloud Functions
    participant GCS as GCS

    C->>GW: POST /v1/documents/upload-url<br/>{"filename":"photo.jpg","content_type":"image/jpeg"}
    GW->>Fn: (X-API-Key 検証済み)
    Fn->>Fn: 拡張子を安全に抽出<br/>inputs/{uuid4()}.jpg にリネーム
    Fn->>GCS: generate_signed_url(method=PUT, expiration=5min, content_type)
    GCS-->>Fn: 署名付きURL
    Fn-->>GW: {"upload_url":"https://storage.googleapis.com/...","gcs_uri":"gs://..."}
    GW-->>C: 200 OK
```

**なぜ直アップを回避するか**

- Cloud Functions にバイナリを渡すと、関数の実行時間・メモリ・転送コストが跳ね上がる
- API Gateway には 32MB のリクエストボディ上限がある
- GCS 署名付き URL なら、バックエンドを経由せずにクライアントが直接 GCS へ PUT できるため、コスト・レイテンシ両方で有利

### ② クライアントから GCS へ直接 PUT

```
PUT {upload_url}
Content-Type: image/jpeg   ← 署名時に指定した MIME タイプと一致させる必要がある
Body: <バイナリ>
```

- 署名付き URL は5分間のみ有効（期限切れは 403）
- Content-Type が署名時と異なる場合も 403

### ③ ドキュメント登録

アップロード完了後、クライアントは `gcs_uri` を含めて `POST /v1/documents` を呼ぶ。
バックエンドは `text` と `gcs_uri` を混在させた**インターリーブ入力**で Gemini Embedding を呼び出す。

```mermaid
sequenceDiagram
    participant C as クライアント
    participant Fn as Cloud Functions
    participant Gemini as Gemini API
    participant FS as Firestore

    C->>Fn: POST /v1/documents<br/>{"gcs_uri":"gs://...","text":"任意","metadata":{}}
    Fn->>Fn: text / gcs_uri の存在チェック<br/>(少なくとも一方が必須)
    Fn->>Gemini: embed_content(<br/>  contents=[text?, Part.from_uri(gcs_uri)?],<br/>  task_type="RETRIEVAL_DOCUMENT"<br/>)
    Gemini-->>Fn: vector[1536]
    Fn->>FS: documents.add({<br/>  embedding, text, gcs_uri, metadata<br/>})
    FS-->>Fn: document id
    Fn-->>C: 201 Created {"id":...}
```

---

## マルチモーダル検索フロー

検索クエリはテキストのみ。テキスト埋め込みと保存済みメディア埋め込みを同一ベクトル空間で比較するため、自然言語クエリで画像や音声がヒットする。

```mermaid
sequenceDiagram
    participant C as クライアント
    participant Fn as Cloud Functions
    participant Gemini as Gemini API
    participant FS as Firestore

    C->>Fn: POST /v1/search<br/>{"query":"夕焼けの写真","top_k":10}
    Fn->>Gemini: embed_content(<br/>  contents=[query],<br/>  task_type="RETRIEVAL_QUERY"<br/>)
    Gemini-->>Fn: query_vector[1536]
    Fn->>FS: find_nearest(<br/>  query_vector,<br/>  distance_type=COSINE,<br/>  limit=top_k<br/>)
    FS-->>Fn: [{id, embedding, text, gcs_uri, metadata, distance}]
    Fn->>Fn: score = 1 - distance
    Fn-->>C: 200 OK<br/>{"results":[{id,text,gcs_uri,score,metadata}]}
```

**マルチモーダル検索が成立する仕組み**

Gemini の `gemini-embedding-2` はテキスト・画像・音声を**同一の1536次元ベクトル空間(次元数は設定可能)**に射影する。
登録時に `Part.from_uri()` で画像を埋め込んでいるため、「夕焼けの写真」というテキストクエリと、画像から生成されたベクトルが近傍に来る。

---

## API インターフェース仕様

### 新設: POST /v1/documents/upload-url

| 項目       | 内容                          |
| ---------- | ----------------------------- |
| 認証       | `X-API-Key`（既存と同様）     |
| リクエスト | `UploadUrlRequest`            |
| レスポンス | `UploadUrlResponse`           |
| レート     | 既存の `/v1/documents` と同等 |

**リクエスト**

```json
{
  "filename": "photo.jpg",
  "content_type": "image/jpeg"
}
```

**レスポンス**

```json
{
  "upload_url": "https://storage.googleapis.com/project-media-inputs/inputs/550e8400...jpg?X-Goog-Signature=...",
  "gcs_uri": "gs://project-media-inputs/inputs/550e8400-e29b-41d4-a716-446655440000.jpg"
}
```

### 変更: POST /v1/documents

`text` を任意に変更し、`gcs_uri` フィールドを追加。

| フィールド | 型     | 必須 | 変更点                                               |
| ---------- | ------ | ---- | ---------------------------------------------------- |
| `text`     | string | 任意 | required → optional（min_length=1, max_length=8000） |
| `gcs_uri`  | string | 任意 | **新規追加**（pattern: `^gs://.+`）                  |
| `metadata` | object | 任意 | 変更なし                                             |

> バリデーション規則: `text` と `gcs_uri` のどちらか一方は必ず存在する。両方なし → 400 Validation Error。

**メディアのみ登録の例**

```json
{
  "gcs_uri": "gs://project-media-inputs/inputs/550e8400.jpg",
  "metadata": { "source": "camera", "tags": ["landscape"] }
}
```

**テキスト＋メディア混在登録の例**

```json
{
  "text": "夕焼けの海岸で撮影した写真",
  "gcs_uri": "gs://project-media-inputs/inputs/550e8400.jpg",
  "metadata": { "category": "nature" }
}
```

### 変更なし: POST /v1/search

クエリ仕様はテキストのまま。検索結果の `SearchResult` に `gcs_uri` を追加する。

```json
{
  "results": [
    {
      "id": "abc123",
      "text": "夕焼けの海岸で撮影した写真",
      "gcs_uri": "gs://project-media-inputs/inputs/550e8400.jpg",
      "score": 0.94,
      "metadata": { "category": "nature" }
    }
  ]
}
```

---

## データモデル（Firestore）

```
documents/{uuid}:
  text:       string | null        # テキストのみ / テキスト+メディア登録時に存在
  gcs_uri:    string | null        # メディア登録時に存在 (gs://bucket/inputs/uuid.ext)
  metadata:   object               # 自由形式（既存）
  embedding:  vector(1536)         # Gemini gemini-embedding-2 の出力
  // createTime / updateTime は Firestore が自動付与
```

**埋め込みのインターリーブ入力パターン**

| 登録パターン       | `embed_content` の `contents`                |
| ------------------ | -------------------------------------------- |
| テキストのみ       | `["テキスト文字列"]`                         |
| メディアのみ       | `[Part.from_uri(gcs_uri)]`                   |
| テキスト＋メディア | `["テキスト文字列", Part.from_uri(gcs_uri)]` |

---

## GCS バケット構成

| 項目           | 内容                                                            |
| -------------- | --------------------------------------------------------------- |
| バケット名     | `{project_id}-media-inputs`                                     |
| リージョン     | `asia-northeast1`（Cloud Functions と同一）                     |
| 用途           | メディアバイナリの一時保管                                      |
| アクセス制御   | Uniform bucket-level access / Public access prevention enforced |
| ライフサイクル | 作成から30日で自動削除（デモデータの課金抑止）                  |
| CORS           | `PUT`, `OPTIONS` を許可（ブラウザ直アップ対応）                 |

**ファイルパス設計**

```
inputs/{uuid4()}.{ext}
```

- クライアントが申告したファイル名は使わない（パストラバーサル / 衝突を排除）
- 拡張子のみ安全に抽出して引き継ぐ

---

## IAM 設計

```mermaid
flowchart LR
    SA["vector-api-runtime\nサービスアカウント"]

    subgraph Bucket["GCS media-inputs バケット"]
        ObjAdmin["roles/storage.objectAdmin\nオブジェクト作成・確認・削除"]
    end

    subgraph SAIam["SA 自身への IAM"]
        TokenCreator["roles/iam.serviceAccountTokenCreator\nsignBlob (V4署名付きURL生成)"]
    end

    SA -->|バケットレベル| ObjAdmin
    SA -->|self-signing| TokenCreator
```

| ロール                                 | 付与先                                          | 理由                                                                                                                                  |
| -------------------------------------- | ----------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------- |
| `roles/storage.objectAdmin`            | `vector_api_runtime` SA → media-inputs バケット | 署名付きURL発行後のオブジェクト存在確認（`blob.exists()`）に読み取りが必要なため `objectCreator` では不足                             |
| `roles/iam.serviceAccountTokenCreator` | `vector_api_runtime` SA → 自分自身              | V4署名付きURLは内部で `iam.serviceAccounts.signBlob` を呼ぶ。Cloud Functions 環境では SA が自分自身に対してこのロールを持つ必要がある |

> **注意**: `signBlob` が呼べないと `generate_signed_url()` が `403 Forbidden` または `invalid_grant` で落ちる。デプロイ後に最初に必ず動作確認すること。

---

## バリデーション仕様

### UploadUrlRequest

| フィールド     | 型     | 制約                                |
| -------------- | ------ | ----------------------------------- |
| `filename`     | string | 必須 / 1文字以上                    |
| `content_type` | string | 必須 / 許可リストで検証（下記参照） |

**許可 MIME タイプ**（初期フェーズ）

```python
ALLOWED_CONTENT_TYPES = {
    "image/jpeg",
    "image/png",
    "image/webp",
    "image/gif",
    "audio/mp3",
    "audio/mpeg",
    "audio/wav",
    "audio/ogg",
    "video/mp4",   # Gemini が対応する場合
}
```

リスト外の MIME タイプは 400 Validation Error。

### DocumentCreateRequest（拡張後）

| 検証                              | 内容                                   |
| --------------------------------- | -------------------------------------- |
| `text` と `gcs_uri` 両方なし      | 400 `validation_error`                 |
| `text` が空文字列                 | 400 `validation_error`（min_length=1） |
| `gcs_uri` が `gs://` 始まりでない | 400 `validation_error`                 |
| `text` が 8000 文字超             | 400 `validation_error`                 |

---

## 制約・考慮事項

| 項目                    | 内容                                                                                                                                                                       |
| ----------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 署名付き URL の有効期限 | 5分。期限切れ後に PUT すると GCS が 403 を返す（バックエンドは検知しない）                                                                                                 |
| ファイルサイズ上限      | GCS 側は無制限だが、Gemini Embedding の入力上限に依存。大容量ファイルの埋め込みは失敗する可能性がある                                                                      |
| gcs_uri の所有確認      | 現実装では申告された `gcs_uri` が自バケット内かを検証しない。悪意ある URI を渡されると外部バケットの読み取りを試みる。本番化時にバケット名プレフィックスでフィルタすること |
| CORS origin             | 現在 `["*"]`。本番化の際は Firebase Hosting ドメイン等に絞ること                                                                                                           |
| ライフサイクル30日      | Firestore 側の `gcs_uri` フィールドは30日後にリンク切れになる。デモ用途前提の設計                                                                                          |
| Gemini インターリーブ   | テキストとメディアの順序は `embed_content` の仕様に従う。順序が検索精度に影響する可能性がある                                                                              |

---

## 関連リソース

| リソース               | 場所                                                                |
| ---------------------- | ------------------------------------------------------------------- |
| GCS バケット Terraform | [`terraform/gcp/media_bucket.tf`](../terraform/gcp/media_bucket.tf) |
| Cloud Functions 実装   | [`functions/vector-api/`](../functions/vector-api/)                 |
| OpenAPI 仕様           | [`api/openapi.yaml`](../api/openapi.yaml)                           |
| セキュリティ方針       | [`docs/security.md`](security.md)                                   |
| API MVP 設計           | [`docs/adr/0001-api-design-mvp.md`](adr/0001-api-design-mvp.md)     |
