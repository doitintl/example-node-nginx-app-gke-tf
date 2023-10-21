variable "project_id" {}
variable "env" {}

variable "location" {
    type = string
}

variable "repository_id" {
    type = string
}

variable "description" {
    type = string
    default = "Docker artifact registry"
}

variable "format" {
    type = string
    default = "DOCKER"
}
