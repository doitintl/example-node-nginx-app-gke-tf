output "id" {
    value = values(google_secret_manager_secret.cmdb_app).*.id
}

output "name" {
    value = values(google_secret_manager_secret.cmdb_app).*.name
}
