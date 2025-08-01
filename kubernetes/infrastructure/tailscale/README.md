# Tailscale Integration

This folder contains Tailscale integration resources for Kubernetes.

## Generate an Auth Key

1. Log in to the Tailscale admin console:
   https://login.tailscale.com/admin/settings/keys

2. Generate an **ephemeral** or **reusable** auth key.

3. Create the secret in Kubernetes:

```bash
kubectl create secret generic tailscale-auth \
  --from-literal=TS_AUTHKEY="tskey-abc123..." \
  --namespace=default
