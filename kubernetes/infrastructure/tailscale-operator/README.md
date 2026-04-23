# Tailscale Kubernetes Operator

This app installs the Tailscale Kubernetes Operator into the `tailscale`
namespace using the official Helm chart.

The operator credentials are not stored in Git. Instead, the chart relies on a
pre-created Kubernetes secret named `operator-oauth` in the `tailscale`
namespace. In this repo that secret is materialized from Bitwarden by:

- [tailscale app](/home/michael/gitstuff/BrainiacOps/kubernetes/infrastructure/tailscale/app.yaml)
- [operator-bitwarden-secrets.yaml](/home/michael/gitstuff/BrainiacOps/kubernetes/infrastructure/tailscale/operator-bitwarden-secrets.yaml)

The secret must contain:

- `client_id`
- `client_secret`

If `operator-oauth` is missing, the operator chart will not be able to start
correctly.
