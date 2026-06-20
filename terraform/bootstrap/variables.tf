variable "project_id" {
  type        = string
  description = "GCP project ID. Bootstrap creates everything in this project."
  default     = "riri-vector-lab-2026"
}

variable "region" {
  type        = string
  description = "Default region for regional resources (state bucket location, future Cloud Functions region)."
  default     = "asia-northeast1"
}

variable "github_repo" {
  type        = string
  description = "GitHub repo in 'owner/name' form. Used to pin WIF Provider attribute_condition."
  default     = "Riri-Inferno/gcp-serverless-vector-search"
}

variable "tfstate_bucket_name" {
  type        = string
  description = "Name of the GCS bucket holding terraform state. Must be globally unique."
  default     = "riri-vector-lab-2026-tfstate"
}

variable "wif_pool_id" {
  type        = string
  description = "Workload Identity Pool ID. Project-scoped name."
  default     = "gh-actions-pool"
}

variable "wif_provider_id" {
  type        = string
  description = "Workload Identity Pool Provider ID under the pool."
  default     = "github-actions"
}

variable "ci_sa_account_id" {
  type        = string
  description = "Account ID prefix for the Terraform CI service account. Becomes <id>@<project>.iam.gserviceaccount.com."
  default     = "terraform-ci"
}
