# it-tools-azure

A handy collection of developer tools ([it-tools](https://github.com/CorentinTh/it-tools)), deployed as a containerized web app on Azure, with infrastructure managed by Terraform and deployments handled by GitHub Actions — authenticated entirely through OpenID Connect, with no long-lived cloud credentials stored anywhere.

**Live URL:** https://azure.abdijalil.dev

## Architecture

```
GitHub repo (main)
   │ push
   ▼
GitHub Actions ── OIDC token exchange ──► Azure AD App Registration
   │                                        (it-tools-azure-github-oidc)
   │
   ├─ Build:   az acr build → pushes image → az rest PUT → updates the
   │            running Container App's image, in place
   │
   └─ Apply / Destroy: terraform plan/apply/destroy against
                        rg-it-tools-azure, state stored in
                        rg-terraform-state

rg-it-tools-azure
   └─ Container Apps Environment (cae-it-tools)
        └─ Container App (it-tools)
              ├─ pulls its image via a dedicated User-Assigned
              │  Managed Identity (id-it-tools-acrpull), scoped
              │  to AcrPull only — nothing broader
              ├─ terminates HTTPS itself (built-in ingress +
              │  managed certificate), no separate load balancer
              └─ sends logs to a Log Analytics workspace
   └─ Container Registry (ittoolsazure)

rg-terraform-state
   └─ Storage Account — Terraform remote state (blob + Azure AD
      auth, no shared access keys), isolated from the app resource
      group so a full Destroy never breaks the backend itself

DNS (external): azure.abdijalil.dev → CNAME + TXT records →
                Container App's managed TLS certificate
```

## Resources

| Resource | Name | Purpose |
|---|---|---|
| Resource Group | `rg-it-tools-azure` | Holds all app infrastructure — fully managed (created and destroyed) by Terraform |
| Resource Group | `rg-terraform-state` | Holds the Terraform backend only; created once via `bootstrap/`, never touched by Apply/Destroy |
| Storage Account | `stittoolstfstate*` | Terraform remote state, blob container `tfstate`, Azure AD auth (no account keys) |
| Container Registry | `ittoolsazure` | Stores built container images |
| Container Apps Environment | `cae-it-tools` | Hosting environment for the Container App; wraps Log Analytics, networking, and scaling |
| Container App | `it-tools` | The running application — autoscales 0–10 replicas, 0.5 vCPU / 1 GiB per replica |
| Log Analytics Workspace | `law-it-tools` | Collects Container App logs |
| User-Assigned Managed Identity | `id-it-tools-acrpull` | The *only* identity the running app uses — granted `AcrPull` on the registry and nothing else |
| Azure AD App Registration | `it-tools-azure-github-oidc` | The identity GitHub Actions authenticates as, via federated OIDC credentials (one per workflow trigger shape) — no client secret exists |

## CI/CD

Three independent GitHub Actions workflows, each authenticating via its own OIDC federated credential:

- **Build** — triggers on push to `main` (ignoring `terraform/**`). Builds the image with `az acr build`, then updates the live Container App's image directly through the Container Apps REST API.
- **Apply** — triggers on push to `terraform/**`, or manually. Runs `terraform plan` / `apply`. Gated behind a GitHub Environment (`azure-infra`) requiring manual approval before anything touches real infrastructure.
- **Destroy** — manual only, requires typing `destroy` as confirmation. Gated behind its own GitHub Environment (`azure-destroy`) with a separate manual approval step.

No workflow stores a client secret, access key, or connection string. Every one exchanges a short-lived GitHub-issued OIDC token for an Azure AD token at run time.

## Identity & access design

The GitHub Actions identity and the app's runtime identity are deliberately separate and scoped differently:

- **CI/CD identity** (`it-tools-azure-github-oidc`) holds `Contributor`, `Role Based Access Control Administrator`, and `Managed Identity Operator` — all scoped to `rg-it-tools-azure` only, never the subscription. It also holds `Storage Blob Data Contributor` on `rg-terraform-state`, for reading/writing Terraform state.
- **Runtime identity** (`id-it-tools-acrpull`) holds only `AcrPull` on the container registry. It cannot touch any other resource, and it's never used by anything except the running Container App pulling its own image.

This means a compromised CI/CD token can manage this one resource group's infrastructure — not the subscription — and a compromised running container can pull images and nothing else.

## Terraform layout

```
terraform/
├── main.tf          # resource group, wires up the two modules below
├── provider.tf       # azurerm provider + remote backend (AAD auth)
├── variables.tf
├── outputs.tf
└── modules/
    ├── acr/              # Container Registry
    └── container-app/    # Log Analytics, Container Apps Environment,
                           # Managed Identity, Container App

bootstrap/
├── setup.sh         # one-time, run by hand — never in CI. Creates
│                    # both resource groups, the state storage account,
│                    # the app registration, its federated credentials,
│                    # and the CI/CD identity's role assignments.
└── README.md
```

## Design notes worth knowing

- **The Container App's image is intentionally not fully Terraform-owned.** Terraform sets the initial image on creation, then `lifecycle { ignore_changes }` lets Build's direct REST API update take over day-to-day deploys — so a new image doesn't require a full `terraform apply` on every push.
- **Terraform state lives in its own resource group**, separate from the app's. Destroy tears down `rg-it-tools-azure` completely on every run; keeping state outside it means a full teardown never breaks Terraform's own backend access or the CI/CD identity's remaining permissions.
- **Container Apps' built-in ingress and managed certificate replace what would otherwise be a separate load balancer, public IP, and certificate resource** — one managed resource instead of several.
- **The storage account backend uses Azure AD auth, not a shared access key** — consistent with the OIDC-first, no-stored-secrets approach used everywhere else in this project.