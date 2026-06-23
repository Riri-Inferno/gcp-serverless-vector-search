# メディア保管用GCSバケット（画像・音声など）
resource "google_storage_bucket" "media_bucket" {
  name     = "${var.project_id}-media-inputs"
  location = var.region

  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  # デモ用途のため terraform destroy 時にオブジェクトが残っていても削除を許可
  force_destroy = true

  # フロントエンド（Firebase Hosting 等）からブラウザが直接 PUT できるよう許可
  # origin は本番化の際に Firebase Hosting ドメインへ絞ること
  cors {
    origin          = ["*"]
    method          = ["PUT", "OPTIONS"]
    response_header = ["Content-Type", "x-goog-resumable"]
    max_age_seconds = 3600
  }

  # デモデータが堆積して課金が跳ねないよう 30 日で自動削除
  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type = "Delete"
    }
  }

  depends_on = [google_project_service.app_required]
}

# ---------------------------------------------------------------------------
# IAM: vector-api SA → media_bucket
#
# roles/storage.objectAdmin: アップロード完了後のオブジェクト存在確認に必要
# roles/iam.serviceAccountTokenCreator: V4 署名付き URL 生成 (signBlob) に必要
# ---------------------------------------------------------------------------

resource "google_storage_bucket_iam_member" "vector_api_media_object_admin" {
  bucket = google_storage_bucket.media_bucket.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.vector_api_runtime.email}"
}

# V4 署名付き URL は SA 自身が signBlob を呼ぶため、SA 自身に TokenCreator を付与する
resource "google_service_account_iam_member" "vector_api_self_token_creator" {
  service_account_id = google_service_account.vector_api_runtime.name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "serviceAccount:${google_service_account.vector_api_runtime.email}"
}
