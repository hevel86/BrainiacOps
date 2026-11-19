# Paperclip

## Deployment

- GitOps path: `kubernetes/apps/ai/paperclip/`.
- Parent Argo CD application: `apps-ai`; child: `paperclip`.
- Namespace: `default`.
- Upstream image: `ghcr.io/paperclipai/paperclip:2026.1117.0`, pinned by
  multi-platform digest. The registry index includes Linux AMD64 and ARM64.
- One non-root application replica, with embedded PostgreSQL and all application
  state mounted at `/paperclip` on a 20Gi `longhorn-prod` RWO PVC.
- `Recreate` rollout strategy avoids overlapping writers/volume mounts. Updates
  have downtime. Startup migrations are explicitly enabled.
- Requests: 250m CPU / 1Gi memory; limits: 4 CPU / 8Gi memory. Agent workloads
  share these limits; revisit them after observing actual usage.
- The pod has no mounted Kubernetes API token, host mounts, or container socket.
  No Kubernetes permissions are granted to Paperclip or its agents.

## Access and initial setup

Expected URL after reconciliation: `https://paperclip.tailca892.ts.net`.

The Tailscale ingress class provisions tailnet-only HTTPS. There is no public
Traefik route, public DNS record, Funnel annotation, or MetalLB address.
MagicDNS, tailnet HTTPS certificates and permission for the operator's tagged
proxies must be enabled in Tailscale. Confirm the hostname in the live Ingress
status; resolve conflicts before changing the canonical application URL.

Paperclip uses `authenticated` mode and `private` exposure. Once deployed, open
its URL from a permitted tailnet device, create/sign into your Paperclip account,
then choose **Claim this instance**. Complete this promptly: the first signed-in
user to claim an unconfigured private instance becomes its administrator. Restrict
initial access to trusted tailnet users. This claim has not been performed by the
manifest preparation step.

Configure a model provider or supported subscription under **Apps → Connections**
after claiming the instance. No provider credentials are bundled or borrowed from
Hermes. The service can start without them, but model-backed agent runs need a
working provider connection. Agent-execution functionality is not verified merely
by an HTTP readiness response.

## Secrets

`BitwardenSecret/default/paperclip-secrets` maps only:

| Kubernetes Secret key | Bitwarden item UUID |
| --- | --- |
| `BETTER_AUTH_SECRET` | `500bf414-3b0c-4a76-8654-b50700f31d55` |
| `PAPERCLIP_TOOL_ACTION_SIGNING_SECRET` | `0728d16f-0c40-446b-8de9-b50700f33a4f` |

The operator uses the existing `bw-auth-token` and organization. Its machine
account must be allowed to read both items. UUIDs are references, not secret
values. Never reuse the Hermes dashboard password for either key.

Keep both signing values persistent across restarts. Environment-sourced values
are loaded at pod start; changing a Bitwarden item does not update a running
container's environment. Coordinate rotation with an approved rollout. Outstanding
tool approvals can depend on the previous signing key.

The persistent application home also holds its local-encryption key and provider
connection state. Treat volume backups as sensitive and preserve that key together
with the database. `Delete=false` and Longhorn's `Retain` protect against normal
GitOps deletion; they are not independent disaster-recovery backups.

## Rollout and verification

By default Michael handles staging, commits and pushes; the agent may perform
these steps when Michael explicitly authorizes them. Integrate with current
master before committing, without overwriting unrelated upstream changes.

After push, `apps-ai` discovers `app.yaml`; the child automatically reconciles its
Kustomize resources. Do not include `app.yaml` in the child `kustomization.yaml`.

```bash
kubectl get applications -n argocd apps-ai paperclip
kubectl get bitwardensecret paperclip-secrets -n default
kubectl get pvc paperclip-data-pvc-lh -n default
kubectl rollout status deployment/paperclip -n default --timeout=900s
kubectl get pods -n default -l app=paperclip
kubectl get ingress paperclip -n default
```

Require a successful Bitwarden synchronization, bound PVC, available deployment,
healthy/synced Argo CD child, and populated ingress hostname. From a permitted
tailnet client, verify `/api/ready`, the login page, account setup and a real agent
run. Review logs privately: bootstrap links or application details may be sensitive.

The startup/readiness probes use `/api/ready` and an explicit allowed Host header.
Liveness is TCP-only so a transient dependency problem does not immediately cause
a restart loop. HTTP readiness alone is not proof of database backup health.

Before upgrades, take and verify an application-consistent PostgreSQL backup and
preserve the complete application home. The image runs migrations on boot; reverting
an image alone may not roll back schema changes. Embedded PostgreSQL intentionally
keeps this a single-replica private deployment, not a highly available database.

## Preparation validation

- Kustomize rendering and yamllint pass.
- Kubeconform validates the built-in resources; Application and BitwardenSecret
  schemas are skipped by the repository's standard `-ignore-missing-schemas` policy.
- Live API server dry-run accepts Deployment, Service and Ingress.
- Server dry-run of PVC, BitwardenSecret and Application is blocked by Hermes RBAC;
  those resources must be created by GitOps, not by expanding Hermes permissions.
- No live installation or application boot is implied by these checks. Docker CLI
  is present in this agent environment but no Docker daemon is available for a
  local container boot test.

## Upstream references

- Paperclip source: <https://github.com/paperclipai/paperclip>
- Release: <https://github.com/paperclipai/paperclip/releases/tag/v2026.1117.0>
- Docker: <https://github.com/paperclipai/paperclip/blob/v2026.1117.0/doc/DOCKER.md>
- Auth: <https://github.com/paperclipai/paperclip/blob/v2026.1117.0/doc/DEPLOYMENT-MODES.md>
- Tailscale ingress: <https://tailscale.com/docs/kubernetes-operator/ingress>
