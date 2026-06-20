# Phase 0 Bootstrap は local backend で初回 apply する。
#
# このディレクトリで GCS backend bucket そのものを作る側なので、最初は backend を
# 持てない（鶏が先か卵が先か）。state_bucket.tf で bucket を作成したあと、
# 必要であれば下のブロックをコメントアウトして `terraform init -migrate-state` で
# state を GCS bucket に移行できる。
#
# 一度 bootstrap が完了すれば滅多に再 apply しないリソース群のため、本リポでは
# local state のまま運用しても実害は小さい（運用方針は docs/terraform-gitops.md を参照）。
#
# terraform {
#   backend "gcs" {
#     bucket       = "riri-vector-lab-2026-tfstate"
#     prefix       = "bootstrap"
#     use_lockfile = true
#   }
# }
