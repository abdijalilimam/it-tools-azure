output "container_app_url" {
  value = module.container_app.fqdn
}

output "acr_login_server" {
  value = module.acr.login_server
}
