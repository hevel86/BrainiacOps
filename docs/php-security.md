# PHP security response

## October 21, 2026 advisory

[PHP's advisory](https://www.php.net/archive/2026.php#2026-10-21-5) covers
CVE-2026-109618 (out-of-memory corruption) and CVE-2026-109619 (stale global
state). Both can allow unauthenticated remote code execution in web-serving PHP,
including FPM and FrankenPHP. Application authentication is not a sufficient
defense.

The fixed upstream releases are PHP 8.2.35, 8.3.36, 8.4.27 and 8.5.12.
Distribution packages may instead contain documented backports. Updating to a
verified patched runtime is the complete fix; the settings below only reduce
exposure to specific attack paths.

Runtime inspection on October 21 found:

| Application | Container tag | PHP runtime |
| --- | --- | --- |
| Nextcloud | `lscr.io/linuxserver/nextcloud:33.0.5` | 8.4.16, FPM |
| WatchState | `ghcr.io/arabcoders/watchstate:v1.10.8` | 8.5.9, FrankenPHP |

Application tags are not PHP versions. No replacement image was verified as
patched during this assessment. Do not assume restarting or pulling the same
tag resolves the vulnerabilities.

## Git-managed partial mitigations

Nextcloud loads a generated ConfigMap before request parsing.
Kustomize's default name hashes change the pod template when these settings
change, so syncing the Deployment restarts all workers. Keep those hashes
enabled: updating a mounted file alone does not reload PHP startup settings,
and Nextcloud uses subPath mounts that do not receive live ConfigMap updates.

- Nextcloud disables session upload-progress tracking in an INI file and its
  FPM pool, and enforces `memory_limit=-1` using an FPM admin setting that
  application code cannot override. Its container memory limit is 2 GiB.
- Both the `nextcloud` and `nextcloud-mariadb` deployments set
  `automountServiceAccountToken: false` so neither container receives a
  Kubernetes API ServiceAccount token.

Nextcloud's memory request is 256 MiB. Idle usage during assessment was approximately
178 MiB; this is not a peak measurement.
Monitor peak usage and OOM kills after deployment. Container limits provide an
availability boundary when PHP's own memory limit is removed, but memory
allocation failures can still reach vulnerable code.

WatchState remains unchanged at the operator's request because it is LAN-only:
its Service uses a private MetalLB address and internal DNS, with no Kubernetes
ingress route. Router port-forwards and external tunnels were not checked.
It still needs a patched runtime when available.

Nextcloud retains its existing upload sizes for compatibility. This leaves its
large-request exposure unchanged. PHP recommends `post_max_size=32M` for apps
requiring uploads, with a smaller `upload_max_filesize`. Adding that restriction
requires checking Nextcloud browser, WebDAV and sync-client chunk sizes; requests
larger than the cap would be rejected. Its ingress uses TLS passthrough, so an
HTTP buffering middleware on that TCP route cannot enforce a request body limit.

The upload-progress setting blocks confirmed session-related stale-state paths;
other variants remain possible. Prioritize verified patched container images,
especially for publicly reachable Nextcloud.

## Deploy and verify

Nextcloud currently has automated Argo CD sync disabled. After manually
committing and pushing the changes, explicitly sync the application:

```bash
argocd app sync nextcloud
kubectl rollout status -n default deployment/nextcloud
```

The single-replica deployment uses Recreate, so expect a brief interruption.
Check Argo CD health, readiness and restart counts, then test login, a Nextcloud
upload/download.

Inspect only relevant PHP values; avoid full phpinfo or environment dumps:

```bash
kubectl exec -n default deploy/nextcloud -- php -r \
  'echo PHP_VERSION, "\n"; echo "session.upload_progress.enabled=", ini_get("session.upload_progress.enabled"), "\n";'

# FPM admin settings are separate from CLI settings. Filter the config dump.
kubectl exec -n default deploy/nextcloud -- php-fpm84 -tt 2>&1 \
  | rg 'php_admin_value\[(memory_limit|session.upload_progress.enabled)\]|test is successful|ERROR'

kubectl top pods -n default | rg 'nextcloud'
```

Expected values are `-1` for the FPM memory limit and `0` for upload-progress
tracking. These
commands check configuration, not exploitability; successful output does not
establish that an unpatched runtime is safe.

When patched images become available, verify their actual bundled PHP versions
or vendor backports, update image references in Git, sync and repeat the checks.
Recheck Nextcloud's PHP paths and FPM executable if a new image changes PHP
branches. Upgrade Nextcloud through its supported application upgrade sequence;
do not skip major versions to obtain a newer PHP runtime.
