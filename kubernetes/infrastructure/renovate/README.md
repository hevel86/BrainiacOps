# Renovate Bot Deployment

This folder contains the Argo CD application to deploy a self-hosted Renovate bot.

## Authentication via Bitwarden Secrets Operator

Renovate requires a secret named `renovate-secrets` in the `renovate` namespace containing a GitHub Personal Access Token (PAT). This setup uses the **Bitwarden Secrets Operator** to securely inject the token from your Bitwarden vault.

### 1. Generate a GitHub Fine-Grained Personal Access Token

For enhanced security, it is highly recommended to use a **Fine-grained Personal Access Token** which grants only the necessary permissions to Renovate.

1.  Go to your GitHub **Developer settings** > **Personal access tokens** > **Fine-grained tokens**.
2.  Click **Generate new token**.
3.  Give the token a descriptive name (e.g., `renovate-bot`).
4.  Set an expiration date.
5.  Under **Repository access**, select **Only select repositories** and choose `hevel86/BrainiacOps`.
6.  Under **Permissions**, select **Repository permissions**.
7.  Grant the following permissions:
    -   **Actions**: `Read-only`
    -   **Administration**: `Read-only` (to read branch protection rules)
    -   **Commit statuses**: `Read-only` (to read CI/CD status checks)
    -   **Contents**: `Read and write` (to read files, create branches/commits)
    -   **Issues**: `Read and write`
    -   **Metadata**: `Read-only` (default)
    -   **Pull requests**: `Read and write`
    -   **Workflows**: `Read and write` (to update GitHub Actions workflow files)
8.  Click **Generate token** and copy the token immediately. You will not be able to see it again.

### 2. Store and Expose the Secret

> [!IMPORTANT]
> **Prerequisite**: The Bitwarden Secrets Operator requires its own authentication token to be present in the `renovate` namespace. Ensure you have created the `bw-auth-token` secret in this namespace before proceeding.
> ```bash
> # Replace <TOKEN_HERE> with your Bitwarden machine account access token
> kubectl create secret generic bw-auth-token -n renovate --from-literal=token="<TOKEN_HERE>"
> ```

1.  **Store the Token in Bitwarden**: Add a new secret to your Bitwarden vault and note its unique ID. Paste the GitHub PAT as its value.

2.  **Verify the `bitwarden-secrets.yaml` file**: This file defines a `BitwardenSecret` resource that tells the operator to fetch the token and create the `renovate-secrets` Kubernetes secret. This manifest is deployed by the `secret-app.yaml` Argo CD Application.
    - Ensure the `metadata.namespace` is set to `renovate`.
    - Ensure `spec.secretName` is set to `renovate-secrets`.
    - Update `spec.organizationId` with your Bitwarden organization ID.
    - Update `map.bwSecretId` with the unique ID of the secret you created in step 1.
    - Populate `DOCKERHUB_USERNAME` and `DOCKERHUB_PASSWORD` with your Docker Hub credentials or PAT so Renovate can authenticate to `index.docker.io`/`registry-1.docker.io` and avoid rate-limit warnings.

Once you commit these files, your app-of-apps controller will discover and sync the `secret-app.yaml`, which in turn deploys the `BitwardenSecret`. The operator then creates the final Kubernetes secret, allowing the Renovate cronjob to authenticate with GitHub.
