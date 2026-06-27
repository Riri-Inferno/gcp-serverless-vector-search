output "tfstate_bucket" {
  value       = google_storage_bucket.tfstate.name
  description = "GCS bucket name. terraform/gcp/backend.tf でこれを参照する。"
}

output "tfstate_bucket_location" {
  value       = google_storage_bucket.tfstate.location
  description = "Region of the state bucket."
}

output "github_actions_wif_provider" {
  value       = "projects/${data.google_project.self.number}/locations/global/workloadIdentityPools/${google_iam_workload_identity_pool.main.workload_identity_pool_id}/providers/${google_iam_workload_identity_pool_provider.github_actions.workload_identity_pool_provider_id}"
  description = "Full WIF provider resource path. GitHub Actions workflow の google-github-actions/auth に workload_identity_provider として渡す。"
}

output "terraform_ci_sa_email" {
  value       = google_service_account.terraform_ci.email
  description = "SA email that GitHub Actions impersonates. google-github-actions/auth に service_account として渡す。"
}

output "project_number" {
  value       = data.google_project.self.number
  description = "GCP project number。WIF principalSet 等で参照用。"
}
