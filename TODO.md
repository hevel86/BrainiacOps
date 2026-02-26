# BrainiacOps Roadmap & Tasks

## Completed Tasks
- [x] **Tailscale Authentication Modernization**
  - [x] Generate a Tailscale OAuth Client in the Admin Console (Settings > OAuth).
    - **Scopes selected:** `Devices` (R/W), `Routes` (R/W), `Keys` (R/W), `Logs` (R).
    - **Tag assigned:** `tag:homelab`.
  - [x] Replace the current 90-day Auth Key in Bitwarden with the new OAuth key.
    - **Bitwarden Secret ID:** `93c1059d-22a1-4454-83ff-b33e010d5bbc`.
    - **Format:** `tskey-client-<client-id>-<client-secret>?ephemeral=false`.
  - [x] Update documentation in `kubernetes/infrastructure/tailscale/README.md`.
  - [x] Standardize sidecar configurations for Portainer, Syncthing, and Semaphore UI.
