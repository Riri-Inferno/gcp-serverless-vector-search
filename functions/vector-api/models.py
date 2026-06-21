"""Pydantic v2 models matching api/openapi.yaml.

OpenAPI 仕様 (`api/openapi.yaml`) と本ファイルは契約として一致させる。スキーマを
変える場合は両方を同期させること。
"""

from datetime import datetime
from typing import Any

from pydantic import BaseModel, ConfigDict, Field


class Metadata(BaseModel):
    """Free-form metadata. OpenAPI 上 additionalProperties: true。"""

    model_config = ConfigDict(extra="allow")


class DocumentCreateRequest(BaseModel):
    text: str = Field(min_length=1, max_length=8000)
    metadata: Metadata | None = None


class Document(BaseModel):
    id: str
    text: str
    metadata: Metadata | None = None
    created_at: datetime


class SearchRequest(BaseModel):
    query: str = Field(min_length=1, max_length=8000)
    top_k: int = Field(default=10, ge=1, le=50)


class SearchResult(BaseModel):
    id: str
    text: str
    metadata: Metadata | None = None
    score: float = Field(ge=0, le=1)


class SearchResponse(BaseModel):
    results: list[SearchResult]


class Problem(BaseModel):
    """RFC 7807 風のエラーレスポンス。`type` は URI ではなくスラグ文字列。"""

    type: str
    title: str
    status: int
    detail: str | None = None
