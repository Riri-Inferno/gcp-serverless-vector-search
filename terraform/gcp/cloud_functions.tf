# Cloud Functions Gen2 デプロイ (ADR 0005 の関数分割粒度に従う)。
#
#   - healthz       : GET /healthz 専用、最小依存・最小メモリ
#   - vector-api    : POST /v1/documents, POST /v1/search、genai + Firestore
#
# ローカル動作確認は functions/README.md 参照。
# API Gateway 経由でのアクセス制御は PR-γ (api/openapi.yaml の x-google-backend + IAM) で組む。

# ---------------------------------------------------------------------------
# Functions ソース格納用 GCS bucket
# ---------------------------------------------------------------------------
resource "google_storage_bucket" "functions_source" {
  name     = "${var.project_id}-functions-source"
  location = var.region

  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  versioning {
    enabled = true
  }

  # 個人ラボなので、bucket 削除 = ソース履歴消える前提で許可
  force_destroy = true

  depends_on = [google_project_service.app_required]
}

# ---------------------------------------------------------------------------
# Functions ソースを zip 化 & GCS にアップロード
#
# 出力 zip 名にハッシュを含めることで、コード変更時に新しい object として
# アップロードされ、Cloud Function 側が自動的に再デプロイをトリガする。
# ---------------------------------------------------------------------------

data "archive_file" "healthz_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../../functions/healthz"
  output_path = "${path.module}/.builds/healthz.zip"
  excludes    = ["__pycache__", ".venv", "*.pyc"]
}

data "archive_file" "vector_api_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../../functions/vector-api"
  output_path = "${path.module}/.builds/vector-api.zip"
  excludes    = ["__pycache__", ".venv", "*.pyc"]
}

resource "google_storage_bucket_object" "healthz_source" {
  name   = "healthz-${data.archive_file.healthz_zip.output_md5}.zip"
  bucket = google_storage_bucket.functions_source.name
  source = data.archive_file.healthz_zip.output_path
}

resource "google_storage_bucket_object" "vector_api_source" {
  name   = "vector-api-${data.archive_file.vector_api_zip.output_md5}.zip"
  bucket = google_storage_bucket.functions_source.name
  source = data.archive_file.vector_api_zip.output_path
}

# ---------------------------------------------------------------------------
# Runtime Service Accounts (各 Cloud Function が動く時の SA)
#
# 最小権限の原則 (docs/security.md D3) に従い、関数ごとに別 SA とする。
# healthz には Firestore / Secret Manager 等のアプリ依存ロールは一切付けない。
# ---------------------------------------------------------------------------

resource "google_service_account" "healthz_runtime" {
  account_id   = "healthz-runtime"
  display_name = "Healthz Cloud Function Runtime"
}

resource "google_service_account" "vector_api_runtime" {
  account_id   = "vector-api-runtime"
  display_name = "Vector API Cloud Function Runtime"
}

# vector-api: Firestore 読み書き
resource "google_project_iam_member" "vector_api_datastore_user" {
  project = var.project_id
  role    = "roles/datastore.user"
  member  = "serviceAccount:${google_service_account.vector_api_runtime.email}"
}

# vector-api: GEMINI_API_KEY (Secret Manager) を読む権限
resource "google_secret_manager_secret_iam_member" "vector_api_gemini_key_accessor" {
  count     = length(google_secret_manager_secret.gemini_api_key)
  secret_id = google_secret_manager_secret.gemini_api_key[0].id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.vector_api_runtime.email}"
}

# ---------------------------------------------------------------------------
# healthz Cloud Function
# ---------------------------------------------------------------------------
resource "google_cloudfunctions2_function" "healthz" {
  name     = "healthz"
  location = var.region

  build_config {
    runtime     = "python313"
    entry_point = "main"

    source {
      storage_source {
        bucket = google_storage_bucket.functions_source.name
        object = google_storage_bucket_object.healthz_source.name
      }
    }
  }

  service_config {
    available_memory      = "128Mi"
    timeout_seconds       = 10
    max_instance_count    = 3 # docs/security.md D5 の物理キャップ
    min_instance_count    = 0 # コールドスタートが許容できなくなったら 1 に
    service_account_email = google_service_account.healthz_runtime.email
    ingress_settings      = "ALLOW_ALL"   # API Gateway 経由 (PR-γ)、ただし IAM 認証は維持
  }

  depends_on = [google_project_service.app_required]
}

# ---------------------------------------------------------------------------
# vector-api Cloud Function
#
# Secret Manager の gemini-api-key が未投入 (count=0) のときは
# 本 Cloud Function も作らない。enc.yaml を commit 済みで初めてデプロイされる。
# ---------------------------------------------------------------------------
resource "google_cloudfunctions2_function" "vector_api" {
  count    = length(google_secret_manager_secret_version.gemini_api_key)
  name     = "vector-api"
  location = var.region

  build_config {
    runtime     = "python313"
    entry_point = "main"

    source {
      storage_source {
        bucket = google_storage_bucket.functions_source.name
        object = google_storage_bucket_object.vector_api_source.name
      }
    }
  }

  service_config {
    available_memory      = "512Mi"
    timeout_seconds       = 60
    max_instance_count    = 3 # docs/security.md D5 の物理キャップ
    service_account_email = google_service_account.vector_api_runtime.email
    ingress_settings      = "ALLOW_ALL"

    # GEMINI_API_KEY は Secret Manager 経由で env として注入する (ADR 0006)
    secret_environment_variables {
      key        = "GEMINI_API_KEY"
      project_id = var.project_id
      secret     = google_secret_manager_secret.gemini_api_key[0].secret_id
      version    = "latest"
    }
  }

  depends_on = [
    google_project_service.app_required,
    google_secret_manager_secret_version.gemini_api_key,
    google_secret_manager_secret_iam_member.vector_api_gemini_key_accessor,
  ]
}
