# アプリリソースが必要とする Google API を有効化する。
# bootstrap 側の services.tf とは責務分離:
#   - bootstrap/services.tf: Terraform 自身が動くために必要な API
#   - gcp/services.tf:       アプリリソース (Cloud Functions / Firestore / API Gateway etc.) が必要な API
#
# 重複しても idempotent なので問題ないが、責務を分けて管理する。
locals {
  app_required_services = toset([
    "cloudfunctions.googleapis.com",     # Cloud Functions Gen2 (実体は Cloud Run)
    "run.googleapis.com",                # Cloud Functions Gen2 が裏で使う Cloud Run
    "cloudbuild.googleapis.com",         # Functions のコンテナイメージビルド
    "artifactregistry.googleapis.com",   # ビルド済みイメージの格納先
    "secretmanager.googleapis.com",      # Google AI Studio API Key 保管
    "firestore.googleapis.com",          # ベクトル + メタデータ DB
    "apigateway.googleapis.com",         # API Gateway 本体
    "servicemanagement.googleapis.com",  # API Gateway の OpenAPI 設定 deploy に必須
    "servicecontrol.googleapis.com",     # API Gateway runtime のサービスコントロール
    "cloudkms.googleapis.com",           # SOPS の暗号化先 KMS key を管理 (ADR 0006)
    "apikeys.googleapis.com",            # google_apikeys_key リソース (API Gateway の API Key)
  ])
}

resource "google_project_service" "app_required" {
  for_each = local.app_required_services
  project  = var.project_id
  service  = each.value

  # API を Terraform destroy で消されると後続運用が破滅するので保護。
  disable_on_destroy = false
}
