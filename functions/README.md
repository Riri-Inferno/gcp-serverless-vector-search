# Cloud Functions (Python)

[ADR 0005](../docs/adr/0005-cloud-functions-runtime-stack.md) の決定に沿った Python 実装。

## 構成

| ディレクトリ | 担当ルート | 依存ライブラリ | 用途 |
|--------------|------------|----------------|------|
| `healthz/`    | `GET /health`                               | functions-framework / flask                              | ヘルスチェック (低レイテンシ / 重い SDK 不要) |
| `vector-api/` | `POST /v1/documents` / `POST /v1/search`    | + pydantic / google-genai / google-cloud-firestore        | 埋め込み生成と Firestore ベクトル検索        |

API 仕様は [`api/openapi.yaml`](../api/openapi.yaml) を契約とする。

## ローカル実行

各関数は `functions-framework` 単体で WSGI app として動く。

```bash
cd functions/vector-api    # or functions/healthz
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
export GEMINI_API_KEY=...   # vector-api のみ必要
export GOOGLE_CLOUD_PROJECT=riri-vector-lab-2026
functions-framework --target=main --port=8080
```

別ターミナルから:

```bash
curl http://localhost:8080/health
curl -X POST http://localhost:8080/v1/documents \
  -H 'Content-Type: application/json' \
  -d '{"text": "Pythonの非同期処理について", "metadata": {"category": "tech"}}'
curl -X POST http://localhost:8080/v1/search \
  -H 'Content-Type: application/json' \
  -d '{"query": "Python async", "top_k": 5}'
```

> Note: ローカル開発時も **本番 Firestore に接続** する設計 (Emulator は vector search の対応状況が不確実なため避ける、ADR 0005 参照)。本番データが混ざるのを避けたい場合は、別途 dev コレクションプレフィックスを切るなどの工夫が必要。

## 環境変数

| 変数 | 必須 | 用途 | デフォルト |
|------|------|------|----------|
| `GEMINI_API_KEY`         | ✓ (vector-api) | Google AI Studio API キー        | (なし) |
| `GOOGLE_CLOUD_PROJECT`   | ✓ (vector-api) | Firestore client がプロジェクト解決に使用 | Cloud Functions 環境では自動セット |
| `LOG_LEVEL`              |                | Python logging のレベル          | `INFO` |

## デプロイ

このディレクトリの内容は次の PR (PR-β) で Terraform から Cloud Functions Gen2 にデプロイする。本 PR ではコードのみで、デプロイ経路はまだ無い。
