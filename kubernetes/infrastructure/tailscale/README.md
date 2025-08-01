# Tailscale Integration

This folder contains Tailscale integration resources for Kubernetes.

## Generate an Auth Key

1. Log in to the Tailscale admin console:  
   https://login.tailscale.com/admin/settings/keys

2. Generate a **reusable** auth key with auto-approval enabled (ephemeral keys will not persist across pod restarts).

3. Save the key in a `Secret` manifest called `tailscale-secret.yaml`. Example:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: tailscale
  namespace: default
type: Opaque
stringData:
  TS_AUTHKEY: tskey-auth-abc123...
