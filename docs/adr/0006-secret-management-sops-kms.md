# ADR 0006: シークレット管理 (SOPS + Cloud KMS)

- **Date**: 2026-06-21
- **Status**: Accepted

## Context

`GEMINI_API_KEY` を皮切りに、Cloud Functions に渡す機密値を扱う必要がある。本プロジェクトの不変則:

- **「git push = インフラ実態に反映」原則** を崩さない
- 平文を git に入れない / Secret Manager に手動投入 (out-of-band) しない / 長期鍵を GitHub Secrets に置かない

これらを満たす標準解として、暗号化済みシークレットを git に commit し、CI 経路で復号して Secret Manager に流す方式を採用する。

## Decision

### 全体フロー

```
git: secrets/<name>.enc.yaml                  (SOPS 暗号化、commit 対象)
   │
   ▼ GitHub Actions (apply workflow 内)
sops decrypt → terraform/gcp/.decrypted/<name>.yaml   (plain、gitignore、CI内のみ)
   │
   ▼ terraform apply
google_secret_manager_secret_version.secret_data  (Secret Manager に投入)
   │
   ▼ Cloud Functions 起動時
SM から取得 → env var として注入 → アプリが os.environ で参照
```

### 確定方針サマリ

| # | 論点 | 採用 |
|---|------|------|
| 1 | 暗号化バックエンド          | **SOPS + Google Cloud KMS** |
| 2 | KMS リソース管理場所        | **`terraform/gcp/`** (bootstrap を肥大化させない) |
| 3 | CI 復号経路                 | **CI で復号 → Secret Manager 投入 → ランタイムは SM 参照** |
| 4 | SOPS ファイル配置           | **`secrets/<name>.enc.yaml`** (リポジトリ root にフラット) + `.sops.yaml` も root |
| 5 | KMS への IAM                | CI SA (`terraform-ci@...`) + 管理者ユーザー (`takayo.uenter36@gmail.com`) の **両方に encrypter/decrypter** |
| 6 | plaintext 保護              | `.gitignore` で `secrets/*.yaml` (素) と `terraform/gcp/.decrypted/` を ignore |
| 7 | ADR の詳細度                | **方針 + 具体実装サンプルまで本 ADR にまとめる** |
| 8 | 初期対象シークレット        | **`GEMINI_API_KEY` のみ** |

### 具体実装

#### `.sops.yaml` (リポジトリ root)

```yaml
creation_rules:
  - path_regex: secrets/.*\.enc\.yaml$
    encrypted_regex: ^.*$
    gcp_kms: projects/riri-vector-lab-2026/locations/global/keyRings/sops/cryptoKeys/sops-key
```

`.sops.yaml` は **暗号化対象を示すメタデータのみで秘密値を含まない** ため、git にコミットする。

#### `terraform/gcp/services.tf` 追加

`local.app_required_services` に以下を追加:

```hcl
"cloudkms.googleapis.com",   # SOPS の暗号化先 KMS key を扱う
```

#### `terraform/gcp/kms.tf` (新規)

```hcl
resource "google_kms_key_ring" "sops" {
  name     = "sops"
  location = "global"

  depends_on = [google_project_service.app_required]
}

resource "google_kms_crypto_key" "sops" {
  name     = "sops-key"
  key_ring = google_kms_key_ring.sops.id
  purpose  = "ENCRYPT_DECRYPT"

  # rotation は設定しない。理由: rotation すると古い key version で暗号化済みの
  # enc.yaml の復号に version 解決が必要になり、運用が煩雑になる。個人ラボでは
  # 暴露時に手動で全シークレット再暗号化する判断で十分。

  # 誤削除すると過去の全 enc.yaml が永久に復号不能になるため必須。
  lifecycle {
    prevent_destroy = true
  }
}

# CI が GHA で sops decrypt を実行するための権限
resource "google_kms_crypto_key_iam_member" "sops_ci_sa" {
  crypto_key_id = google_kms_crypto_key.sops.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:terraform-ci@${var.project_id}.iam.gserviceaccount.com"
}

# 管理者ユーザーがローカルで暗号化/編集するための権限
resource "google_kms_crypto_key_iam_member" "sops_admin" {
  crypto_key_id = google_kms_crypto_key.sops.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "user:${var.admin_user_email}"
}
```

`var.admin_user_email` は `terraform/gcp/variables.tf` に追加 (`default = "takayo.uenter36@gmail.com"`)。

#### `terraform/gcp/secrets.tf` (新規)

