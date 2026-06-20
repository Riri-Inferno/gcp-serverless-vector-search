resource "google_storage_bucket" "tfstate" {
  name     = var.tfstate_bucket_name
  location = var.region

  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  versioning {
    enabled = true
  }

  # 誤削除防止。bucket 削除が必要な時だけ手動で true にして apply。
  force_destroy = false

  depends_on = [google_project_service.bootstrap_required]
}
