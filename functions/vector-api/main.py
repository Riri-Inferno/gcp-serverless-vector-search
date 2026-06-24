"""Vector API Cloud Function.

ADR 0005 の判断に従い、/v1/documents と /v1/search を同一関数に同居させる
(両方 genai SDK + Firestore client を共有するため)。

リクエスト経路 (本番): Cloudflare → API Gateway → 本関数。
API Gateway 段で API Key 認証が済んでいる前提なので、本関数では認証を行わない
(ADR 0003 / docs/security.md D2-D3 参照)。
"""

from __future__ import annotations

import datetime
import logging
import os
import pathlib
import uuid

import functions_framework
import google.auth
import google.auth.transport.requests
import json
from flask import Response
from google import genai
from google.cloud import firestore, storage
from google.cloud.firestore_v1.base_vector_query import DistanceMeasure
from google.cloud.firestore_v1.vector import Vector
from google.genai import types
from pydantic import ValidationError

from models import (
    Document,
    DocumentCreateRequest,
    Problem,
    SearchRequest,
    SearchResponse,
    SearchResult,
    UploadUrlRequest,
    UploadUrlResponse,
)

# ---------------------------------------------------------------------------
# 設定 (ADR 0001 / 0004 / 0005 / 0015 / 0016 で確定済みの値を hardcode)
# ---------------------------------------------------------------------------
EMBEDDING_MODEL = "gemini-embedding-2"
EMBEDDING_DIMENSION = 2048
COLLECTION = "documents"
EMBEDDING_FIELD = "embedding"
DISTANCE_RESULT_FIELD = "vector_distance"
MEDIA_BUCKET = os.environ["MEDIA_BUCKET"]

ALLOWED_CONTENT_TYPES = {
    # 画像（最大6枚 / リクエスト）
    "image/jpeg", "image/png", "image/webp", "image/bmp",
    "image/heic", "image/heif", "image/avif",
    # PDF（最大1ファイル・最大6ページ）
    "application/pdf",
    # 動画（最大1本 / 音声付き80秒・無音120秒）
    "video/mp4", "video/mpeg",
    # 音声（最大1ファイル・最大180秒）
    "audio/mp3", "audio/wav",
}

# ---------------------------------------------------------------------------
# Clients (warm 状態でリクエスト間に共有される module-level singleton)
# ---------------------------------------------------------------------------
logging.basicConfig(level=os.environ.get("LOG_LEVEL", "INFO"))
logger = logging.getLogger(__name__)

_genai_client: genai.Client | None = None
_firestore_client: firestore.Client | None = None
_storage_client: storage.Client | None = None


def get_genai_client() -> genai.Client:
    global _genai_client
    if _genai_client is None:
        api_key = os.environ["GEMINI_API_KEY"]
        _genai_client = genai.Client(api_key=api_key)
    return _genai_client


def get_firestore_client() -> firestore.Client:
    global _firestore_client
    if _firestore_client is None:
        _firestore_client = firestore.Client()
    return _firestore_client


def get_storage_client() -> storage.Client:
    global _storage_client
    if _storage_client is None:
        _storage_client = storage.Client()
    return _storage_client


# ---------------------------------------------------------------------------
# Response helpers
# ---------------------------------------------------------------------------
def _json(data: dict, status: int = 200, content_type: str = "application/json") -> Response:
    return Response(json.dumps(data, ensure_ascii=False), status=status, content_type=content_type)


def problem(type_slug: str, title: str, status: int, detail: str | None = None) -> Response:
    body = Problem(type=type_slug, title=title, status=status, detail=detail).model_dump(
        exclude_none=True
    )
    return _json(body, status, "application/problem+json")


# ---------------------------------------------------------------------------
# Embedding
# ---------------------------------------------------------------------------
def embed(text: str | None, gcs_uri: str | None = None) -> list[float]:
    """gemini-embedding-2 でコンテンツを 2048 次元ベクトルに変換する。

    Google AI Studio (API Key 認証) は gs:// URI を直接読めないため、
    gcs_uri が指定された場合は GCS からバイナリをダウンロードして
    Part.from_bytes() でインラインデータとして渡す。
    """
    contents: list = []
    if text:
        contents.append(text)
    if gcs_uri:
        bucket_name, blob_path = _parse_gcs_uri(gcs_uri)
        blob = get_storage_client().bucket(bucket_name).blob(blob_path)
        data = blob.download_as_bytes()
        mime_type = blob.content_type or "application/octet-stream"
        contents.append(types.Part.from_bytes(data=data, mime_type=mime_type))

    result = get_genai_client().models.embed_content(
        model=EMBEDDING_MODEL,
        contents=contents,
        config={"output_dimensionality": EMBEDDING_DIMENSION},
    )
    return list(result.embeddings[0].values)


def _parse_gcs_uri(gcs_uri: str) -> tuple[str, str]:
    """gs://bucket/path/to/blob → (bucket, path/to/blob)"""
    without_scheme = gcs_uri.removeprefix("gs://")
    bucket_name, _, blob_path = without_scheme.partition("/")
    return bucket_name, blob_path


