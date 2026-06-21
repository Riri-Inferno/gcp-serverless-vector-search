data "google_project" "self" {
  project_id = var.project_id
}

output "project_number" {
  value       = data.google_project.self.number
  description = "GCP project number. 後続のリソース定義 (WIF principalSet 等) で参照する。"
}

output "enabled_services" {
  value       = sort([for s in google_project_service.app_required : s.service])
  description = "本ディレクトリで有効化している Google API の一覧。"
}

output "api_gateway_url" {
  value       = "https://${google_api_gateway_gateway.vector_search.default_hostname}"
  description = "API Gateway のデフォルトホスト名 (Cloudflare の CNAME 先になる)。"
}

output "api_key" {
  value       = google_apikeys_key.vector_search.key_string
  description = "Vector Search API Key の値。クライアントが X-API-Key ヘッダで使う。"
  sensitive   = true
}

