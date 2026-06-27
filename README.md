<a id="readme-top"></a>

<!-- PROJECT SHIELDS -->

[![Stars][stars-shield]][stars-url]
[![Issues][issues-shield]][issues-url]
[![License][license-shield]][license-url]
[![Python][python-shield]][python-url]
[![Terraform][terraform-shield]][terraform-url]

<!-- PROJECT LOGO -->
<br />
<div align="center">

<!-- PLACEHOLDER: ロゴ画像を用意したら下記を差し替えてください -->
<!-- <a href="https://github.com/Riri-Inferno/gcp-serverless-vector-search">
  <img src="docs/images/logo.png" alt="Logo" width="80" height="80">
</a> -->

<h3 align="center">GCP Serverless Vector Search</h3>

<p align="center">
  テキスト・画像・手書きで横断検索できる、GCP サーバーレス構成のマルチモーダルベクトル検索システム
  <br />
  <a href="docs/architecture.md"><strong>アーキテクチャを読む »</strong></a>
  <br />
  <br />
  <a href="https://vector-search-demo.riri-inferno.com/">デモを見る</a>
  &middot;
  <a href="https://github.com/Riri-Inferno/gcp-serverless-vector-search/issues/new?labels=bug">バグを報告</a>
  &middot;
  <a href="https://github.com/Riri-Inferno/gcp-serverless-vector-search/issues/new?labels=enhancement">機能リクエスト</a>
</p>
</div>

---

<!-- TABLE OF CONTENTS -->
<details>
  <summary>目次</summary>
  <ol>
    <li><a href="#about-the-project">このプロジェクトについて</a></li>
    <li><a href="#built-with">技術スタック</a></li>
    <li>
      <a href="#getting-started">はじめかた</a>
      <ul>
        <li><a href="#demo-ui">デモ UI を使う</a></li>
        <li><a href="#api">API を直接叩く</a></li>
        <li><a href="#local-dev">ローカル開発</a></li>
      </ul>
    </li>
    <li><a href="#usage">使いかた</a></li>
    <li><a href="#api-reference">API リファレンス</a></li>
    <li><a href="#architecture">アーキテクチャ</a></li>
    <li><a href="#roadmap">ロードマップ</a></li>
    <li><a href="#license">ライセンス</a></li>
    <li><a href="#contact">コンタクト</a></li>
    <li><a href="#acknowledgments">謝辞</a></li>
  </ol>
</details>

---

## About The Project

<!-- PLACEHOLDER: デモ UI 全体のスクリーンショット（検索結果が表示されている状態）を撮影し、
     docs/images/screenshot-demo.png として保存した上で下記のコメントを外してください -->
