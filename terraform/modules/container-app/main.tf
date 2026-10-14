resource "azurerm_log_analytics_workspace" "logs" {
  name                = "law-${var.container_app_name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

resource "azurerm_container_app_environment" "environment" {
  name                       = "cae-${var.container_app_name}"
  location                   = var.location
  resource_group_name        = var.resource_group_name
  log_analytics_workspace_id = azurerm_log_analytics_workspace.logs.id
}

resource "azurerm_user_assigned_identity" "acr_pull" {
  name                = "id-${var.container_app_name}-acrpull"
  resource_group_name = var.resource_group_name
  location            = var.location
}

resource "azurerm_role_assignment" "acr_pull" {
  scope                = var.acr_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.acr_pull.principal_id
}

resource "azurerm_container_app" "app" {
  name                         = var.container_app_name
  resource_group_name          = var.resource_group_name
  container_app_environment_id = azurerm_container_app_environment.environment.id
  revision_mode                = "Single"
  workload_profile_name        = "Consumption"

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.acr_pull.id]
  }

  template {
    container {
      name   = var.container_app_name
      image  = "mcr.microsoft.com/azuredocs/containerapps-helloworld@sha256:e9b3e7c34664c7cffd7144864b0e4eec369bfde80068f9095dc63b37058bec48"      
      cpu    = 0.5
      memory = "1Gi"
    }
  }

  ingress {
    external_enabled = true
    target_port       = 80
    transport         = "auto"

    traffic_weight {
      latest_revision = true
      percentage       = 100
    }
  }

  registry {
    server   = var.acr_login_server
    identity = azurerm_user_assigned_identity.acr_pull.id
  }

  lifecycle {
    ignore_changes = [template[0].container[0].image]
  }

  depends_on = [azurerm_role_assignment.acr_pull]
}
