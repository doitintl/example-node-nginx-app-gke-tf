terraform {
  backend "gcs" {
    bucket = "mike-test-cmdb-gke-tfstate"
    prefix = "env/dev"
  }
}