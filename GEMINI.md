# Gemini Code Assistant Context

This document provides context for the Gemini Code Assistant to understand the `BrainiacOps` project.

## Project Overview

This is a GitOps repository for a home lab Kubernetes cluster. It uses a declarative, "app-of-apps" approach with Argo CD to manage the entire stack, from the underlying OS to a comprehensive suite of self-hosted applications.

- **Orchestration**: Kubernetes
- **GitOps Controller**: Argo CD
- **Operating System**: Talos
- **Persistent Storage**: Longhorn
- **Ingress**: Traefik
- **Dependency Automation**: Renovate
- **Secrets Management**: Bitwarden (via Bitwarden Secrets Operator)
- **CI/CD**: GitHub Actions
- **Tool Version Management**: mise + aqua

The repository is structured into several key directories:

- `kubernetes/bootstrap`: Contains the initial Argo CD manifests to kickstart the GitOps process.
- `kubernetes/infrastructure`: Manages all cluster-level services like storage (Longhorn), networking (Traefik, MetalLB), and monitoring.
- `kubernetes/apps`: Contains all user-facing applications, primarily in the `default` namespace.
- `kubernetes/games`: Holds configurations for game servers.
- `talos`: Defines the immutable OS configuration for the Kubernetes nodes.

## Building and Running

This is a GitOps repository, so there is no traditional "build" process. Changes are applied by pushing commits to the main branch of this repository. Argo CD monitors the repository and automatically syncs any changes to the Kubernetes cluster.

A GitHub Actions workflow (`.github/workflows/kubeconform.yml`) validates all Kubernetes manifests against their schemas using `kubeconform` on every push and pull request.

## Development Conventions

- **Configuration Management**: Kubernetes manifests are managed using Kustomize. The "app-of-apps" pattern is used extensively, with parent Argo CD `Application` resources that recursively manage child applications.
- **Dependency Updates**: Renovate (`renovate.json5`) is configured to automatically create pull requests for updates to:
    - Docker image tags in Kubernetes manifests.
    - Helm chart versions in Argo CD Applications.
    - CLI tool versions in `.mise.toml`.
- **Tooling**: The `.mise.toml` file defines the exact versions of the command-line tools required for this project. These tools are installed and managed via `mise` and `aqua`.
- **Secrets**: Secrets are not stored in the repository. They are managed by the Bitwarden Secrets Operator, which injects them into the cluster at runtime.
- **Shared Resources**: The `kubernetes/apps/default/_shared` directory contains an Argo CD application for managing resources that are shared across multiple applications in the `default` namespace.
- **Sync Waves**: Argo CD sync waves are used in application annotations (`argocd.argoproj.io/sync-wave`) to control the deployment order of resources. For example, infrastructure components like Longhorn have a lower sync wave (`"0"`) to ensure they are deployed before applications that depend on them.

## Current Status (as of 2025-11-21)

The user is in the process of upgrading the Talos cluster.

1.  **Problem:** An attempt to upgrade the `brainiac-01` control plane node (10.0.0.35) was blocked because it would cause a loss of quorum.
2.  **Solution:** A new control plane node, `brainiac-02` (10.0.0.36), is being added to the cluster to establish quorum before proceeding with the upgrade.
3.  **Next Steps:**
    *   Apply the machine configuration for `brainiac-02` using `talosctl apply-config`. A `talos/clusterconfig/talos-rao-brainiac-02.yaml` file already exists.
    *   Once the new node is online and the cluster is healthy, proceed with the upgrade of `brainiac-01` using `talosctl upgrade`.
4.  **Note:** There is a recurring `x509: certificate signed by unknown authority` error when connecting to `brainiac-01`. The `--insecure` flag is being used as a temporary workaround.

A `talos/README.md` file has been created to document these steps.
