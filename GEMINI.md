# Gemini Project: BrainiacOps

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
*   **Pre-commit hooks:** Enforce code quality and security by running `TruffleHog` to scan for secrets and `yamllint` to check for style issues.
*   **Bitwarden Secrets Operator:** Injects secrets into the cluster, keeping sensitive data out of the Git repository.

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

## Development Conventions

This project follows a set of conventions to maintain code quality and consistency:

*   **Kustomize:** Used extensively to manage Kubernetes configurations, with a preference for overlays and shared bases (`_shared` directory) to reduce duplication.
*   **Pre-commit Hooks:** Before committing any changes, a pre-commit hook runs to:
    *   Scan for secrets using `TruffleHog`.
    *   Ensure YAML files have a trailing newline to comply with `yamllint` rules.
    To enable the hooks, run:
    ```bash
    git config core.hooksPath .githooks
    ```
*   **Manifest Validation:** All Kubernetes manifests are validated against their schemas using `kubeconform`. This is enforced in the CI pipeline.
*   **Linting:** `yamllint` is used to enforce YAML best practices, with a custom configuration defined in `.yamllint.yaml`.
*   **Secrets Management:** Secrets are managed outside of the repository using the Bitwarden Secrets Operator.