<!-- [![Demo Screenshot][product-screenshot]](https://vector-search-demo.riri-inferno.com/) -->

テキスト・画像・手書きキャンバス・クリップボード貼り付けを入力として、2048 次元のベクトル空間で横断検索できるサーバーレスシステムです。

**できること:**

- テキストで画像を検索（クロスモーダル）
- 画像で似た画像を検索
- 手書きキャンバスで画像を検索
- クリップボードに貼り付けた画像で即検索（Ctrl+V）
- 検索結果を画像 / テキストでフィルタリング
- ドキュメントの登録・削除（GCS メディアファイルも連動削除）

Gemini Embedding API（`gemini-embedding-2`）でテキスト・画像・動画・音声・PDF を同一ベクトル空間に射影し、Firestore のネイティブベクトル検索（`find_nearest`）で近傍探索します。

<p align="right">(<a href="#readme-top">back to top</a>)</p>

---

## Built With

[![GCP Cloud Functions][cloudfunctions-shield]][cloudfunctions-url]
[![Firestore][firestore-shield]][firestore-url]
[![GCS][gcs-shield]][gcs-url]
[![API Gateway][apigw-shield]][apigw-url]
[![Gemini][gemini-shield]][gemini-url]
[![Cloudflare][cloudflare-shield]][cloudflare-url]
[![Terraform][terraform-shield]][terraform-url]
[![Python][python-shield]][python-url]
[![Tailwind CSS][tailwind-shield]][tailwind-url]

<p align="right">(<a href="#readme-top">back to top</a>)</p>

---

## Getting Started

### Demo UI

ブラウザだけで試せます。インストール不要。

1. **<https://vector-search-demo.riri-inferno.com/>** を開く
2. 画面上部の API Key 欄に発行済みの `X-API-Key` を入力
3. テキスト / 画像 / 手書き いずれかで検索

<!-- PLACEHOLDER: 手書きキャンバスのスクリーンショットを
     docs/images/screenshot-canvas.png として保存した上で下記のコメントを外してください -->
<!-- ![Canvas Search][canvas-screenshot] -->

### API

ベース URL: `https://vector-search.riri-inferno.com`  
すべてのリクエストに `X-API-Key` ヘッダが必要です。

```bash
# ヘルスチェック
curl https://vector-search.riri-inferno.com/health \
  -H "X-API-Key: YOUR_KEY"

# テキスト登録
curl -X POST https://vector-search.riri-inferno.com/v1/documents \
  -H "X-API-Key: YOUR_KEY" \
  -H "Content-Type: application/json" \
  -d '{"text": "夕日の海岸線"}'

# テキストで検索
curl -X POST https://vector-search.riri-inferno.com/v1/search \
  -H "X-API-Key: YOUR_KEY" \
  -H "Content-Type: application/json" \
  -d '{"query": "海の夕暮れ", "top_k": 5}'
```

### Local Dev

```bash
# Tailwind ウォッチビルド
cd frontend
npm install
npm run dev

# index.html をブラウザで直接開く（API Key が必要）
```

<p align="right">(<a href="#readme-top">back to top</a>)</p>

---

## Usage

### 検索モード

| モード         | 操作                                 | 補足                               |
| -------------- | ------------------------------------ | ---------------------------------- |
| テキスト       | キーワードを入力して検索             | 日本語・英語対応                   |
| 画像           | ファイルを選択 / ドロップ            | スマホのカメラロールからも選択可   |
| 手書き         | 鉛筆ボタン → キャンバスに描画 → 確定 | Ctrl+Z / Ctrl+Y でアンドゥ・リドゥ |
| クリップボード | 画像をコピー後、検索エリアで Ctrl+V  | デスクトップ限定                   |

検索結果は **すべて / 画像 / テキスト** でフィルタリングできます。

<!-- PLACEHOLDER: 画像モードの検索結果グリッドのスクリーンショットを
     docs/images/screenshot-results.png として保存した上で下記のコメントを外してください -->
<!-- ![Results Grid][results-screenshot] -->

### ドキュメント登録

デモ UI の「登録」タブから画像・テキストを登録できます。画像は GCS に直接アップロード（API Gateway を経由しない）され、Gemini でベクトル化して Firestore に保存されます。

### ドキュメント削除

検索結果カードの × ボタンから削除できます。Firestore のドキュメントと GCS のメディアファイルが同時に削除されます。

### マルチモーダル検索の挙動について

本システムは Gemini Embedding API の joint embedding space を利用しており、テキスト / 画像 / 音声 / 動画 / PDF を **同一の 2048 次元ベクトル空間** に射影します。同モダリティでの検索（テキスト → テキスト、画像 → 画像）は良好に機能します。

ただし実運用では **modality gap**（異モダリティ間の cosine 類似度が同モダリティ内ペアより著しく低くなる傾向）が大きく、テキストクエリで画像が、画像クエリでテキストが top_k 上位にヒットすることはほとんどありません。`top_k=50` まで広げても同様の傾向が見られます。これは joint embedding を採用したマルチモーダルシステムに広く知られている特性です。

そのため本システムは現時点では「**複数モダリティを同一ベクトル空間で保持し、モダリティ別に高精度な近傍検索ができる基盤**」として完成しており、強力なクロスモーダル検索（テキスト ↔ 画像の双方向検索）は将来課題としています。検索 UI のフィルタ機能（すべて / 画像 / テキスト）で結果を明示的に絞り込めます。

将来的には、より強いクロスモーダル能力を持つモデル（例: Vertex AI `multimodalembedding`）への切替を視野に入れています。

<p align="right">(<a href="#readme-top">back to top</a>)</p>

---

## API Reference

エンドポイント一覧:

| メソッド | パス                       | 概要                                                  |
| -------- | -------------------------- | ----------------------------------------------------- |
| `GET`    | `/health`                  | 死活監視                                              |
| `POST`   | `/v1/documents`            | コンテンツを埋め込みベクトル化して保存                |
| `POST`   | `/v1/documents/upload-url` | メディアアップロード用 Signed URL 発行（5分）         |
| `DELETE` | `/v1/documents/{id}`       | ドキュメント削除（GCS も連動）                        |
| `POST`   | `/v1/search`               | テキスト / 画像クエリで近傍ベクトル検索               |
| `POST`   | `/v1/media/download-url`   | GCS メディアのダウンロード用 Signed URL 発行（1時間） |

リクエスト / レスポンスの詳細スキーマは [`api/openapi.yaml`](api/openapi.yaml) を参照してください。

<p align="right">(<a href="#readme-top">back to top</a>)</p>

---

## Architecture

```
Browser
  └─ HTTPS + X-API-Key
      └─ Cloudflare Worker（Host ヘッダ書き換え / ADR-0014）
          └─ GCP API Gateway（X-API-Key 認証 / ADR-0003）
              ├─ GET  /health        → healthz（Cloud Functions）
              └─ *    /v1/*          → vector-api（Cloud Functions）
                  ├─ Firestore           ベクトル保存・検索
                  ├─ GCS inputs/         登録メディア（30日 TTL）
                  ├─ GCS queries/        検索クエリ画像（翌日 TTL / ADR-0018）
                  ├─ Secret Manager      Gemini API Key
                  └─ Gemini Embedding    2048 次元ベクトル生成
```

詳細なシーケンス図・コンポーネント一覧は [`docs/architecture.md`](docs/architecture.md) を参照してください。  
設計判断の経緯は [`docs/adr/`](docs/adr/) にまとめています。  
セキュリティ設計は [`docs/security.md`](docs/security.md) を参照してください。

<p align="right">(<a href="#readme-top">back to top</a>)</p>

---

## Roadmap

- [x] テキスト / 画像 クロスモーダル検索
- [x] GCS Signed URL 直アップロード（API Gateway バイパス）
- [x] ドキュメント削除（Firestore + GCS 連動）
- [x] 手書きキャンバス検索（Signature Pad）
- [x] クリップボード貼り付け検索（Ctrl+V）
- [x] 検索結果フィルタ（すべて / 画像 / テキスト）
- [x] GCS プレフィックス分離 + 検索クエリ画像の自動削除（ADR-0018）
- [ ] デモデータ整備（動物画像 + テキスト）
- [ ] metadata を活用した自動タグ付け（OCR / Gemini）

<p align="right">(<a href="#readme-top">back to top</a>)</p>

---

## License

[Creative Commons Attribution-NonCommercial 4.0 International](LICENSE) の下で配布しています。

<p align="right">(<a href="#readme-top">back to top</a>)</p>

---

## Contact

<!-- PLACEHOLDER: 下記をご自身の情報に差し替えてください -->

<!-- 後でエージェントリファラ側宛にお願いしますって書く。ここにメアド載せたくないかも -->

Riri-Inferno - [@your_twitter](https://twitter.com/your_username)

Project Link: [https://github.com/Riri-Inferno/gcp-serverless-vector-search](https://github.com/Riri-Inferno/gcp-serverless-vector-search)

<p align="right">(<a href="#readme-top">back to top</a>)</p>

---

## Acknowledgments

- [Gemini Embedding API](https://ai.google.dev/gemini-api/docs/embeddings)
- [Firestore Vector Search](https://firebase.google.com/docs/firestore/vector-search)
- [Signature Pad](https://github.com/szimek/signature_pad) — MIT License
- [Tailwind CSS](https://tailwindcss.com/)
- [Best-README-Template](https://github.com/othneildrew/Best-README-Template)
- [Img Shields](https://shields.io)

<p align="right">(<a href="#readme-top">back to top</a>)</p>

---

<!-- SHIELDS REFERENCE LINKS -->

[stars-shield]: https://img.shields.io/github/stars/Riri-Inferno/gcp-serverless-vector-search.svg?style=for-the-badge
[stars-url]: https://github.com/Riri-Inferno/gcp-serverless-vector-search/stargazers
[issues-shield]: https://img.shields.io/github/issues/Riri-Inferno/gcp-serverless-vector-search.svg?style=for-the-badge
[issues-url]: https://github.com/Riri-Inferno/gcp-serverless-vector-search/issues
[license-shield]: https://img.shields.io/badge/License-CC%20BY--NC%204.0-lightgrey.svg?style=for-the-badge
[license-url]: LICENSE
[python-shield]: https://img.shields.io/badge/Python-3.13-3776AB?style=for-the-badge&logo=python&logoColor=white
[python-url]: https://www.python.org/
[terraform-shield]: https://img.shields.io/badge/Terraform-IaC-7B42BC?style=for-the-badge&logo=terraform&logoColor=white
[terraform-url]: https://www.terraform.io/
[cloudfunctions-shield]: https://img.shields.io/badge/Cloud%20Functions-Gen2-4285F4?style=for-the-badge&logo=googlecloud&logoColor=white
[cloudfunctions-url]: https://cloud.google.com/functions
[firestore-shield]: https://img.shields.io/badge/Firestore-Vector%20Search-FF6F00?style=for-the-badge&logo=firebase&logoColor=white
[firestore-url]: https://firebase.google.com/docs/firestore/vector-search
[gcs-shield]: https://img.shields.io/badge/Cloud%20Storage-GCS-4285F4?style=for-the-badge&logo=googlecloud&logoColor=white
[gcs-url]: https://cloud.google.com/storage
[apigw-shield]: https://img.shields.io/badge/API%20Gateway-OpenAPI-34A853?style=for-the-badge&logo=googlecloud&logoColor=white
[apigw-url]: https://cloud.google.com/api-gateway
[gemini-shield]: https://img.shields.io/badge/Gemini-Embedding%202-8E75B2?style=for-the-badge&logo=google&logoColor=white
[gemini-url]: https://ai.google.dev/gemini-api/docs/embeddings
[cloudflare-shield]: https://img.shields.io/badge/Cloudflare-Pages%20%2B%20Workers-F38020?style=for-the-badge&logo=cloudflare&logoColor=white
[cloudflare-url]: https://pages.cloudflare.com/
[tailwind-shield]: https://img.shields.io/badge/Tailwind%20CSS-3.x-06B6D4?style=for-the-badge&logo=tailwindcss&logoColor=white
[tailwind-url]: https://tailwindcss.com/

<!-- SCREENSHOT REFERENCE LINKS (コメントを外したら一緒に有効化してください) -->
<!-- [product-screenshot]: docs/images/screenshot-demo.png -->
<!-- [canvas-screenshot]: docs/images/screenshot-canvas.png -->
<!-- [results-screenshot]: docs/images/screenshot-results.png -->
