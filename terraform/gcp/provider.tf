provider "google" {
  project = var.project_id
  region  = var.region
}

# API Gateway リソース (google_api_gateway_*) は google-beta provider 必須のため別途定義する。
provider "google-beta" {
  project = var.project_id
  region  = var.region
}
