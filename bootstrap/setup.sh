#!/usr/bin/env bash
set -euo pipefail

# Bootstraps the Azure resources needed before Terraform can run:
# resource group, remote state storage, and the GitHub OIDC trust.

RG="rg-it-tools-azure"
LOCATION="eastus"
STORAGE_ACCOUNT="stittoolstfstate$RANDOM"
CONTAINER="tfstate"
APP_NAME="it-tools-azure-gha"
REPO="abdijalilimam/it-tools-azure"
BRANCH="main"

# 1. Resource group
az group create --name "$RG" --location "$LOCATION"

# 2. Storage account + container for Terraform remote state
az storage account create \
  --name "$STORAGE_ACCOUNT" \
  --resource-group "$RG" \
  --location "$LOCATION" \
  --sku Standard_LRS

az storage container create \
  --name "$CONTAINER" \
  --account-name "$STORAGE_ACCOUNT" \
  --auth-mode login

# 3. App registration for GitHub OIDC
APP_ID=$(az ad app create --display-name "$APP_NAME" --query appId -o tsv)
az ad sp create --id "$APP_ID"

SUB_ID=$(az account show --query id -o tsv)

# 4. Scoped Contributor role — resource group only, not subscription-wide
az role assignment create \
  --assignee "$APP_ID" \
  --role Contributor \
  --scope "/subscriptions/$SUB_ID/resourceGroups/$RG"

# 5. Federated credential — trusts GitHub Actions on $BRANCH only
az ad app federated-credential create \
  --id "$APP_ID" \
  --parameters "{
    \"name\": \"github-actions-$BRANCH\",
    \"issuer\": \"https://token.actions.githubusercontent.com\",
    \"subject\": \"repo:$REPO:ref:refs/heads/$BRANCH\",
    \"audiences\": [\"api://AzureADTokenExchange\"]
  }"

echo "RG=$RG"
echo "STORAGE_ACCOUNT=$STORAGE_ACCOUNT"
echo "CONTAINER=$CONTAINER"
echo "APP_ID=$APP_ID"
echo "SUB_ID=$SUB_ID"
