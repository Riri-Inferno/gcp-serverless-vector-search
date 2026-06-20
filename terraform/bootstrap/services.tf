# Bootstrap apply 自身が必要とする最小限の Google API のみ宣言する。
# アプリリソース固有の API（cloudfunctions / run / secretmanager / firestore /
# apigateway 等）は terraform/gcp/ 側で enable する。
#
# Note: 初回 apply の前にユーザー側で `gcloud services enable ...` で同じ API を
# 有効化済み。本リソースは state = reality を取り戻し、以降の管理を IaC に寄せるため。
locals {
  bootstrap_required_services = toset([
    "cloudresourcemanager.googleapis.com", # project IAM の読み書き
    "iam.googleapis.com",                  # service accounts, custom roles
    "iamcredentials.googleapis.com",       # impersonation (generateAccessToken)
    "sts.googleapis.com",                  # WIF token exchange
    "storage.googleapis.com",              # state bucket
    "serviceusage.googleapis.com",         # 他 API の enable/disable（terraform/gcp で使用）
  ])
}

resource "google_project_service" "bootstrap_required" {
  for_each = local.bootstrap_required_services
  project  = var.project_id
  service  = each.value

  # API を Terraform destroy で消されると後続運用が破滅するので保護。
  disable_on_destroy = false
}
