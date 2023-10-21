variable "project_id" {}
variable "env" {}

variable "label" {
    type = string
    default = "app"
}

variable "secret_ids_list" {
    type = set(string)
}
