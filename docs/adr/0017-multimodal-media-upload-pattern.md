# ADR 0017: マルチモーダル対応 — GCS Signed URL 直アップロード & Part.from_bytes

- **Date**: 2026-06-23
- **Status**: Accepted
- **Supersedes**: なし

## Context

マルチモーダル対応（画像・PDF・動画・音声の埋め込み登録）を実装するにあたり、2 つの実装方針を決定する必要があった。

**課題 A — クライアントからバイナリをどう届けるか**

- GCP API Gateway はリクエストボディの上限が 32MB
- 動画ファイルは 80 秒で数百 MB になりうる
- Cloud Functions にバイナリを通すと関数の実行時間・メモリ・転送コストが倍増する

**課題 B — Cloud Functions が Gemini にメディアを渡す方法**

- `google-genai` SDK は `Part.from_uri("gs://...")` をサポートするが、  
  これは Vertex AI (サービスアカウント認証) 専用の機能
- 本プロジェクトは Google AI Studio の API Key 認証を使用（ADR 0006）  
  → `Part.from_uri("gs://...")` は認証エラーになる

## Decision

**A: GCS V4 Signed URL 経由でクライアントが GCS へ直接 PUT する**

1. クライアントが `POST /v1/documents/upload-url` でファイル名と MIME タイプを申告
2. vector-api が 5 分間有効な V4 Signed URL を発行して返す
3. クライアントはその URL に対して直接 `PUT` でバイナリをアップロード
4. アップロード完了後、クライアントは `gcs_uri` を添えて `POST /v1/documents` を呼ぶ

**B: GCS からバイナリをダウンロードして `Part.from_bytes(data, mime_type)` でインライン渡しする**

- vector-api が `google-cloud-storage` SDK でバイナリを取得し、Gemini にインラインデータとして渡す
- `Part.from_uri("gs://...")` は使わない

## Rationale

| 観点        | 採用案                                                   | 却下案                                                     |
| ----------- | -------------------------------------------------------- | ---------------------------------------------------------- |
| API GW 上限 | GCS 直 PUT は API GW を通さない                          | multipart/form-data で API GW 経由 → 32MB 上限に引っかかる |
| コスト      | 大容量バイナリが GCP 内部で GCS→関数→GCS と 2 往復しない | 関数経由受け取り → GCS 保存 → GCS 再取得で転送コスト 3×    |
| Gemini 認証 | `Part.from_bytes()` は API Key 認証と互換                | `Part.from_uri("gs://")` は Vertex AI (SA 認証) 専用       |

## Consequences

- Signed URL の有効期限は 5 分。期限切れ後の PUT は GCS が 403 を返す（バックエンドは検知しない）
- Content-Type が署名時と異なる場合も GCS が 403 を返す
- `roles/iam.serviceAccountTokenCreator` の自己バインドが必要（`media_bucket.tf` 追加済み）
- メディアバイナリを Cloud Functions のメモリに展開するため、`available_memory = "1Gi"` が前提