```hcl
# CI で復号された yaml を読み込む。enc.yaml が未配置の初回 apply 時は
# .decrypted/<name>.yaml も生成されないため、fileexists() で skip する。
# これにより「KMS key を先に作る → ユーザーが手元で encrypt → enc.yaml を
# commit → 次の apply で Secret Manager に投入」という安全な順序を保つ。
locals {
  decrypted_file = "${path.module}/.decrypted/gemini-api-key.yaml"
  decrypted      = fileexists(local.decrypted_file) ? yamldecode(file(local.decrypted_file)) : {}
}

resource "google_secret_manager_secret" "gemini_api_key" {
  count     = lookup(local.decrypted, "gemini_api_key", "") != "" ? 1 : 0
  secret_id = "gemini-api-key"

  replication {
    auto {}
  }

  depends_on = [google_project_service.app_required]
}

resource "google_secret_manager_secret_version" "gemini_api_key" {
  count       = lookup(local.decrypted, "gemini_api_key", "") != "" ? 1 : 0
  secret      = google_secret_manager_secret.gemini_api_key[0].id
  secret_data = local.decrypted.gemini_api_key
}
```

#### `.gitignore` 追加

```
# SOPS 復号後の一時ファイル (CI で作られ、jobs 終了時に消える)
terraform/gcp/.decrypted/

# secrets/ は暗号化済みファイルだけ git に乗せる (素の yaml は誤コミット防止)
secrets/*.yaml
!secrets/*.enc.yaml
```

#### GitHub Actions ワークフロー追記

`terraform-gcp-plan.yml` および `terraform-gcp-apply.yml` の **`terraform init` の直前** に以下のステップを追加:

```yaml
- name: Install SOPS
  uses: getsops/sops-installer@v1

- name: Decrypt secrets (skip if not yet committed)
  run: |
    mkdir -p terraform/gcp/.decrypted
    if [ -f secrets/gemini-api-key.enc.yaml ]; then
      sops decrypt secrets/gemini-api-key.enc.yaml > terraform/gcp/.decrypted/gemini-api-key.yaml
    fi
```

plan/apply ともに復号が必要 (`yamldecode(file(...))` の評価のため)。

### 運用フロー

#### 初回セットアップ (Phase 分け)

1. **KMS / SOPS スタック追加 PR**: 本 ADR の `terraform/gcp/kms.tf` / `secrets.tf` / `.sops.yaml` / `.gitignore` / GHA 復号ステップ / `cloudkms` API 有効化 を入れる
   - この時点で `secrets/gemini-api-key.enc.yaml` は **未配置**
   - apply で KMS key と `prevent_destroy` 設定が完成、Secret Manager は `count=0` で作られない
2. ローカルで暗号化:
   ```bash
   # GCP に管理者ユーザーで認証済みであること
   echo 'gemini_api_key: "AIzaSy..."' > secrets/gemini-api-key.yaml
   sops --encrypt secrets/gemini-api-key.yaml > secrets/gemini-api-key.enc.yaml
   rm secrets/gemini-api-key.yaml
   ```
3. **Cloud Functions デプロイ PR**: `secrets/gemini-api-key.enc.yaml` を commit。Cloud Functions の Terraform 定義 (env で SM 参照) も同 PR で入れる
4. apply で Secret Manager + secret version + Cloud Functions が完成

#### 値の変更 (通常運用)

```bash
sops secrets/gemini-api-key.enc.yaml
# → エディタが起動、自動的に復号した状態で開く
# → 編集 → 保存で自動的に再暗号化
git add secrets/gemini-api-key.enc.yaml
git commit -m "rotate gemini api key"
git push
```

push → PR → merge → apply で Secret Manager の新しい version が作成され、Cloud Functions は次回 cold start 時に新値を取得する。

#### シークレット追加

1. `secrets/<new-name>.enc.yaml` を SOPS で暗号化して commit
2. `terraform/gcp/secrets.tf` に同形の `locals` + `google_secret_manager_secret*` を追加
3. Cloud Functions の env block に SM 参照を追加

## Consequences

- "git push = インフラ実態に反映" 原則を保てる (シークレット込み)
- 長期鍵を GitHub Secrets に置く必要がない (CI 認証は既存 WIF を再利用)
- 鍵紛失リスクは KMS 側で吸収。ユーザー本人 + CI SA 両方が encrypter/decrypter
- KMS key は `prevent_destroy = true` 必須。誤削除で過去の暗号化ファイルが全件復号不能になる
- 鍵 rotation は設定しない (古い key version で暗号化済みの enc.yaml の復号は技術的に可能だが、運用が煩雑になるため。漏洩時は手動で全シークレット再暗号化する方針)
- Phase 分け運用 (KMS / SOPS スタック追加 PR → ローカル暗号化 → Cloud Functions デプロイ PR) が必要。`secrets.tf` の `count` 条件と `fileexists()` を組み合わせて、シークレット未配置でも `terraform plan` が通る構造にしている
- `.sops.yaml` には KMS key の **resource path** が書かれるが秘密値は含まない。git commit OK
- 一切の plain text シークレットは git にも GitHub Actions の output / log にも残らない (decrypt 後の `.decrypted/` は jobs 終了で消える、GHA log への直接出力もしない)
- 「なぜ Secret Manager 直接投入 (方式 A) ではなく SOPS 経由か」の議論はこの ADR で完結。再評価する場合は新 ADR を起こす
