locals {
  env = "shared"
}

provider "google" {
  project = var.project_id
}

module "registry" {
  source        = "../../modules/registry"
  project_id    = var.project_id
  env           = local.env
  location      = var.region
  repository_id = var.repository_id
}
