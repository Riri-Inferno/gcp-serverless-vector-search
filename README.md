# gcp-serverless-vector-search

GCP 上で動く、サーバーレス構成のマルチモーダル（テキスト＋画像）ベクトル検索システム。インフラは Terraform で管理。フロントエンドは Cloudflare Pages で配信。

- **API**: `https://vector-search.riri-inferno.com`
- **フロントエンド（デモ UI）**: <https://vector-search-demo.riri-inferno.com/>

---

## これは何か

テキスト・画像・PDF・動画・音声を統一ベクトル空間（2048 次元）に格納し、自然言語クエリや画像クエリで横断検索できる個人向けサーバーレスシステム。

| できること              | 補足                                                            |
| ----------------------- | --------------------------------------------------------------- |
| テキスト → テキスト検索 | 自然言語で類似ドキュメントを引く                                |
| テキスト → 画像検索     | テキストで類似画像を検索（クロスモーダル）                      |
| 画像 → 画像検索         | 画像で似た画像を検索                                            |
| テキスト＋画像 → 検索   | 両方を同時にクエリとして使うマルチモーダル検索                  |
| メディア登録            | 画像・動画・音声・PDF を GCS に直接アップロードし埋め込みを生成 |

---

## フロントエンド

ブラウザから API Key を入力するだけで、テキスト/画像検索・メディア登録が使える DEMO UI。

<!-- SCREENSHOT: デモUI全体のスクリーンショット（検索結果が表示されている状態）をここに貼ってください -->

### 検索モード

| モード         | 操作                                                   |
| -------------- | ------------------------------------------------------ |
| テキスト       | 検索ワードを入力して検索                               |
| 画像           | 画像をドロップまたはタップして選択し検索（スマホ対応） |
| テキスト＋画像 | 両方を組み合わせてマルチモーダル検索                   |

検索結果は画像／テキストでフィルタリング可能。

<!-- SCREENSHOT: 画像モードで検索したときの結果グリッドのスクリーンショット -->

### フロントエンドのローカル確認

```bash
cd frontend
npm install
npm run dev        # Tailwind ウォッチビルド
# → index.html をブラウザで直接開く
```

---

## API エンドポイント

ベース URL: `https://vector-search.riri-inferno.com`  
認証: すべてのリクエストに `X-API-Key` ヘッダが必要。

| メソッド | パス                       | 概要                                                              |
| -------- | -------------------------- | ----------------------------------------------------------------- |
| `GET`    | `/health`                  | 死活監視                                                          |
| `POST`   | `/v1/documents`            | テキスト or GCS URI を埋め込みベクトル化して保存                  |
| `POST`   | `/v1/documents/upload-url` | メディアアップロード用 Signed URL を発行（5分間有効）             |
| `POST`   | `/v1/search`               | テキスト / メディアクエリで近傍ベクトル検索（クロスモーダル対応） |
| `POST`   | `/v1/media/download-url`   | GCS メディアファイルのダウンロード用 Signed URL を発行            |

詳細なリクエスト/レスポンス仕様は [`api/openapi.yaml`](api/openapi.yaml) を参照。

### クイック動作確認

```bash
# ヘルスチェック
curl https://vector-search.riri-inferno.com/health \
  -H "X-API-Key: <your-key>"

# テキスト登録
curl -X POST https://vector-search.riri-inferno.com/v1/documents \
  -H "X-API-Key: <your-key>" \
  -H "Content-Type: application/json" \
  -d '{"text": "夕日の海岸"}'

# テキスト検索
curl -X POST https://vector-search.riri-inferno.com/v1/search \
  -H "X-API-Key: <your-key>" \
  -H "Content-Type: application/json" \
  -d '{"query": "海の夕暮れ", "top_k": 5}'
```

---

## システムアーキテクチャ

![System Architecture](docs/images/architecture.png)

詳細なシーケンス図・コンポーネント一覧は [`docs/architecture.md`](docs/architecture.md) を参照。

### 処理フロー概要

```
Browser / CLI
  └─ HTTPS + X-API-Key
      └─ Cloudflare Worker (Host ヘッダ書き換え)
          └─ GCP API Gateway (X-API-Key 認証)
              ├─ GET  /health       → healthz (Cloud Functions)
              └─ POST /v1/*         → vector-api (Cloud Functions)
                  ├─ Firestore          (ベクトル保存 / 検索)
                  ├─ GCS media-inputs   (メディアバイナリ)
                  ├─ Secret Manager     (Gemini API Key)
                  └─ Gemini Embedding API (2048-dim ベクトル生成)
```

