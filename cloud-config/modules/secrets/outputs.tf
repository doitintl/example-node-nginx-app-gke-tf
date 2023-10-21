output "id" {
    value = values(google_secret_manager_secret.app).*.id
}

output "name" {
    value = values(google_secret_manager_secret.app).*.name
}
