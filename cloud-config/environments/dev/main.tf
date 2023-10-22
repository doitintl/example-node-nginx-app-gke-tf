locals {
  env                    = "dev"
  cluster_name           = "safer-cluster"
  network_name           = "safer-cluster-network-${local.env}"
  subnet_name            = "safer-cluster-subnet"
  master_auth_subnetwork = "safer-cluster-master-subnet"
  pods_range_name        = "ip-range-pods-${local.env}"
  svc_range_name         = "ip-range-svc-${local.env}"
  subnet_names           = [for subnet_self_link in module.gcp_network.subnets_self_links : split("/", subnet_self_link)[length(split("/", subnet_self_link)) - 1]]
  node_count             = 1
}

provider "google" {
  project = var.project_id
}

# TODO: https://registry.terraform.io/modules/terraform-google-modules/project-factory/google/latest
# - create service project, link to shared vpc host project, enable APIs

# create secrets (without versions for security purpose)
module "secrets" {
  source          = "../../modules/secrets"
  project_id      = var.project_id
  env             = local.env
  secret_ids_list = var.secret_ids
}

# google safer cluster module
data "google_client_config" "default" {}

provider "kubernetes" {
  host                   = "https://${module.gke.endpoint}"
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(module.gke.ca_certificate)
}

module "gke" {
  source = "terraform-google-modules/kubernetes-engine/google//modules/safer-cluster"
  # version                    = "28.0.0"
  project_id                 = var.project_id
  name                       = "${local.cluster_name}-${local.env}"
  regional                   = true
  region                     = var.region
  network                    = module.gcp_network.network_name
  subnetwork                 = local.subnet_names[index(module.gcp_network.subnets_names, local.subnet_name)]
  initial_node_count         = local.node_count
  ip_range_pods              = local.pods_range_name
  ip_range_services          = local.svc_range_name
  master_ipv4_cidr_block     = "172.16.0.0/28"
  add_cluster_firewall_rules = true
  firewall_inbound_ports     = ["9443", "15017"]
  kubernetes_version         = "latest"
  release_channel            = "UNSPECIFIED"
  gateway_api_channel        = "CHANNEL_STANDARD"
  registry_project_ids       = [var.registry_project_id]
  grant_registry_access      = true
  #enable_private_endpoint    = false

  master_authorized_networks = [
    {
      cidr_block   = var.master_auth_cidrs
      display_name = "VPC"
    },
  ]

  notification_config_topic = google_pubsub_topic.updates.id
}

resource "google_pubsub_topic" "updates" {
  name    = "cluster-updates-${local.env}"
  project = var.project_id
}

# nat gateway if nodes/bastion need to reach public internet
module "cloud-nat" {
  source     = "terraform-google-modules/cloud-nat/google"
  version    = "~> 1.2"
  project_id = var.project_id
  region     = var.region
  network    = module.gcp_network.network_name
  router     = google_compute_router.router.name
}

# bastion host to access cluster
module "iap_bastion" {
  source = "terraform-google-modules/bastion-host/google"

  project = var.project_id
  zone    = var.zone
  network = module.gcp_network.network_self_link
  subnet  = module.gcp_network.subnets_self_links[0]
  members = var.bastion_users
}
