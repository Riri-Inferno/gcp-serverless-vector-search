# Workload Identity Pool for GitHub Actions OIDC.
#
# Provider 側の attribute_condition で repository pin することで、別リポジトリの
# OIDC token では impersonation できないようにする（信頼境界の第一層）。
resource "google_iam_workload_identity_pool" "main" {
  workload_identity_pool_id = var.wif_pool_id
  display_name              = "GitHub Actions Pool"
  description               = "WIF Pool for GitHub Actions in ${var.github_repo}"

  depends_on = [google_project_service.bootstrap_required]
}

resource "google_iam_workload_identity_pool_provider" "github_actions" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.main.workload_identity_pool_id
  workload_identity_pool_provider_id = var.wif_provider_id
  display_name                       = "GitHub Actions"

  # repo pin — このリポジトリ発行の OIDC token 以外は弾く
  attribute_condition = "assertion.repository == '${var.github_repo}'"

  attribute_mapping = {
    "google.subject"             = "assertion.sub"
    "attribute.repository"       = "assertion.repository"
    "attribute.repository_owner" = "assertion.repository_owner"
    "attribute.ref"              = "assertion.ref"
  }

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}
