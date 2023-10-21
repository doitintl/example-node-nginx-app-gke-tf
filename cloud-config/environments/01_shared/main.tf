locals {
  env = "shared"
}

provider "google" {
  project = var.project_id
}

# TODO: https://registry.terraform.io/modules/terraform-google-modules/project-factory/google/latest
# - create service project, link to shared vpc host project, enable APIs

module "registry" {
  source        = "../../modules/registry"
  project_id    = var.project_id
  env           = local.env
  location      = var.region
  repository_id = var.repository_id
}
