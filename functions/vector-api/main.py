"""Vector API Cloud Function.

ADR 0005 の判断に従い、/v1/documents と /v1/search を同一関数に同居させる
(両方 genai SDK + Firestore client を共有するため)。

リクエスト経路 (本番): Cloudflare → API Gateway → 本関数。
API Gateway 段で API Key 認証が済んでいる前提なので、本関数では認証を行わない
(ADR 0003 / docs/security.md D2-D3 参照)。
"""

from __future__ import annotations

import logging
import os
import uuid

import functions_framework
import json
from flask import Response
from google import genai
from google.cloud import firestore
from google.cloud.firestore_v1.base_vector_query import DistanceMeasure
from google.cloud.firestore_v1.vector import Vector
from pydantic import ValidationError

from models import (
    Document,
    DocumentCreateRequest,
    Problem,
    SearchRequest,
    SearchResponse,
    SearchResult,
)

# ---------------------------------------------------------------------------
# 設定 (ADR 0001 / 0004 / 0005 で確定済みの値を hardcode)
# ---------------------------------------------------------------------------
EMBEDDING_MODEL = "gemini-embedding-2"
EMBEDDING_DIMENSION = 3072
COLLECTION = "documents"
EMBEDDING_FIELD = "embedding"
DISTANCE_RESULT_FIELD = "vector_distance"  # find_nearest が距離を書き込むフィールド名

# ---------------------------------------------------------------------------
# Clients (warm 状態でリクエスト間に共有される module-level singleton)
# ---------------------------------------------------------------------------
logging.basicConfig(level=os.environ.get("LOG_LEVEL", "INFO"))
logger = logging.getLogger(__name__)

_genai_client: genai.Client | None = None
_firestore_client: firestore.Client | None = None


def get_genai_client() -> genai.Client:
    global _genai_client
    if _genai_client is None:
        api_key = os.environ["GEMINI_API_KEY"]  # 未設定なら起動時に KeyError で fail-fast
        _genai_client = genai.Client(api_key=api_key)
    return _genai_client


def get_firestore_client() -> firestore.Client:
    global _firestore_client
    if _firestore_client is None:
        _firestore_client = firestore.Client()
    return _firestore_client


# ---------------------------------------------------------------------------
# Response helpers
# ---------------------------------------------------------------------------
def _json(data: dict, status: int = 200, content_type: str = "application/json") -> Response:
    return Response(json.dumps(data, ensure_ascii=False), status=status, content_type=content_type)


def problem(type_slug: str, title: str, status: int, detail: str | None = None):
    body = Problem(type=type_slug, title=title, status=status, detail=detail).model_dump(
        exclude_none=True
    )
    return _json(body, status, "application/problem+json")


# ---------------------------------------------------------------------------
# Embedding
# ---------------------------------------------------------------------------
def embed(text: str) -> list[float]:
    """gemini-embedding-2 でテキストを 3072 次元ベクトルに変換する。"""
    result = get_genai_client().models.embed_content(
        model=EMBEDDING_MODEL,
        contents=text,
        config={"output_dimensionality": EMBEDDING_DIMENSION},
    )
    return list(result.embeddings[0].values)


# ---------------------------------------------------------------------------
# Handlers
# ---------------------------------------------------------------------------
def handle_create_document(request):
    try:
        payload = DocumentCreateRequest.model_validate_json(request.get_data())
    except ValidationError as e:
        return problem("validation_error", "Invalid request body", 400, str(e))

    try:
        embedding = embed(payload.text)
    except Exception:
        logger.exception("embedding generation failed")
        return problem("internal_error", "Embedding generation failed", 500)

    doc_id = str(uuid.uuid4())
    doc_ref = get_firestore_client().collection(COLLECTION).document(doc_id)

    try:
        doc_ref.set(
            {
                "text": payload.text,
                "metadata": payload.metadata.model_dump() if payload.metadata else {},
                EMBEDDING_FIELD: Vector(embedding),
                "embedding_model": EMBEDDING_MODEL,
                "created_at": firestore.SERVER_TIMESTAMP,
            }
        )
        # createTime / create_at を再取得するため reread (Firestore は書き込み時点で
        # SERVER_TIMESTAMP を解決するため、書き込み直後でないと値が取れない)
        saved = doc_ref.get()
    except Exception:
        logger.exception("firestore write failed")
        return problem("internal_error", "Firestore write failed", 500)

    response = Document(
        id=doc_id,
        text=payload.text,
        metadata=payload.metadata,
        created_at=saved.create_time,
    ).model_dump(mode="json", exclude_none=True)
    return _json(response, 201)


def handle_search(request):
    try:
        payload = SearchRequest.model_validate_json(request.get_data())
    except ValidationError as e:
        return problem("validation_error", "Invalid request body", 400, str(e))

    try:
        query_vector = embed(payload.query)
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
                text=data.get("text", ""),
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
