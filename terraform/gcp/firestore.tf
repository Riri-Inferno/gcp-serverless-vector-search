# Firestore Native mode database + ベクトル検索用インデックス。
#
# ADR 0001 で確定した仕様:
#   - コレクション: documents
#   - ベクトルフィールド: embedding (1536次元)
#   - 距離関数: COSINE (find_nearest 実行時にクエリ側で指定)
#   - 索引タイプ: FLAT (Firestore のベクトル検索は KNN flat 走査)
#
# Note: Firestore Native は location_id を一度確定すると変更不可。
# `asia-northeast1` (Tokyo) で固定する。

resource "google_firestore_database" "default" {
  project     = var.project_id
  name        = "(default)"
  location_id = "asia-northeast1"
  type        = "FIRESTORE_NATIVE"

  # 誤 destroy 防止。データ消失を防ぐためデフォルトで保護を有効化する。
  # データベースを本気で削除したい時だけ DISABLED に変更して apply → destroy。
  delete_protection_state = "DELETE_PROTECTION_ENABLED"

  depends_on = [google_project_service.app_required]
}

# ベクトル検索用インデックス。`documents` コレクションの `embedding` フィールドに対する
# インデックスを 1536次元・FLAT 走査で定義する。
#
# 仕様メモ:
#   - Firestore の Vector Index は `__name__` (ASCENDING) フィールドを **明示的に** 含めるのが
#     公式の正準形。`__name__` を省略すると API 側で自動付加されるが、state と乖離して
#     terraform plan で疑似 drift が発生するため、最初から明示する。
#     参考: https://firebase.google.com/docs/firestore/query-data/indexing
#   - 距離関数 (COSINE / EUCLIDEAN / DOT_PRODUCT) はインデックス設定ではなく、
#     クエリ側 (find_nearest) で都度指定する仕様。よって本インデックスは距離関数を
#     指定しない。Cloud Functions の実装側で COSINE を渡すこと。
resource "google_firestore_index" "documents_embedding" {
  project     = var.project_id
  database    = google_firestore_database.default.name
  collection  = "documents"
  query_scope = "COLLECTION"

  fields {
    field_path = "__name__"
    order      = "ASCENDING"
  }

  fields {
    field_path = "embedding"
    vector_config {
      dimension = 1536
      flat {}
    }
  }
}
