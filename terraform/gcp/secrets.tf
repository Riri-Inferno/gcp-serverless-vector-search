# SOPS で暗号化されたシークレットを Secret Manager に投入する。
# 設計の詳細は ADR 0006 参照。
#
# CI 経路:
#   secrets/<name>.enc.yaml (git)
#     → GHA: sops decrypt → terraform/gcp/.decrypted/<name>.yaml (gitignore)
#     → terraform apply: yamldecode した値を Secret Manager の secret_data に投入
#
# 初回 KMS スタック追加時には enc.yaml が未配置のため、fileexists() で skip する。
# これにより count=0 で Secret Manager リソースが作られず、ユーザーは KMS key を
# 使って後からローカルで sops encrypt → enc.yaml を commit する流れに進める。

locals {
  decrypted_file = "${path.module}/.decrypted/gemini-api-key.yaml"
  decrypted      = fileexists(local.decrypted_file) ? yamldecode(file(local.decrypted_file)) : {}

  # try() で safe アクセス。decrypted が空 object のとき直接 `.gemini_api_key` を
  # 参照すると `terraform validate` の静的型チェック (count を解決しない) で
  # "object has no attributes" と落ちるため。
  gemini_api_key = try(local.decrypted.gemini_api_key, "")
}

resource "google_secret_manager_secret" "gemini_api_key" {
  count     = local.gemini_api_key != "" ? 1 : 0
  secret_id = "gemini-api-key"

  replication {
    auto {}
  }

  depends_on = [google_project_service.app_required]
}

resource "google_secret_manager_secret_version" "gemini_api_key" {
  count       = local.gemini_api_key != "" ? 1 : 0
  secret      = google_secret_manager_secret.gemini_api_key[0].id
  secret_data = local.gemini_api_key
}
