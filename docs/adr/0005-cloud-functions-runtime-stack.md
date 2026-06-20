# ADR 0005: Cloud Functions 実装スタック（言語・ランタイム・FW・SDK）

- **Date**: 2026-06-21
- **Status**: Accepted

## Context

[ADR 0001](0001-api-design-mvp.md) で API 仕様、[ADR 0004](0004-firestore-embedding-model-field.md) で Firestore スキーマが確定したので、Cloud Functions (2nd gen) の実装スタックを確定する必要がある。

ここで決めた選定は `functions/` のディレクトリ構成、`requirements.txt`、ローカル開発手順、Terraform 側の `runtime` 文字列などすべてに反映される。後から大きく変えると出戻りが大きいので最初に明示する。

## Decision

### 言語: **Python**

選定理由:
- Google AI Studio の公式 SDK (`google-genai`) が Python を起点に整備されている
- マルチモーダル系（画像・音声処理）のエコシステムが他言語より充実
- 個人ラボのインタプリタ言語が増えると認知負荷が高まる中、Python は本人が日常的に扱う言語

「AI 推論自体のレイテンシが支配的なので、言語のホットパス性能差は問題にならない」点が決定打。

### ランタイム: **`python313`** (Python 3.13、google-22 デフォルト)

Cloud Functions Gen2 の GA 済みランタイムから最新を採用:
- `runtime = "python313"`
- ベースイメージは google-22 デフォルト（`-full` 系は不要、必要になれば後から変更）

理由: 新しい Python ほど標準ライブラリ・パフォーマンスが向上している。最新を選んで困ることは個人ラボ規模ではほぼ無い。

### Web フレームワーク: **`functions-framework` + Flask**

- Cloud Functions Gen2 公式の Python ランタイムは内部的に functions-framework を使う
- `functions-framework` の `--target` で指定する HTTP ハンドラを Flask の WSGI app (`Flask(__name__)`) で構築する
- Flask 内でルートを分岐する

FastAPI を採用しない理由:
- async/await の旨味を活かすには ASGI server が必要で、Cloud Functions Gen2 上で動かすには追加の adapter が要る
- 後述の通り MVP は sync で問題ない見込み
- 必要になったタイミングで Flask → FastAPI 移行は局所的に可能（routing 層の置換だけ）

### Cloud Function の分割粒度: **`/healthz` のみ別関数、`/v1/*` は同居**

| Cloud Function | 担当ルート | 依存ライブラリ | メモリ目安 |
|---|---|---|---|
| `healthz` | `GET /healthz` のみ | `functions-framework` + `flask` のみ | 最小 (128 MB) |
| `vector-api` | `POST /v1/documents` / `POST /v1/search` | 上記 + `pydantic` + `google-genai` + `google-cloud-firestore` | 中 (256-512 MB、要計測) |

「FaaS は 1 関数 1 役割」という単一責任原則と、「依存と初期化コストを共有したい」という現実のバランスを取る形。

**なぜ healthz だけ分離するか**:
- `/healthz` はヘルスチェッカ（外形監視・Cloudflare の Cache rule 越し等）から頻繁に叩かれ、コールドスタートが起きると **偽の不健全 alert を生む**
- `/healthz` は genai SDK や Firestore client の初期化が**全く不要** — 重いライブラリを抱えると意味のないコールドスタート時間を払うことになる
- Cloud Functions Gen2 は **per-function に min_instances を設定** できるため、healthz だけ常時 1 インスタンス warm にする運用も低コストで可能

**なぜ `/v1/documents` と `/v1/search` は同居するか**:
- 両方とも genai (embedding) と Firestore を必ず使う → 初期化コードと SDK client を共有できる
- 初回コールドスタート時の SDK 初期化（数百 ms）が 2 関数分節約できる
- API Gateway 段で認証が済んでいるため、認証スコープの違いを理由にした分離は不要 (ADR 0003 参照)

### 関数分離の判断基準（今後の指針）

将来「この機能を別関数に分けるべきか」を判断するためのチェックリスト。**2 個以上 YES なら分離を検討、3 個以上 YES なら分離を強く推奨**。

| # | 判断項目 | YES の例 |
|---|---|---|
| 1 | **依存ライブラリ集合が大きく異なるか** | 既存関数では不要だった ML フレームワーク等を新ルートだけが必要とする |
| 2 | **コールドスタートの許容度が異なるか** | 監視系・外形 ping のように低レイテンシが必須 vs バッチ的な処理 |
| 3 | **メモリ/CPU 要件が大きく異なるか** | 既存は 256MB で動くが新ルートは画像処理で 2GB 欲しい |
| 4 | **scale 特性が異なるか** | 既存は秒間数 req、新ルートはバースト 100 req などスケール想定が桁違い |
| 5 | **デプロイサイクルが異なるか** | 既存は安定運用、新ルートは頻繁に実験的更新が入る |
| 6 | **障害ドメインを分けたいか** | 新ルートが落ちても既存ルートを生かしたい（クリティカリティが違う） |
| 7 | **認証/認可ポリシーが大きく異なるか** | API Gateway で吸収できない範囲のスコープ差分（直接 IAM 認証が必要等） |
| 8 | **観測性を独立させたいか** | メトリクス・ログ・SLO を個別に追いたい強い動機がある |

