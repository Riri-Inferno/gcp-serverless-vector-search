# SOPS 暗号化用の KMS keyring + key。
# 用途・設計判断の根拠は ADR 0006 参照。

resource "google_kms_key_ring" "sops" {
  name     = "sops"
  location = "global"

  depends_on = [google_project_service.app_required]
}

resource "google_kms_crypto_key" "sops" {
  name     = "sops-key"
  key_ring = google_kms_key_ring.sops.id
  purpose  = "ENCRYPT_DECRYPT"

  # rotation は設定しない。理由: rotation で古い key version が destroy_scheduled に
  # なると、過去の enc.yaml が永久に復号できなくなるリスクがある。漏洩時は手動で
  # 全シークレット再暗号化する判断 (ADR 0006)。

  # 誤削除すると過去の全 enc.yaml が永久に復号不能になるため必須。
  lifecycle {
    prevent_destroy = true
  }
}

# CI が GHA で sops decrypt を実行するための権限。
resource "google_kms_crypto_key_iam_member" "sops_ci_sa" {
  crypto_key_id = google_kms_crypto_key.sops.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:terraform-ci@${var.project_id}.iam.gserviceaccount.com"
}

# 管理者ユーザーがローカルで暗号化/編集するための権限。
resource "google_kms_crypto_key_iam_member" "sops_admin" {
  crypto_key_id = google_kms_crypto_key.sops.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "user:${var.admin_user_email}"
}
