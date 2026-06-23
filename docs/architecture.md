# システムアーキテクチャ

## 概要

テキスト・画像・PDF・動画・音声を統一ベクトル空間に格納し、自然言語クエリで横断検索できる個人向けサーバーレス・ベクトル検索システム。

---

## 全体構成図

```mermaid
flowchart LR
    C["クライアント\nBrowser / CLI"]

    subgraph CF["Cloudflare"]
        CFW["Cloudflare Worker\nHost Header Rewrite\nADR-0014"]
    end

    subgraph GCP["Google Cloud Platform"]
        APIGW["API Gateway\nX-API-Key Auth\nADR-0003"]
        HZ["healthz\nGET /health\n128Mi / 10s"]
        VA["vector-api\nPOST /v1/documents\nPOST /v1/documents/upload-url\nPOST /v1/search\n1Gi / 120s"]
        FS[("Firestore\ndocuments\n2048-dim COSINE\nADR-0001")]
        GCS[("GCS media-inputs\ninputs/{uuid}.ext\n30日 TTL")]
        SM["Secret Manager\nGEMINI_API_KEY\nADR-0006"]
    end

    subgraph AI["Google AI"]
        GEMINI["Gemini Embedding API\ngemini-embedding-2\n2048-dim\nADR-0016"]
    end

    C -->|"HTTPS + X-API-Key"| CFW
    CFW --> APIGW
    APIGW -->|"GET /health"| HZ
    APIGW -->|"POST /v1/*"| VA
    VA --> FS
    VA -->|"Signed URL 発行 / DL"| GCS
    VA -.->|"API Key 取得"| SM
    VA -->|"embed_content\nPart.from_bytes"| GEMINI
    C -. "PUT binary\n直接アップロード" .-> GCS

    style C fill:#dae8fc,stroke:#6c8ebf
    style GCP fill:#e8f4fb,stroke:#4285f4
    style CF fill:#fff2cc,stroke:#d6b656
    style AI fill:#fce4ec,stroke:#c62828
    style HZ fill:#d5e8d4,stroke:#82b366
    style VA fill:#d5e8d4,stroke:#82b366
    style FS fill:#e1d5e7,stroke:#9673a6
    style GCS fill:#e1d5e7,stroke:#9673a6
    style SM fill:#f8cecc,stroke:#b85450
```

---

## コンポーネント一覧

| コンポーネント           | 種別                 | 役割                                                                                |
| ------------------------ | -------------------- | ----------------------------------------------------------------------------------- |
| **Cloudflare Worker**    | Edge Proxy           | カスタムドメインから GCP API Gateway へ Host ヘッダを書き換えてプロキシ（ADR-0014） |
| **API Gateway**          | GCP Managed          | X-API-Key 認証。全エンドポイントの入口。Cloud Functions へルーティング（ADR-0003）  |
| **healthz**              | Cloud Functions Gen2 | `GET /health` 死活監視専用。128Mi / 10s タイムアウト                                |
| **vector-api**           | Cloud Functions Gen2 | ドキュメント登録・検索・メディアアップロード URL 発行。1Gi / 120s タイムアウト      |
| **Firestore**            | GCP Managed DB       | ドキュメントとベクトルを保存。2048-dim FLAT インデックス (COSINE 距離)（ADR-0001）  |
| **GCS media-inputs**     | GCP Storage          | メディアバイナリ一時保管。クライアントが Signed URL で直接 PUT する（ADR-0017）     |
| **Secret Manager**       | GCP Managed          | Gemini API Key を安全に注入（ADR-0006）                                             |
| **Gemini Embedding API** | Google AI (外部)     | `gemini-embedding-2` でテキスト・メディアを 2048-dim ベクトルに変換（ADR-0016）     |

---

## 主要フロー

### テキスト登録

```mermaid
sequenceDiagram
    participant C as クライアント
    participant GW as API Gateway
    participant VA as vector-api
    participant G as Gemini API
    participant FS as Firestore

    C->>GW: POST /v1/documents<br/>{text, metadata?}
    GW->>VA: (X-API-Key 検証済み)
    VA->>G: embed_content([text])
    G-->>VA: vector[2048]
    VA->>FS: documents.add({text, embedding, metadata})
    FS-->>VA: document id
    VA-->>C: 201 Created {id, text, created_at}
```

### メディア登録（画像・PDF・動画・音声）

