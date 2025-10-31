# BrainiacOps

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Renovate](https://img.shields.io/badge/renovate-enabled-brightgreen.svg)](https://renovatebot.com)

> GitOps home lab running Argo CD, media automation, and self-hosted infrastructure.

---

## Overview

BrainiacOps is the single source of truth for my homelab Kubernetes cluster. Argo CD continuously reconciles everything in this repository—ingress, storage, media workloads, monitoring, and supporting services—using a Kustomize-first app-of-apps layout. Renovate and GitHub Actions keep dependencies fresh while pre-commit hooks guard the supply chain.

## Key Capabilities

- **GitOps-first operations**: Argo CD bootstraps itself, then syncs infrastructure, media apps, and game servers from declarative manifests.
- **Opinionated platform services**: Traefik, MetalLB, Tailscale, cert-manager, Portainer, Longhorn, and Intel GPU plugins are managed as first-class infrastructure.
- **Media & automation stack**: Jellyfin, Radarr/Sonarr, Plex, Transmission (with VPN), Handbrake, Mealie, and more run under `kubernetes/apps`.
- **Observability**: Kube Prometheus Stack, Gatus, metrics-server, and supporting secrets live in `kubernetes/infrastructure/monitoring`.
- **Security guardrails**: Bitwarden Secrets Operator injects credentials, pre-commit TruffleHog scans staged YAML/ENV/JSON, and Renovate patches stay grouped for fast reviews.
- **Testing sandboxes**: `kubernetes/testing` holds throwaway workloads, benchmarks, and repro environments without polluting prod namespaces.

## Repository Layout

- `kubernetes/bootstrap/` – Minimal manifests to install Argo CD and seed the app-of-apps controller.
- `kubernetes/infrastructure/` – Cluster services (ingress, storage, monitoring, secrets, Renovate, tooling).
- `kubernetes/apps/` – User-facing workloads. `default/` is the primary namespace; `external/` tracks remotely managed installs; `_shared/` holds common Kustomize pieces.
- `kubernetes/games/` – Game server workloads such as Minecraft.
- `kubernetes/storage/` – PersistentVolume definitions and storage glue for the media stack.
- `kubernetes/testing/` – Temporary experiments, benchmark jobs, and validation manifests.
- `.github/workflows/` – CI pipelines (currently kubeconform schema validation).
- `.githooks/` – Custom Git hooks (TruffleHog scan and YAML hygiene).
- `renovate.json5` – Renovate configuration, including patch-only grouping rules and custom managers for YAML updates.

## GitOps Bootstrap

Spin up a new cluster with the Argo CD app-of-apps flow:

```bash
# 1. Create the Argo CD namespace
kubectl apply -f kubernetes/bootstrap/argocd-namespace.yaml

# 2. Install Argo CD from the vendored manifest
kubectl apply -k kubernetes/bootstrap/argocd-install

# 3. Seed the infrastructure app-of-apps once Argo CD is healthy
kubectl apply -f kubernetes/bootstrap/infrastructure-app.yaml

# 4. (Optional) Enable application trees
kubectl apply -f kubernetes/bootstrap/apps-app.yaml
kubectl apply -f kubernetes/bootstrap/apps-external-app.yaml
```

Argo CD will take over reconciliation from there, applying infrastructure first and then layering applications.

## Automation & Quality Gates

- **GitHub Actions**: `.github/workflows/kubeconform.yml` validates changed Kubernetes manifests on every PR with `kubeconform`.
- **Renovate**: A self-hosted Renovate bot (deployed via `kubernetes/infrastructure/renovate`) keeps images, charts, and GitHub Actions updated. All patch bumps are grouped for quick merges; minors and majors ship individually.
- **Pre-commit hooks**: `.githooks/pre-commit` runs TruffleHog inside Docker against staged YAML/ENV/JSON and fixes missing trailing newlines to keep yamllint happy.
- **Linting**: `.yamllint.yaml` customizes yamllint for long lines, GitHub Actions keys, and templated files.

## Local Workflow

1. Enable repo-provided hooks so secret scanning runs before each commit:
   ```bash
   git config core.hooksPath .githooks
   ```
2. Optional checks before pushing:
   ```bash
   # Skip CRDs while validating manifests against upstream schemas
   kubeconform -strict -ignore-missing-schemas $(git ls-files 'kubernetes/**/*.ya?ml')
   ```
3. Need to bypass TruffleHog for a specific commit? Export `SKIP_TRUFFLEHOG=1` (use sparingly).

## Secrets & Sensitive Data

- Bitwarden Secrets Operator (under `kubernetes/infrastructure/bitwarden`) syncs credentials into namespaces.
- Renovate’s GitHub token is provisioned via the operator—see `kubernetes/infrastructure/renovate/README.md` for the Bitwarden workflow and required fine-grained PAT scopes.
- Additional secrets are managed through the same pattern so the Git repo stays scrubbed.

## Contributing

- Favor Kustomize overlays and `_shared` bases to avoid copy/paste drift.
- Keep manifests schema-valid; when adding new CRDs, update kubeconform ignores if necessary.
- Document notable app folders with a short `README.md` when extra setup is required.

## License

MIT – see `LICENSE`.
