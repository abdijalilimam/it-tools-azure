#!/usr/bin/env bash
set -euo pipefail

# Bootstraps the Azure resources needed before Terraform can run:
# two resource groups (app + state), remote state storage, the GitHub
# OIDC trust, and the role assignments CI/CD needs. Run once, by hand,
# with your own (Owner-level) login — never from GitHub Actions, and
# never re-run against a subscription that already has these resources
# (it creates a NEW storage account and app registration every time,
# which orphans Terraform state rather than repairing anything).
#
# The app resource group (rg-it-tools-azure) is created here and never
# destroyed — terraform/main.tf looks it up with a data source instead
# of managing it as a resource. Apply/Destroy only ever create or
# remove what's INSIDE the group. That's what keeps the role
# assignments below alive across every Destroy: a role assignment is a
# child of the scope it's attached to, so as long as the group itself
# is never deleted, these never need to be re-granted. (If a role ever
# does go missing — say the group was deleted out-of-band — use
# repair-roles.sh to re-grant it without re-running this whole script.)
#
# The state resource group is kept separate from the app resource
# group for the same reason it's always been separate: Terraform's own
# backend access shouldn't live inside the thing Terraform manages.

RG="rg-it-tools-azure"
STATE_RG="rg-terraform-state"
LOCATION="eastus"
STORAGE_ACCOUNT="stittoolstfstate$RANDOM"
CONTAINER="tfstate"
APP_NAME="it-tools-azure-github-oidc"
REPO="abdijalilimam/it-tools-azure"
BRANCH="main"

# 1. Resource groups — app and state, kept separate. The app RG is
#    created here once and is never destroyed again; only its contents
#    are created/destroyed by Terraform.
az group create --name "$RG" --location "$LOCATION"
az group create --name "$STATE_RG" --location "$LOCATION"

# 2. Storage account + container for Terraform remote state
#    (lives in the state RG, never the app RG)
az storage account create \
  --name "$STORAGE_ACCOUNT" \
  --resource-group "$STATE_RG" \
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

# 4. Roles scoped to the app resource group only — not subscription-wide.
#    Contributor manages the resources themselves (ACR, Container Apps,
#    etc.); Role Based Access Control Administrator lets Terraform
#    create the AcrPull role assignment for the managed identity;
#    Managed Identity Operator lets the deploy step attach that
#    identity to the Container App. These survive every future Destroy
#    because the resource group they're scoped to is never deleted.
for ROLE in "Contributor" "Role Based Access Control Administrator" "Managed Identity Operator"; do
  az role assignment create \
    --assignee "$APP_ID" \
    --role "$ROLE" \
    --scope "/subscriptions/$SUB_ID/resourceGroups/$RG"
done

# 5. Role on the state resource group — lets Terraform read/write
#    remote state via Azure AD auth instead of a shared storage account
#    key.
az role assignment create \
  --assignee "$APP_ID" \
  --role "Storage Blob Data Contributor" \
  --scope "/subscriptions/$SUB_ID/resourceGroups/$STATE_RG"

# 6. Federated credentials — one per distinct GitHub Actions subject
#    claim shape. A job that uses `environment:` for a manual-approval
#    gate produces a different subject than a plain branch-triggered
#    job, so each shape needs its own credential.
declare -A SUBJECTS=(
  ["github-actions-$BRANCH"]="repo:$REPO:ref:refs/heads/$BRANCH"
  ["github-actions-env-azure-infra"]="repo:$REPO:environment:azure-infra"
  ["github-actions-env-azure-destroy"]="repo:$REPO:environment:azure-destroy"
)

for NAME in "${!SUBJECTS[@]}"; do
  az ad app federated-credential create \
    --id "$APP_ID" \
    --parameters "{
      \"name\": \"$NAME\",
      \"issuer\": \"https://token.actions.githubusercontent.com\",
      \"subject\": \"${SUBJECTS[$NAME]}\",
      \"audiences\": [\"api://AzureADTokenExchange\"]
    }"
done

echo "RG=$RG"
echo "STATE_RG=$STATE_RG"
echo "STORAGE_ACCOUNT=$STORAGE_ACCOUNT"
echo "CONTAINER=$CONTAINER"
echo "APP_ID=$APP_ID"
echo "SUB_ID=$SUB_ID"
