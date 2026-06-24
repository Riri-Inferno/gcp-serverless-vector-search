"""Pydantic v2 models matching api/openapi.yaml.

OpenAPI 仕様 (`api/openapi.yaml`) と本ファイルは契約として一致させる。スキーマを
変える場合は両方を同期させること。
"""

from datetime import datetime
from typing import Any

from pydantic import BaseModel, ConfigDict, Field, model_validator


class Metadata(BaseModel):
    """Free-form metadata. OpenAPI 上 additionalProperties: true。"""

    model_config = ConfigDict(extra="allow")


class UploadUrlRequest(BaseModel):
    filename: str = Field(min_length=1)
    content_type: str = Field(min_length=1)


class UploadUrlResponse(BaseModel):
    upload_url: str
    gcs_uri: str


class DownloadUrlRequest(BaseModel):
    gcs_uri: str = Field(pattern=r"^gs://.+")


class DownloadUrlResponse(BaseModel):
    download_url: str


class DocumentCreateRequest(BaseModel):
    text: str | None = Field(default=None, min_length=1, max_length=8000)
    gcs_uri: str | None = Field(default=None, pattern=r"^gs://.+")
    metadata: Metadata | None = None

    @model_validator(mode="after")
    def at_least_one_required(self) -> "DocumentCreateRequest":
        if self.text is None and self.gcs_uri is None:
            raise ValueError("text または gcs_uri のどちらか一方は必須")
        return self


class Document(BaseModel):
    id: str
    text: str | None = None
    gcs_uri: str | None = None
    metadata: Metadata | None = None
    created_at: datetime


class SearchRequest(BaseModel):
    query: str | None = Field(default=None, min_length=1, max_length=8000)
    gcs_uri: str | None = Field(default=None, pattern=r"^gs://.+")
    top_k: int = Field(default=10, ge=1, le=50)

    @model_validator(mode="after")
    def at_least_one_required(self) -> "SearchRequest":
        if self.query is None and self.gcs_uri is None:
            raise ValueError("query または gcs_uri のどちらか一方は必須")
        return self


class SearchResult(BaseModel):
    id: str
    text: str | None = None
    gcs_uri: str | None = None
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
