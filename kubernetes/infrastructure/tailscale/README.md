# Tailscale Integration

This folder contains Tailscale integration resources for Kubernetes.

## Authentication Methods

### 1. OAuth Clients (Recommended - Non-Expiring)
Tailscale OAuth Clients allow you to generate a key that does **not expire** after 90 days.

1. Log in to the [Tailscale Admin Console](https://login.tailscale.com/admin/settings/oauth).
2. Create a new OAuth Client with:
   - **Scopes:** `Devices: Read/Write`
3. The format to use as the key is: `tskey-client-<client-id>-<client-secret>`.
4. Store this key in your Bitwarden vault (linked to the BitwardenSecret in this folder).

### 2. Standard Auth Keys (Expires every 90 days)
1. Log in to the [Tailscale Admin Console](https://login.tailscale.com/admin/settings/keys).
2. Generate a **reusable** auth key with auto-approval enabled.
3. Save the key in your Bitwarden vault.

## Kubernetes Configuration
The `BitwardenSecret` in this folder pulls the key from your vault and maps it to a Kubernetes secret.
