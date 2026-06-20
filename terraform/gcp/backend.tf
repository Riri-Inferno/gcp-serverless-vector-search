terraform {
  backend "gcs" {
    bucket = "riri-vector-lab-2026-tfstate"
    prefix = "gcp"
  }
}
# GCS backend は object generation ベースで暗黙にロックされるため、追加のロック設定は不要。
# `use_lockfile = true` は S3 backend 専用 (Terraform 1.13 以降) の機能であり、GCS では未サポート。
