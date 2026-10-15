#!/usr/bin/env bash
set -uo pipefail

# Re-grants the CI/CD identity's resource-group-scoped roles.
#
# Under normal operation this script should never be needed: the app
# resource group is created once by setup.sh and looked up (not
# managed) by Terraform, so Destroy never deletes the group itself —
# only what's inside it — and these role assignments, being children
# of the group, survive every Destroy along with it.
#
# It exists only to repair things if the group or its role
# assignments are ever removed out-of-band (manually deleted, or
# recovering from before this project stopped letting Terraform own
# the group's lifecycle). Safe to re-run any time: if a role is
# already assigned, Azure returns an error for that one line only, and
# the loop continues.

APP_ID="3bfab09a-67c7-4443-9f4d-f4be699e6b0c"
RG="rg-it-tools-azure"
SUB_ID=$(az account show --query id -o tsv)

for ROLE in "Contributor" "Role Based Access Control Administrator" "Managed Identity Operator"; do
  echo "Granting $ROLE on $RG..."
  az role assignment create \
    --assignee "$APP_ID" \
    --role "$ROLE" \
    --scope "/subscriptions/$SUB_ID/resourceGroups/$RG" \
    || echo "  (already assigned, or RG doesn't exist yet — run setup.sh first if so)"
done

echo "Done."
