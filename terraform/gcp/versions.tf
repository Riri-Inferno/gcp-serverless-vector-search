terraform {
  # GCS backend の native lock (`use_lockfile = true`) は Terraform 1.10 以降のため、
  # bootstrap (≥ 1.5) より厳しい floor を設定する。実バージョンは terraform/.terraform-version で pin。
  required_version = ">= 1.10"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}
