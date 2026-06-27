# Terraform CI 用の Service Account と、その SA に必要な IAM 権限を集約する。
#
# 信頼境界の整理:
#   1. WIF Provider 側で repository pin (wif.tf の attribute_condition)
#   2. CI SA への impersonation を repository == github_repo な principal に限定
#      (下の google_service_account_iam_member.terraform_ci_wif)
# この2段で「このリポジトリの GitHub Actions だけがこの SA で動かせる」を担保する。
#
# Project-level の roles は docs/terraform-gitops.md の方針通り、初期は強めに付与し
# 安定後に縮小する。home-raspi-iac での実績に従い editor + 個別 admin role 構成。

data "google_project" "self" {
  project_id = var.project_id
}

resource "google_service_account" "terraform_ci" {
  account_id   = var.ci_sa_account_id
  display_name = "Terraform CI (GitHub Actions)"
  description  = "GitHub Actions が WIF 経由で impersonate して terraform plan/apply を実行する"
}

# WIF からの impersonation 許可。principalSet は repository attribute でフィルタ。
resource "google_service_account_iam_member" "terraform_ci_wif" {
  service_account_id = google_service_account.terraform_ci.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/projects/${data.google_project.self.number}/locations/global/workloadIdentityPools/${google_iam_workload_identity_pool.main.workload_identity_pool_id}/attribute.repository/${var.github_repo}"
}

# state bucket への objectAdmin（読み書き）。bucket 自体の管理権限は project IAM の
# storage.admin で別途付与（下記）。
resource "google_storage_bucket_iam_member" "terraform_ci_bucket_object_admin" {
  bucket = google_storage_bucket.tfstate.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.terraform_ci.email}"
}

# Project-level roles。
#
# editor は広範な resource CRUD を含むが、リソース個別の setIamPolicy や
# IAM 系の admin は含まれないため、個別に追加が必要。
locals {
  ci_sa_project_roles = toset([
    "roles/editor",                          # 広範な resource CRUD（IAM 系は含まない）
    "roles/iam.serviceAccountAdmin",         # SA CRUD
    "roles/iam.workloadIdentityPoolAdmin",   # WIF（将来 terraform/gcp で更新する場合に備え）
    "roles/resourcemanager.projectIamAdmin", # project IAM
    "roles/serviceusage.serviceUsageAdmin",  # API enable（terraform/gcp 側で必要）
    "roles/storage.admin",                   # bucket setIamPolicy（editor に含まれない）
    "roles/secretmanager.admin",             # Secret Manager resource-level IAM
    "roles/run.admin",                       # Cloud Functions Gen2（内部的に Cloud Run）
    "roles/cloudfunctions.admin",            # Cloud Functions API
    "roles/datastore.owner",                 # Firestore + ベクトルインデックス
    "roles/apigateway.admin",                # API Gateway
    "roles/cloudkms.admin",                  # KMS key resource-level IAM (SOPS 用、ADR 0006)
  ])
}

resource "google_project_iam_member" "terraform_ci_project_roles" {
  for_each = local.ci_sa_project_roles
  project  = var.project_id
  role     = each.value
  member   = "serviceAccount:${google_service_account.terraform_ci.email}"
}
