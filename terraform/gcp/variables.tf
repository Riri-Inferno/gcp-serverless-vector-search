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
