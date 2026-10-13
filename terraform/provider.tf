terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.90"
    }
  }

  backend "azurerm" {
    resource_group_name  = "rg-it-tools-azure"
    storage_account_name = "stittoolstfstate29134"
    container_name       = "tfstate"
    key                  = "it-tools-azure.tfstate"
    use_azuread_auth     = true
  }
}

provider "azurerm" {
  features {}
}