# Looked up, not created: the resource group is provisioned once by
# bootstrap/setup.sh and never destroyed. Role assignments scoped to it
# (the CI/CD identity's Contributor etc.) are children of this scope —
# if Terraform owned and destroyed the group itself, those roles would
# be wiped on every Destroy, same as they would be for rg-terraform-state
# if that one were Terraform-managed. Treating the group as unmanaged
# keeps Destroy's blast radius to "everything inside it" only.
data "azurerm_resource_group" "main" {
  name = var.resource_group_name
}

module "acr" {
  source              = "./modules/acr"
  name                = var.acr_name
  resource_group_name = data.azurerm_resource_group.main.name
  location            = data.azurerm_resource_group.main.location
}

module "container_app" {
  source              = "./modules/container-app"
  resource_group_name = data.azurerm_resource_group.main.name
  location            = data.azurerm_resource_group.main.location
  container_app_name  = var.container_app_name
  acr_login_server    = module.acr.login_server
  acr_id              = module.acr.id
  image_tag           = var.image_tag
}