メディアアップロードはクライアントが GCS へ直接 PUT する（API Gateway を経由しない）。詳細は [ADR-0017](docs/adr/0017-multimodal-media-upload-pattern.md)。

---

## 技術スタック

| レイヤー           | 採用                                   | 選定理由                                                        |
| ------------------ | -------------------------------------- | --------------------------------------------------------------- |
| インフラ管理       | Terraform                              | 構成のコード化。`tfstate` は GCS にロック付きで保存             |
| フロントエンド     | **Cloudflare Pages**                   | 静的配信。`wrangler` でデプロイ。ビルドは Tailwind CSS のみ     |
| DNS / TLS / Proxy  | Cloudflare                             | `riri-inferno.com` 配下のサブドメイン管理、エッジで TLS 終端    |
| API 入口           | **GCP API Gateway**                    | OpenAPI 仕様で X-API-Key 認証・レート制限を肩代わり             |
| 実行ランタイム     | **Cloud Functions Gen2 (Python 3.13)** | ゼロスケール。リクエストがない時間は完全に課金されない          |
| 埋め込みモデル     | **`gemini-embedding-2`** (2048 次元)   | テキスト・画像・動画・音声・PDF を同一ベクトル空間に射影        |
| ベクトル DB        | **Firestore** (`find_nearest`)         | ネイティブにベクトル検索対応。起動固定費なし                    |
| メディアストレージ | Cloud Storage                          | 画像バイナリ等の保存。Firestore には GCS URI とベクトルのみ格納 |
| シークレット管理   | Secret Manager + SOPS + KMS            | Gemini API Key を Cloud Functions に安全にマウント              |

---

## セキュリティ & コスト保護

DDoS・課金暴騰に対する多層防御方針は [`docs/security.md`](docs/security.md) を参照。

主要ポイント:

- **認証**: API Gateway 段で X-API-Key 検証（[ADR-0003](docs/adr/0003-authentication.md)）。Cloud Functions は IAM で API GW からのみ受け付ける
- **最小権限**: 関数ごとに専用 Service Account。`healthz` は Firestore/Storage へのアクセス権なし
- **メディアバケット**: Public access prevention enforced / Uniform bucket-level access
- **Signed URL**: アップロード用は 5 分間、ダウンロード用は短期 TTL のみ有効
- **スケール上限**: Cloud Functions `max_instance_count = 3`（[ADR-0005](docs/adr/0005-cloud-functions-runtime-stack.md)）
- Cloudflare 側の対策（WAF / Rate Limiting）は [home-raspi-iac](https://github.com/Riri-Inferno/home-raspi-iac) で管理

---

## リポジトリ構成

```
.
├── api/                  # OpenAPI 仕様 (openapi.yaml)
├── docs/
│   ├── adr/              # Architecture Decision Records
│   ├── architecture.md   # 詳細アーキテクチャ・シーケンス図
│   ├── security.md       # セキュリティ設計
│   └── images/           # 構成図 PNG / drawio
├── frontend/             # デモ UI (HTML + Tailwind CSS)
│   ├── index.html
│   ├── src/input.css
│   ├── tailwind.config.js
│   └── wrangler.toml     # Cloudflare Pages デプロイ設定
├── functions/
│   ├── healthz/          # GET /health (Python)
│   └── vector-api/       # POST /v1/* (Python)
├── terraform/
│   ├── bootstrap/        # GCS バックエンド・WIF・CI SA
│   └── gcp/              # GCP リソース全体
├── secrets/              # SOPS 暗号化済みシークレット
└── DESIGN.md             # AI エージェント向けデザインシステム定義
```

---

## ADR 索引

| ADR                                                               | 内容                                                            |
| ----------------------------------------------------------------- | --------------------------------------------------------------- |
| [0001](docs/adr/0001-api-design-mvp.md)                           | API MVP 設計（エンドポイント・ID・スコア・エラー形式）          |
| [0003](docs/adr/0003-authentication.md)                           | X-API-Key ヘッダ認証                                            |
| [0005](docs/adr/0005-cloud-functions-runtime-stack.md)            | Cloud Functions Gen2 / Python / 関数分割粒度                    |
| [0006](docs/adr/0006-secret-management-sops-kms.md)               | SOPS + KMS による Secret 管理                                   |
| [0014](docs/adr/0014-cloudflare-worker-host-rewrite.md)           | Cloudflare Worker で Host ヘッダを書き換えて API Gateway へ接続 |
| [0016](docs/adr/0016-embedding-dimension-2048-firestore-limit.md) | 埋め込み次元を 2048 に確定（Firestore 上限）                    |
| [0017](docs/adr/0017-multimodal-media-upload-pattern.md)          | GCS Signed URL 直アップロード & Part.from_bytes                 |
