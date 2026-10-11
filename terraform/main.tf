resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
}

module "acr" {
  source              = "./modules/acr"
  name                = var.acr_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
}

module "container_app" {
  source              = "./modules/container-app"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  container_app_name  = var.container_app_name
  acr_login_server    = module.acr.login_server
  acr_id              = module.acr.id
  image_tag           = var.image_tag
}
