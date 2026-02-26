# Tailscale Integration

This folder contains Tailscale integration resources for Kubernetes.

## Authentication Methods

### 1. OAuth Clients (Recommended - Non-Expiring)
Tailscale OAuth Clients allow you to generate a key that does **not expire** after 90 days. This is the preferred method for Kubernetes sidecars.

#### Creation Steps
1. Log in to the [Tailscale Admin Console](https://login.tailscale.com/admin/settings/oauth).
2. Create a new OAuth Client with the following scopes:
   - **Devices:** `Read & Write` (Required to join the tailnet)
   - **Keys:** `Read & Write` (Required for the sidecar pattern)
   - **Routes:** `Read & Write` (Required for subnet routing)
3. Assign a **Tag** (e.g., `tag:homelab`) to the client.
4. **Save the Client ID and Secret.**

#### Bitwarden Configuration
Store the key in your Bitwarden vault using the following format:
`tskey-client-<client-id>-<client-secret>?ephemeral=false`

*Note: The `?ephemeral=false` suffix is critical to ensure the machine identity persists across pod restarts.*

#### Tailscale ACL Requirements
Ensure the tag used is owned by `autogroup:admin` in your [ACL JSON](https://login.tailscale.com/admin/acls/file):
```json
"tagOwners": {
    "tag:homelab": ["hevel86@github", "autogroup:admin"]
}
```

### 2. Standard Auth Keys (Expires every 90 days)
*Discouraged for long-running services.*
1. Log in to the [Tailscale Admin Console](https://login.tailscale.com/admin/settings/keys).
2. Generate a **reusable** auth key with auto-approval enabled.
3. Save the key in your Bitwarden vault.

## Kubernetes Configuration
The `BitwardenSecret` in this folder pulls the key from your vault and maps it to a Kubernetes secret named `tailscale`.

### Standard Sidecar Arguments
For consistency across the cluster, all sidecars should use these `TS_EXTRA_ARGS`:
`--hostname=<app>-sidecar --accept-routes=true --accept-dns=true --advertise-tags=tag:homelab`
