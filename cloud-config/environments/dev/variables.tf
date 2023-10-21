variable "project_id" {
  type = string
}

variable "registry_project_id" {
  type = string
}

variable "region" {
  type = string
}

variable "zone" {
  type = string
}

variable "secret_ids" {
  type = set(string)
}

variable "master_auth_cidrs" {
  type = string
}

variable "bastion_users" {
  type = set(string)
}