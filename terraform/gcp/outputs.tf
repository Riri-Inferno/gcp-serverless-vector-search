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
