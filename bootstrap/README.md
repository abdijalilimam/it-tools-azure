# Bootstrap

Run once, before any `terraform apply`, to create the resources Terraform itself depends on (state backend + CI/CD identity):

```bash
chmod +x bootstrap/setup.sh
./bootstrap/setup.sh
```

Creates:
- Resource group for the project
- Storage account + container for Terraform remote state
- An Azure AD app registration with a federated credential, so GitHub Actions can authenticate via OIDC — no stored secrets

Copy the printed output into your local `azure-notes.md` (gitignored).
