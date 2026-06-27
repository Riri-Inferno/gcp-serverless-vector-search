variable "project_id" {
  type        = string
  description = "GCP project ID."
  default     = "riri-vector-lab-2026"
}

variable "region" {
  type        = string
  description = "Default region for regional resources (Cloud Functions / API Gateway 等)."
  default     = "asia-northeast1"
}

variable "admin_user_email" {
  type        = string
  description = "GCP プロジェクトの管理者ユーザー (人間)。KMS key の encrypter/decrypter を付与してローカルでの sops encrypt を許可する (ADR 0006)。"
  default     = "takayo.uenter36@gmail.com"
}
