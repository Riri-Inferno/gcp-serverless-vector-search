terraform {
  backend "gcs" {
    bucket       = "riri-vector-lab-2026-tfstate"
    prefix       = "gcp"
    use_lockfile = true
  }
}