**逆に分離しない方向の重み**:
- 同じ SDK client を毎リクエスト初期化することの非効率
- Terraform リソース・デプロイパイプライン・ローカル開発手順の重複
- 認知負荷（個人ラボでは特に重要）

判断に迷ったら **「同居で始めて、必要になったら分割」を default** とする。FaaS の理想に寄せるのではなく、運用観測に基づいて分割していく。

### バリデーション: **Pydantic v2**

- OpenAPI 3.0.4 のスキーマと自然に整合する（フィールド型、required、enum 等）
- Cloud Functions の HTTP ハンドラに入る前段で request body を Pydantic モデルにパースし、不正なら 400 + `application/problem+json` を返す
- レスポンスも Pydantic モデル → `model_dump_json()` で直接シリアライズ

### Google AI Studio SDK: **`google-genai`**（公式・新世代）

旧 `google-generativeai` ではなく新 `google-genai` を採用する。前者は deprecated 扱い、後者が Google AI Studio / Vertex AI 双方を統一インターフェースで扱える新公式 SDK。

呼び出し例（参考）:

```python
from google import genai
client = genai.Client(api_key=os.environ["GEMINI_API_KEY"])
result = client.models.embed_content(
    model="gemini-embedding-2",
    contents=text,
    config={"output_dimensionality": 1536},
)
embedding = result.embeddings[0].values  # list[float] of length 1536
```

### Firestore SDK: **`google-cloud-firestore`** (sync client)

vector search (`find_nearest`) がサポートされたバージョン以降を使う。非同期版 (`firestore.AsyncClient`) は採用しない（理由は次項）。

### 同期/非同期: **sync 採用 (MVP)**

理由:
- Cloud Functions Gen2 の Python ランタイムは関数あたり 1 リクエストを sync 処理する想定が標準
- 個人ラボ規模では concurrent request 数が極めて少ない（1-2 同時程度）
- AI 推論のレイテンシは「ネットワーク往復＋モデル推論」が支配的で、ハンドラ内で async にしても全体応答時間はほぼ変わらない

**async 検討トリガ**: 以下のいずれかが起きたら async/await + FastAPI に切り替えを再検討する。
- 1 リクエスト内で複数の外部呼び出しを並列実行したくなった（embedding API + 別 API、複数ベクトル並列検索 等）
- 同時リクエスト数が増えてコンテナあたりの throughput が問題になった
- レスポンスストリーミング（SSE）が必要になった

### 埋め込みモデル: **`gemini-embedding-2`** (確定済み)

- モデルコード: `gemini-embedding-2`
- 入力: テキスト / 画像 / 動画 / 音声 / PDF（マルチモーダル対応済み）
- 入力トークン上限: 8,192
- 出力次元: 柔軟（128〜3072）。本プロジェクトは **1536** を採用（[ADR 0001](0001-api-design-mvp.md), [ADR 0004](0004-firestore-embedding-model-field.md)）

公式ドキュメント: <https://ai.google.dev/gemini-api/docs/models/gemini-embedding-2>

### ローカル開発: 最小限

- `functions-framework --target=app --port=8080` で Flask app をローカル起動
- Firestore は本番プロジェクト直接接続（Emulator はベクトル検索の対応状況が不確実なため避ける）
- Google AI Studio API も本番直接（埋め込み単発呼び出しの課金は微少）
- Docker / Compose 化はしない

## Consequences

- `functions/` 配下に 2 つのサブディレクトリ（`vector-api/` と `healthz/`）を持つ構成にする。それぞれ独立した `main.py` と `requirements.txt` を持つ
  - `functions/vector-api/requirements.txt`: `functions-framework`, `flask`, `pydantic>=2`, `google-genai`, `google-cloud-firestore`
  - `functions/healthz/requirements.txt`: `functions-framework`, `flask` のみ
- Terraform の Cloud Function 定義は 2 リソース。`runtime = "python313"` を共通固定。memory / min_instances を関数ごとに個別設定
- async 化は localized なリファクタで対応可能（ハンドラ層を FastAPI に置換、Firestore/AI SDK を AsyncClient に置換）。再エンベディングは不要なので影響範囲が限定的
- 「なぜ Flask？」「なぜ sync？」「なぜ 3.13？」「なぜ healthz だけ分離？」「分離の判断基準は？」の議論はこの ADR で完結。再度持ち上がったら本 ADR を Superseded する形で更新する