# ---------------------------------------------------------------------------
# Handlers
# ---------------------------------------------------------------------------
def handle_get_upload_url(request) -> Response:
    try:
        payload = UploadUrlRequest.model_validate_json(request.get_data())
    except ValidationError as e:
        return problem("validation_error", "Invalid request body", 400, str(e))

    if payload.content_type not in ALLOWED_CONTENT_TYPES:
        return problem(
            "validation_error",
            "Unsupported content_type",
            400,
            f"'{payload.content_type}' is not allowed. Supported: {sorted(ALLOWED_CONTENT_TYPES)}",
        )

    ext = pathlib.Path(payload.filename).suffix.lower()
    object_name = f"inputs/{uuid.uuid4()}{ext}"

    try:
        credentials, _ = google.auth.default()
        auth_req = google.auth.transport.requests.Request()
        credentials.refresh(auth_req)

        blob = get_storage_client().bucket(MEDIA_BUCKET).blob(object_name)
        upload_url = blob.generate_signed_url(
            version="v4",
            expiration=datetime.timedelta(minutes=5),
            method="PUT",
            content_type=payload.content_type,
            service_account_email=credentials.service_account_email,
            access_token=credentials.token,
        )
    except Exception:
        logger.exception("signed URL generation failed")
        return problem("internal_error", "Failed to generate upload URL", 500)

    gcs_uri = f"gs://{MEDIA_BUCKET}/{object_name}"
    return _json(UploadUrlResponse(upload_url=upload_url, gcs_uri=gcs_uri).model_dump(), 200)


def handle_create_document(request) -> Response:
    try:
        payload = DocumentCreateRequest.model_validate_json(request.get_data())
    except ValidationError as e:
        return problem("validation_error", "Invalid request body", 400, str(e))

    try:
        embedding = embed(payload.text, payload.gcs_uri)
    except Exception:
        logger.exception("embedding generation failed")
        return problem("internal_error", "Embedding generation failed", 500)

    doc_id = str(uuid.uuid4())
    doc_ref = get_firestore_client().collection(COLLECTION).document(doc_id)

    try:
        doc_ref.set(
            {
                "text": payload.text,
                "gcs_uri": payload.gcs_uri,
                "metadata": payload.metadata.model_dump() if payload.metadata else {},
                EMBEDDING_FIELD: Vector(embedding),
                "embedding_model": EMBEDDING_MODEL,
                "created_at": firestore.SERVER_TIMESTAMP,
            }
        )
        saved = doc_ref.get()
    except Exception:
        logger.exception("firestore write failed")
        return problem("internal_error", "Firestore write failed", 500)

    response = Document(
        id=doc_id,
        text=payload.text,
        gcs_uri=payload.gcs_uri,
        metadata=payload.metadata,
        created_at=saved.create_time,
    ).model_dump(mode="json", exclude_none=True)
    return _json(response, 201)


def handle_search(request) -> Response:
    try:
        payload = SearchRequest.model_validate_json(request.get_data())
    except ValidationError as e:
        return problem("validation_error", "Invalid request body", 400, str(e))

    try:
        query_vector = embed(payload.query, payload.gcs_uri)
    except Exception:
        logger.exception("query embedding failed")
        return problem("internal_error", "Embedding generation failed", 500)

    try:
        vector_query = get_firestore_client().collection(COLLECTION).find_nearest(
            vector_field=EMBEDDING_FIELD,
            query_vector=Vector(query_vector),
            distance_measure=DistanceMeasure.COSINE,
            limit=payload.top_k,
            distance_result_field=DISTANCE_RESULT_FIELD,
        )
        snapshots = list(vector_query.stream())
    except Exception:
        logger.exception("firestore find_nearest failed")
        return problem("internal_error", "Vector search failed", 500)

    results: list[SearchResult] = []
    for snap in snapshots:
        data = snap.to_dict() or {}
        distance = float(data.get(DISTANCE_RESULT_FIELD, 1.0))
        # COSINE distance ∈ [0, 2]、similarity = 1 - distance/2 とする実装もあるが、
        # Firestore は正規化済みベクトルを前提とした「1 - cosine_similarity」を返すため、
        # similarity = 1 - distance で扱う (ADR 0001)。
        score = max(0.0, min(1.0, 1.0 - distance))
        results.append(
            SearchResult(
                id=snap.id,
                text=data.get("text") or None,
                gcs_uri=data.get("gcs_uri") or None,
                metadata=data.get("metadata") or None,
                score=score,
            )
        )

    response = SearchResponse(results=results).model_dump(mode="json", exclude_none=True)
    return _json(response, 200)


# ---------------------------------------------------------------------------
# Entry point — path / method dispatch
# ---------------------------------------------------------------------------
@functions_framework.http
def main(request):
    path = request.path.rstrip("/") or "/"
    method = request.method

    # upload-url を /v1/documents より先にマッチさせる（プレフィックス衝突を防ぐ）
    if method == "POST" and path == "/v1/documents/upload-url":
        return handle_get_upload_url(request)
    if method == "POST" and path == "/v1/documents":
        return handle_create_document(request)
    if method == "POST" and path == "/v1/search":
        return handle_search(request)

    return problem(
        "not_found",
        "Path not found",
        404,
        detail=f"{method} {request.path} is not handled by vector-api",
    )
