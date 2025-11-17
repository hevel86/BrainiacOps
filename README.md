# BrainiacOps

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Renovate](https://img.shields.io/badge/renovate-enabled-brightgreen.svg)](https://renovatebot.com)
[![GitHub Actions](https://img.shields.io/github/actions/workflow/status/hevel86/BrainiacOps/kubeconform.yml?branch=main)](https://github.com/hevel86/BrainiacOps/actions/workflows/kubeconform.yml)

> GitOps home lab running Argo CD, media automation, and self-hosted infrastructure on Kubernetes.

---

## Overview

BrainiacOps is the single source of truth for my homelab Kubernetes cluster. It uses a GitOps approach with Argo CD to declaratively manage the entire stack, from infrastructure and networking to a comprehensive suite of self-hosted applications. The repository follows an "app-of-apps" pattern with Kustomize to keep configurations DRY and maintainable.

Automation is a core principle, with Renovate for dependency updates, GitHub Actions for CI/CD, and pre-commit hooks for code quality and security.

## Key Capabilities

- **GitOps-first Operations**: Argo CD bootstraps itself and then syncs all resources, including infrastructure, media applications, and game servers, from declarative manifests in this repository.
- **Opinionated Platform Services**: A robust set of platform services are managed as first-class infrastructure, including:
    - **Ingress & Networking**: Traefik, MetalLB, and Tailscale.
    - **Storage**: Longhorn for distributed block storage and CSI snapshotting.
    - **Security**: cert-manager for automated TLS certificates and Bitwarden Secrets Operator for secret injection.
    - **Hardware Acceleration**: Intel GPU device plugins for video transcoding.
    - **Management**: Portainer for a GUI-based overview of the cluster.
- **Comprehensive Media & Automation Stack**: A wide range of applications for media management and automation are deployed, including:
    - **Media Servers**: Plex, Jellyfin, Audiobookshelf.
    - **Content Automation**: Radarr, Sonarr, Bazarr, Prowlarr, Mylar3.
    - **Download Clients**: SABnzbd, Transmission (with and without VPN).
    - **Request Management**: Jellyseerr, Ombi.
    - **Utilities**: Handbrake for video transcoding, Tautulli for Plex monitoring, and more.
- **Observability**: A full monitoring stack provides insights into the cluster's health, featuring:
    - Kube Prometheus Stack for metrics and alerting.
    - Gatus for endpoint health checking.
    - metrics-server for resource metrics.
- **Security Guardrails**:
    - **Secret Management**: Bitwarden Secrets Operator injects credentials securely, keeping sensitive data out of Git.
    - **Supply Chain Security**: Pre-commit hooks with TruffleHog scan for secrets, and Renovate keeps dependencies up-to-date.
- **Testing Sandboxes**: The `kubernetes/testing` directory provides a space for temporary workloads, benchmarks, and experiments without affecting production namespaces.

## Repository Layout

- `kubernetes/bootstrap/`: Contains the minimal manifests to install Argo CD and seed the app-of-apps controller, kicking off the GitOps process.
- `kubernetes/infrastructure/`: Manages all cluster-level services, such as ingress, storage, monitoring, secrets management, and the Renovate bot itself.
- `kubernetes/apps/`: Contains all user-facing workloads. `default/` is the primary namespace for most applications, while `external/` is used for tracking remotely managed installs. `_shared/` holds common Kustomize bases to reduce duplication.
- `kubernetes/games/`: Holds configurations for game servers, such as Minecraft.
- `kubernetes/storage/`: Defines PersistentVolumes for the media stack, ensuring data persistence across pod restarts.
- `kubernetes/testing/`: A sandbox for temporary experiments, benchmark jobs, and validation manifests.
- `.github/workflows/`: Contains CI pipelines, including a `kubeconform` workflow to validate all Kubernetes manifests against their schemas.
- `.githooks/`: Includes custom Git hooks that run on pre-commit to scan for secrets with TruffleHog and enforce YAML linting rules.
- `renovate.json5`: The configuration for the Renovate bot, defining how dependencies are updated, grouped, and managed.

## GitOps Bootstrap

To bootstrap a new cluster with this GitOps setup, follow these steps:

```bash
# 1. Create the Argo CD namespace
kubectl apply -f kubernetes/bootstrap/argocd-namespace.yaml

# 2. Install Argo CD
kubectl apply -k kubernetes/bootstrap/argocd-install

# 3. Seed the infrastructure app-of-apps
kubectl apply -f kubernetes/bootstrap/infrastructure-app.yaml

# 4. (Optional) Enable application trees
kubectl apply -f kubernetes/bootstrap/apps-app.yaml
kubectl apply -f kubernetes/bootstrap/apps-external-app.yaml
```

Once these steps are completed, Argo CD will take over and continuously reconcile the state of the cluster with the manifests in this repository.

## Mise En Place Tooling

The repository ships with a [mise](https://mise.jdx.dev/) configuration (`.mise.toml`) that relies on the built-in [aquaproj/aqua](https://aquaproj.github.io/) backend for static CLI downloads—`kubectl`, `kustomize`, `helm`, `talhelper`, `talosctl`, `kubeconform`, `sops`, and `age`—plus `yamllint` via `pipx`. No manual plugin installs are required. It also wires environment variables for:

- `KUBECONFIG`: points to `~/.kube/config`.
- `TALOSCONFIG`: points to `~/.talos/config`.
- `SOPS_AGE_KEY_FILE`: defaults to `~/.config/sops/age/keys.txt`, matching the standard sops location.

1. Install mise (see the [mise docs](https://mise.jdx.dev/getting-started.html)).
2. Trust the repo configuration once so aqua-backed installs can run: `mise trust .mise.toml`.
3. Install the pinned toolchain: `mise install`.
4. Use `mise shell` or `mise exec` to run commands with the managed tools.

Tool versions in `.mise.toml` are tracked and updated automatically by Renovate via regex managers, so you’ll receive pull requests when new releases are available.

## Development Conventions

This project follows a set of conventions to maintain code quality and consistency:

- **Mise En Place**: Use `.mise.toml` to install and pin CLI dependencies (via aqua + pipx) and to provide consistent environment configuration for `KUBECONFIG`, `TALOSCONFIG`, and `SOPS_AGE_KEY_FILE`.
- **Kustomize:** Used extensively to manage Kubernetes configurations, with a preference for overlays and shared bases (`_shared` directory) to reduce duplication.
- **Pre-commit Hooks:** Before committing any changes, a pre-commit hook runs to:
    - Scan for secrets using `TruffleHog`.
    - Ensure YAML files have a trailing newline to comply with `yamllint` rules.
    To enable the hooks, run:
    ```bash
    git config core.hooksPath .githooks
    ```
- **Manifest Validation:** All Kubernetes manifests are validated against their schemas using `kubeconform`. This is enforced in the CI pipeline.
- **Linting:** `yamllint` is used to enforce YAML best practices, with a custom configuration defined in `.yamllint.yaml`.
- **Secrets Management:** Secrets are managed outside of the repository using the Bitwarden Secrets Operator.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
