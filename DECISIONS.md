# Decisions

Notes on why this is built the way it is, same spirit as the reasoning in the AWS version's README, just for the Azure side.

## Container Apps over AKS or a VM

I didn't go with AKS even though it would've looked more impressive on paper — it's days of extra work for a project that's supposed to demonstrate the same concepts as the ECS version, not become a second full-time job. A VM was never on the table either, same reason as the AWS repo: I don't want to spend my time patching an OS instead of shipping the app. Container Apps is the actual equivalent of Fargate here — managed, no servers to think about, and it comes with HTTPS ingress and autoscaling built in instead of me having to wire those up separately.

## Dropping the ALB and ACM equivalents

On the AWS side I needed an ALB and ACM because ECS doesn't give you ingress or TLS for free. Container Apps does, natively, so there was nothing to replace them with — I just didn't build them. Less code, same outcome.

## Skipping a custom VNet for v1

The AWS version has a full VPC with NAT and private subnets. I'm leaving that out of the first version here on purpose, not because it's not worth doing — it's a legit next step if someone asks "how would you lock this down further," but building it right now would eat time I don't have before this needs to be ready to talk about.

## Azure Storage instead of S3 for remote state

Same reason as the AWS repo's S3 backend: GitHub Actions runs on a fresh machine every time, so without a shared state file it has no memory of what it already created. Azure Storage + a blob container does the same job S3 did.

## OIDC with a federated credential instead of a stored secret

Same principle as the IAM/OIDC setup on the AWS side — GitHub Actions authenticates to Azure using a federated credential tied to this specific repo and branch, not a stored client secret sitting in GitHub Secrets. Nothing long-lived to leak.

## Scoped the service principal to the resource group, not the subscription

The app registration only has Contributor on `rg-it-tools-azure`, not the whole subscription. If the credential ever leaked, the blast radius is one resource group, not everything in my Azure account.

## Managed identity + AcrPull instead of ACR admin credentials

I turned off admin access on the registry and gave the Container App a system-assigned identity with just the AcrPull role instead. Slower to set up than flipping on admin credentials, but it's the same least-privilege instinct as the IAM policies on the ECS side, so worth the extra few minutes.

## Tagging images with the git SHA, not `latest`

Wanted every image to be traceable back to the exact commit that built it, and `latest` makes that impossible to audit later. GitHub Actions will eventually generate this tag automatically from `github.sha`; for now I'm doing it by hand to get unblocked.

## Building images with ACR Tasks instead of locally

Building for `linux/amd64` on my Apple Silicon Mac meant every local build ran under emulation — slow, and it actually crashed with out-of-memory errors a couple times during the Vite build step. Switched to `az acr build`, which runs the build on Azure's own infrastructure instead of my laptop: native x86_64, no emulation tax, and it finished in under 3 minutes what was taking 17+ minutes (and failing) locally. This is also closer to how the real CI pipeline will work once GitHub Actions is wired up.

## Issues I ran into

The resource group already existed by the time I ran `terraform apply`, since I'd created it manually during the bootstrap step before Terraform knew about it. Had to `terraform import` it into state instead of letting Terraform try to create it fresh.

Building the image with `--platform linux/amd64` on an Apple Silicon Mac crashed with a JavaScript heap out-of-memory error partway through the Vite build. Fixed the immediate crash with `NODE_OPTIONS=--max-old-space-size=4096`, but it was still painfully slow under emulation, which is what led to switching the build to ACR Tasks instead.

First time creating a Container App on this subscription, Terraform failed with `MissingSubscriptionRegistration` for the `Microsoft.App` namespace — Azure resource providers have to be registered on a subscription before first use. Fixed with `az provider register --namespace Microsoft.App`, though it took a while to actually finish since registration happens per-region and the top-level status doesn't flip to "Registered" until every region is done — worth just retrying the apply once your target region's registration completes rather than waiting on the full status.
