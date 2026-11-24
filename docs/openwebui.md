# Open WebUI

Manifests: `kubernetes/apps/ai/openwebui/`, discovered by `apps-ai`.

## Deployment contract

- Official upstream v0.13.4 image pinned by immutable multi-architecture digest.
- One replica, Recreate strategy, SQLite and all application data on a 10Gi
  `longhorn-prod` PVC. `Delete=false` retains the claim on Argo app deletion.
- Tailnet HTTPS only: Tailscale Ingress `openwebui`, ClusterIP backend on 8080.
  No Traefik route, public DNS annotation, NodePort or LoadBalancer is added.
- Intended URL: `https://openwebui.tailca892.ts.net`; verify the operator-assigned
  hostname after rollout. Tailnet ACLs determine which devices can reach it.
- Login remains enabled. Claim the first administrator promptly: upstream allows
  initial admin signup even with ENABLE_SIGNUP=false, then disables registration.
  Tailnet access does not remove this first-claim risk.
- Bitwarden item `2b3a268d-2f72-4ae5-b88f-b50c01529f04` maps to WEBUI_SECRET_KEY.
  The operator machine account must have access to this dedicated item.
- No Ollama or other inference server is deployed. Configure provider connections
  in Admin Panel after login. OpenAI-compatible connections are enabled; Ollama
  is initially disabled and can be enabled through application configuration.
- Provider credentials and admin configuration stored by Open WebUI reside on
  its PVC and must be included in a backup/restore plan. Retain the signing key.

## Security and validation limits

The upstream image defaults to UID 0 and labels non-root configurations untested.
This manifest retains the upstream runtime identity, drops Linux capabilities,
disables privilege escalation and uses RuntimeDefault seccomp. Server dry-run
accepts the Deployment but warns about runAsNonRoot under restricted PodSecurity.
Do not assume this manifest runs in a namespace enforcing the restricted profile.

Local Kustomize rendering, yamllint and core-resource kubeconform checks pass.
Application and BitwardenSecret are custom resources excluded from kubeconform.
Server dry-run accepts the Service, PVC, Deployment and Ingress; Hermes lacks
CREATE permission for Application and BitwardenSecret, so their admission and
controller reconciliation remain unverified. No live resources were created.

## Activation and verification

Publishing these files to master allows the auto-synced apps-ai parent to create
an auto-synced child: merging/pushing activates the workload. Review first.
No imperative workload bootstrap is required on rebuild.

After publication, verify the child revision, successful Bitwarden synchronization,
bound PVC, available Deployment, pod restart count and Tailscale Ingress hostname.
A temporarily missing generated Secret may delay container startup; do not create
an ad hoc replacement Secret. Check the operator if synchronization fails.

Test HTTPS from a device outside the home LAN: Tailscale on must reach the login
page with valid TLS; Tailscale off must not reach the app. Claim the administrator,
confirm signup is disabled, configure a provider and run a harmless test chat.
Cluster readiness alone does not verify off-LAN access or model inference.

## Sources

- https://docs.openwebui.com/getting-started/
- https://github.com/open-webui/open-webui/releases/tag/v0.13.4
- https://github.com/open-webui/open-webui/blob/v0.13.4/backend/open_webui/routers/auths.py
