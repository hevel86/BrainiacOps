# Gemini Project: BrainiacOps

## Critical Rules

**This is a GitOps repository. All changes are automatically deployed to a live Kubernetes cluster.**

- **NEVER commit secrets, passwords, API keys, or tokens** - Use Bitwarden Secrets Operator references instead
- **NEVER hardcode sensitive values** in manifests - Reference `BitwardenSecret` resources
- **Talos secrets** must only exist in `talsecret.sops.yaml` (encrypted with SOPS+age)
- When in doubt, ask before committing anything that could contain sensitive data

## Project Overview

This repository, BrainiacOps, is a GitOps-managed home lab running on a Kubernetes cluster. It uses an "app-of-apps" pattern with Argo CD to declaratively manage infrastructure, self-hosted applications, and media automation services.

The core of the project is the `kubernetes` directory, which is organized into several subdirectories:

*   `bootstrap`: Contains the initial manifests to install Argo CD and seed the app-of-apps controller.
*   `infrastructure`: Manages cluster-level services such as Traefik for ingress, MetalLB for load balancing, Longhorn for persistent storage, and cert-manager for TLS certificates. It also includes monitoring tools like Kube Prometheus Stack and Gatus.
*   `apps`: Contains user-facing applications, primarily for media automation. This includes popular services like Jellyfin, Plex, Radarr, Sonarr, and Transmission.
*   `games`:  Holds configurations for game servers, such as Minecraft.
*   `storage`: Defines PersistentVolumes for the media stack.
*   `testing`: A sandbox for temporary experiments and benchmarks.

The project emphasizes automation and security with tools like:

*   **Renovate:** A self-hosted bot that automatically updates dependencies.
*   **GitHub Actions:** Used for continuous integration to validate Kubernetes manifests with `kubeconform`.
*   **Pre-commit hooks:** Enforce YAML style basics (final newline) to keep `yamllint` happy.
*   **Bitwarden Secrets Operator:** Injects secrets into the cluster, keeping sensitive data out of the Git repository.

## Architecture & Patterns

*   Argo CD uses an app-of-apps pattern with `directory.recurse` to discover any `app.yaml` automatically.
*   Sync ordering is controlled with waves: -2 (PVs), 0 (core infra), 1 (infra dependencies), 30 (user apps).
*   Storage is Longhorn-backed; `longhorn-prod` uses 3 replicas with `dataLocality: best-effort` and aggressive pod deletion for failover.
*   Talos must be installed with the factory installer schematic to retain extensions:
    * `talosImageURL: factory.talos.dev/installer/284a1fe978ff4e6221a0e95fc1d01278bab28729adcb54bb53f7b0d3f2951dcc`

## Building and Running

To bootstrap a new cluster with this GitOps setup, follow these steps:

1.  **Create the Argo CD namespace:**
    ```bash
    kubectl apply -f kubernetes/bootstrap/argocd-namespace.yaml
    ```

2.  **Install Argo CD:**
    ```bash
    kubectl apply -k kubernetes/bootstrap/argocd-install
    ```

3.  **Seed the infrastructure app-of-apps:**
    ```bash
    kubectl apply -f kubernetes/bootstrap/infrastructure-app.yaml
    ```

4.  **(Optional) Enable application trees:**
    ```bash
    kubectl apply -f kubernetes/bootstrap/apps-app.yaml
    kubectl apply -f kubernetes/bootstrap/apps-external-app.yaml
    ```

Once these steps are completed, Argo CD will take over and continuously reconcile the state of the cluster with the manifests in this repository.

## Quick Tooling Setup & Validation

*   Install pinned tool versions and trust repo config: `mise install` then `mise trust .mise.toml`.
*   Validate manifests before merging: `kustomize build <path> | kubeconform -strict -` and `yamllint <path>/`.

## Development Conventions

This project follows a set of conventions to maintain code quality and consistency:

*   **Kustomize:** Used extensively to manage Kubernetes configurations, with a preference for overlays and shared bases (`_shared` directory) to reduce duplication.
*   **Pre-commit Hooks:** Before committing any changes, a pre-commit hook runs to:
    *   Ensure YAML files have a trailing newline to comply with `yamllint` rules.
    To enable the hooks, run:
    ```bash
    git config core.hooksPath .githooks
    ```
*   **Manifest Validation:** All Kubernetes manifests are validated against their schemas using `kubeconform`. This is enforced in the CI pipeline.
*   **Linting:** `yamllint` is used to enforce YAML best practices, with a custom configuration defined in `.yamllint.yaml`.
*   **Secrets Management:** Secrets are managed outside of the repository using the Bitwarden Secrets Operator.

## Common Workflows

*   Add an app: create `kubernetes/apps/default/<name>/` with `app.yaml`, `kustomization.yaml`, manifests, and set sync wave `30`.
*   Add infrastructure: create under `kubernetes/infrastructure/<name>/` with sync wave `0` or `1`.
*   Talos config pipeline: `talconfig.yaml + talsecret.sops.yaml` → `talhelper genconfig` → `clusterconfig/*.yaml` → `talosctl apply-config`.
*   Talos operations (examples): `talosctl -n 10.0.0.34 services`, `talosctl get disks --nodes 10.0.0.36 --insecure`, `talosctl apply-config --insecure --nodes 10.0.0.36 --file clusterconfig/talos-rao-brainiac-02.yaml`.
*   Kubernetes checks: `kubectl get nodes -o wide`, `kubectl get applications -n argocd`, `argocd app sync <app-name>`.

## Cluster Details

*   Cluster name: `talos-rao`; Talos v1.11.5, Kubernetes v1.34.1.
*   Control plane nodes: brainiac-00 (10.0.0.34), brainiac-01 (10.0.0.35), brainiac-02 (10.0.0.36); VIP 10.0.0.30.
*   Networks: Pod CIDR 10.244.0.0/16, Service CIDR 10.96.0.0/12, MetalLB pool 10.0.0.200-10.0.0.250.
*   System extensions (all nodes): i915, intel-ice-firmware, intel-ucode, iscsi-tools, mei, nut-client, nvme-cli, thunderbolt, util-linux-tools.

## Current Cluster Status (as of 2025-11-21)

The Talos cluster is currently undergoing maintenance.

1.  **Objective:** Upgrade the Talos OS on the control plane nodes.
2.  **Blocker:** An attempt to upgrade `brainiac-01` (10.0.0.35) was halted because it would cause the cluster to lose quorum.
3.  **Resolution:** A new control plane node, `brainiac-02` (10.0.0.36), is being added to the cluster to ensure quorum is maintained during the rolling upgrade.
4.  **Next Steps:**
    *   Apply the machine configuration for `brainiac-02`. A configuration file exists at `talos/clusterconfig/talos-rao-brainiac-02.yaml`.
    *   After `brainiac-02` joins the cluster, proceed with the upgrade of the other control plane nodes one at a time.
5.  **Known Issue:** There is a recurring TLS certificate error when connecting to `brainiac-01` (`x509: certificate signed by unknown authority`). The `--insecure` flag for `talosctl` is being used as a temporary workaround.

A detailed guide for these steps has been created in `talos/README.md`.

## Common Issues & Notes

*   Missing extensions after boot usually means the base Talos installer was used; switch to the factory installer URL above and reapply configs.
*   If an Argo CD Application will not sync, check the Application description and `argocd-app-controller` logs; common causes are missing namespaces or missing injected secrets.
*   Renovate PRs are validated by kubeconform in CI; test locally before merge when regex managers touch manifests.
