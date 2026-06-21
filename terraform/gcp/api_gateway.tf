# API Gateway: 外部公開エンドポイント + API Key 認証 + Cloud Functions ルーティング。
# 設計の根拠は docs/security.md (D2-D3) / ADR 0001 / ADR 0003 を参照。
#
# 全体経路 (本番):
#   Cloudflare → API Gateway → (API Key 検証 + jwt_audience) → Cloud Functions (Cloud Run IAM)

# ---------------------------------------------------------------------------
# OpenAPI yaml に Cloud Functions の実 URL を埋め込んで render
# ---------------------------------------------------------------------------
locals {
  openapi_rendered = templatefile("${path.module}/../../api/openapi.yaml", {
    healthz_url    = google_cloudfunctions2_function.healthz.service_config[0].uri
    vector_api_url = length(google_cloudfunctions2_function.vector_api) > 0 ? google_cloudfunctions2_function.vector_api[0].service_config[0].uri : ""
  })
}

# ---------------------------------------------------------------------------
# API Gateway 用 Service Account
# Cloud Functions (内部 Cloud Run) を呼ぶための roles/run.invoker を保持する。
# ---------------------------------------------------------------------------
resource "google_service_account" "api_gateway" {
  account_id   = "api-gateway"
  display_name = "API Gateway runtime SA"
}

resource "google_cloud_run_v2_service_iam_member" "invoke_healthz" {
  project  = var.project_id
  location = var.region
  name     = google_cloudfunctions2_function.healthz.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.api_gateway.email}"
}

resource "google_cloud_run_v2_service_iam_member" "invoke_vector_api" {
  count    = length(google_cloudfunctions2_function.vector_api)
  project  = var.project_id
  location = var.region
  name     = google_cloudfunctions2_function.vector_api[0].name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.api_gateway.email}"
}

# ---------------------------------------------------------------------------
# API Gateway リソース三段 (api → api_config → gateway)
# ---------------------------------------------------------------------------
resource "google_api_gateway_api" "vector_search" {
  provider = google-beta
  api_id   = "vector-search"

  depends_on = [google_project_service.app_required]
}

resource "google_api_gateway_api_config" "vector_search" {
  provider             = google-beta
  api                  = google_api_gateway_api.vector_search.api_id
  api_config_id_prefix = "config-"

  openapi_documents {
    document {
      path     = "openapi.yaml"
      contents = base64encode(local.openapi_rendered)
    }
  }

  gateway_config {
    backend_config {
      google_service_account = google_service_account.api_gateway.email
    }
  }

  # OpenAPI 内容が変わると新 config を作って差し替える運用。同名 config を上書きできないため。
  lifecycle {
    create_before_destroy = true
  }
}

resource "google_api_gateway_gateway" "vector_search" {
  provider   = google-beta
  api_config = google_api_gateway_api_config.vector_search.id
  gateway_id = "vector-search-gateway"
  region     = var.region

  depends_on = [google_api_gateway_api_config.vector_search]
}

# API Gateway がデプロイ時に動的に作る managed service を有効化する。
# これが無いと API Key 経由の呼出で 403 "API has not been used in project ... before
# or it is disabled" が返る。managed service 名は google_api_gateway_api のリソース
# 作成時に確定するため、services.tf 内の static set には入れられず本ファイルで個別に
# 宣言する。
resource "google_project_service" "vector_search_managed_service" {
  project            = var.project_id
  service            = google_api_gateway_api.vector_search.managed_service
  disable_on_destroy = false
}

# ---------------------------------------------------------------------------
# API Key
# 値そのもの (key_string) は state に sensitive 値として保持される。配布は GCP コンソール
# or `terraform output -raw api_key` で取り出す運用。
# ---------------------------------------------------------------------------
resource "google_apikeys_key" "vector_search" {
  name         = "vector-search-api-key"
  display_name = "Vector Search API Key"

  restrictions {
    api_targets {
      service = google_api_gateway_api.vector_search.managed_service
    }
  }

  depends_on = [google_api_gateway_api.vector_search]
}
