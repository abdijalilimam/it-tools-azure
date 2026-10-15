# Bootstrap

Run once, ever, before any `terraform apply` — never from CI, never re-run against a subscription that's already been bootstrapped:

```bash
chmod +x bootstrap/setup.sh
./bootstrap/setup.sh
```

Creates:
- Both resource groups (`rg-it-tools-azure` for the app, `rg-terraform-state` for the backend)
- Storage account + container for Terraform remote state
- An Azure AD app registration with federated credentials (one per GitHub Actions trigger shape), so GitHub Actions can authenticate via OIDC — no stored secrets
- The CI/CD identity's role assignments, scoped to each resource group

Copy the printed output into your local `azure-notes.md` (gitignored).

**Don't re-run `setup.sh` to "fix" anything.** It generates a new random storage account name and a new app registration every time, so running it again doesn't repair existing infrastructure — it orphans your Terraform state in a second, empty storage account and can leave a duplicate app registration behind.

**Why re-running shouldn't be necessary anyway:** `terraform/main.tf` looks up `rg-it-tools-azure` with a `data` source instead of creating it as a managed resource. Apply and Destroy only ever touch what's *inside* the group — the group itself is created once, here, and never torn down. Since a role assignment is a child of the scope it's attached to, the roles this script grants survive every future Destroy for free; there's no `az group create` / `terraform import` / re-grant dance to repeat.

If a role assignment ever does go missing — e.g. the group was deleted out-of-band, or you're recovering from before this project looked up the group instead of managing it — use `repair-roles.sh` to re-grant it without touching anything else:

```bash
./bootstrap/repair-roles.sh
```