```mermaid
sequenceDiagram
    participant C as クライアント
    participant GW as API Gateway
    participant VA as vector-api
    participant GCS as GCS media-inputs
    participant G as Gemini API
    participant FS as Firestore

    Note over C,VA: ① Signed URL 取得
    C->>GW: POST /v1/documents/upload-url<br/>{filename, content_type}
    GW->>VA: (X-API-Key 検証済み)
    VA->>VA: inputs/{uuid4()}.ext を採番
    VA->>GCS: generate_signed_url(V4, PUT, 5min)
    GCS-->>VA: signed URL
    VA-->>C: {upload_url, gcs_uri}

    Note over C,GCS: ② GCS へ直接 PUT（API Gateway を経由しない）
    C->>GCS: PUT {upload_url}<br/>Content-Type ヘッダ付き
    GCS-->>C: 200 OK

    Note over C,FS: ③ 埋め込み登録
    C->>GW: POST /v1/documents<br/>{gcs_uri, text?, metadata?}
    GW->>VA: (X-API-Key 検証済み)
    VA->>GCS: blob.download_as_bytes()
    GCS-->>VA: bytes + mime_type
    VA->>G: embed_content([text?, Part.from_bytes(data, mime_type)])
    G-->>VA: vector[2048]
    VA->>FS: documents.add({gcs_uri, text?, embedding, metadata})
    FS-->>VA: document id
    VA-->>C: 201 Created {id, gcs_uri, created_at}
```

### ベクトル検索

```mermaid
sequenceDiagram
    participant C as クライアント
    participant GW as API Gateway
    participant VA as vector-api
    participant G as Gemini API
    participant FS as Firestore

    C->>GW: POST /v1/search<br/>{query, top_k}
    GW->>VA: (X-API-Key 検証済み)
    VA->>G: embed_content([query])
    G-->>VA: query_vector[2048]
    VA->>FS: find_nearest(COSINE, top_k)
    FS-->>VA: [{id, text, gcs_uri, metadata, distance}]
    VA->>VA: score = 1 - distance
    VA-->>C: 200 OK<br/>{results: [{id, text, gcs_uri, score}]}
```

---

## インフラ構成

| リソース               | 管理方法                                                    |
| ---------------------- | ----------------------------------------------------------- |
| GCP リソース全体       | Terraform (`terraform/gcp/`)                                |
| Cloudflare Worker      | Terraform (`terraform/cloudflare/`)                         |
| API Gateway 設定       | OpenAPI テンプレート (`api/openapi.yaml`)                   |
| Cloud Functions コード | Python 3.13 (`functions/vector-api/`, `functions/healthz/`) |
| Gemini API Key         | SOPS + KMS 暗号化 → Secret Manager（ADR-0006）              |

---

## セキュリティ設計

詳細は `docs/security.md` 参照。主要ポイント:

- **認証**: API Gateway 段で X-API-Key 検証（ADR-0003）。Cloud Functions は IAM で API GW からのみ受け付ける
- **最小権限**: 関数ごとに専用 Service Account。healthz は Firestore/Storage へのアクセス権なし
- **メディアバケット**: Public access prevention enforced / Uniform bucket-level access
- **Signed URL**: 5 分間のみ有効。Content-Type が署名時と一致しない場合 GCS が 403 を返す
- **スケール上限**: Cloud Functions max_instance_count = 3（ADR-0005 / D5）

---

## ADR 索引

| ADR                                                          | 内容                                                            |
| ------------------------------------------------------------ | --------------------------------------------------------------- |
| [0001](adr/0001-api-design-mvp.md)                           | API MVP 設計（エンドポイント・ID・スコア・エラー形式）          |
| [0003](adr/0003-authentication.md)                           | X-API-Key ヘッダ認証                                            |
| [0005](adr/0005-cloud-functions-runtime-stack.md)            | Cloud Functions Gen2 / Python / 関数分割粒度                    |
| [0006](adr/0006-secret-management-sops-kms.md)               | SOPS + KMS による Secret 管理                                   |
| [0014](adr/0014-cloudflare-worker-host-rewrite.md)           | Cloudflare Worker で Host ヘッダを書き換えて API Gateway へ接続 |
| [0016](adr/0016-embedding-dimension-2048-firestore-limit.md) | 埋め込み次元を 2048 に確定（Firestore 上限）                    |
| [0017](adr/0017-multimodal-media-upload-pattern.md)          | GCS Signed URL 直アップロード & Part.from_bytes                 |
