# Jellyfin official-image migration and 12.2 upgrade: LLM handoff

**Handoff date:** 2026-10-06, America/New_York  
**Repository:** `/home/michael/gitstuff/BrainiacOps`  
**Purpose:** Preserve the full operational context so another LLM can continue without repeating work, restarting the cancelled backup, or confusing prepared Git changes with deployed state.

## 1. Read this first

Production is currently running the **official Jellyfin 10.11.11 image**, successfully migrated from LinuxServer. It is healthy and has one ready server pod with zero restarts. **Jellyfin 12.2 has not been deployed.** Its database migrations have not been run by this agent.

The user explicitly authorized proceeding toward **12.2 without the full stopped backup** after cancelling an attempted download. Do not ask for the same backup waiver again, and do not resume that backup process by default. The latest request was to document everything for another LLM because the user is approaching their limits; upgrade execution was paused to create this handoff.

There is an **uncommitted, unfinished stage-2 edit** to `kubernetes/apps/default/jellyfin/deploy.yaml`. It pins both the application and a new plugin-quarantine init container to 12.2. That edit has **not yet been rendered, schema-validated, behavior-tested, committed, pushed, or deployed**. Review and validate it before presenting it for the user's Git operations.

**Never perform `git add`, commit, or push.** The repository explicitly reserves Git operations for the user. Make necessary changes and checks, then stop at that genuine user-managed gate. Once the user commits/pushes, an explicit Argo CD sync is required. Automatic sync remains disabled.

## 2. Exact latest user intent and authorization

Relevant conversation sequence:

1. The user supplied a two-stage migration plan: LinuxServer 10.11.11 → official 10.11.11, then official 12.2, with all nine plugins required for acceptance.
2. The agent prepared and validated stage 1. The user subsequently committed/pushed and deployed it outside the agent's tool actions. Live inspection confirmed that deployment.
3. The user reported: **“I just played with Fladder on my desktop. Seemed to work well.”**
4. The agent explained a stopped backup and the user initially authorized it: **“Ok, go ahead and do that.”**
5. During the large transfer the user interrupted: **“Let's just move forward. I don't want to keep going with downloading everything.”**
6. The agent cancelled the transfer, removed the backup helper, restarted Jellyfin, and verified health.
7. When asked whether to proceed toward 12.2 without that backup, the user replied: **“Yes, proceed without the backup.”**
8. The agent began preparing stage 2, then the user requested this extensive handoff instead of continuing work in this context.

Interpretation:

- The full-backup requirement has been explicitly waived for this upgrade attempt.
- Do not impose another backup approval loop because the older migration document says a backup is mandatory.
- The user still wants the 12.2 upgrade and plugin validation.
- The user has not declared all plugins functionally validated; do not invent those results.
- Preparing/deploying the upgrade and accepting it as successful are separate milestones. All nine plugin checks remain acceptance requirements.
- Permission to proceed does **not** override the no-auto-commit rule.
- Avoid unnecessary downtime, large downloads unrelated to the upgrade, or repetitive confirmation requests.

## 3. Repository rules that remain binding

Read the actual root `AGENTS.md` before continuing. Key rules:

- This is a live GitOps cluster; Argo CD uses Git as desired state.
- Never stage or commit automatically. Do not push on the user's behalf.
- Never put secrets, API tokens, passwords, application databases, plugin secret configuration, or detailed private operational exports into Git.
- Keep private logs and intermediate data under `/tmp`; large sensitive artifacts created in this session are separately located in a protected home backup directory because `/tmp` was too small.
- Use Bitwarden references for any persistent secret configuration.
- Keep `Recreate` for the single replica mounting the RWO config PVC.
- Retain the existing config PVC; never replace it or assume a new claim recovers existing data.
- Config PVC already has `argocd.argoproj.io/sync-options: Delete=false`.
- Keep the Application deletion finalizer.
- Do not use ad hoc scaling or Argo CD patches as persistent desired-state fixes. The temporary maintenance scale here was performed only after verifying auto-sync/self-heal was disabled and was reversed afterward.
- Do not spawn sub-agents unless the user or applicable instructions explicitly authorize delegation. None were used here.

## 4. Last independently verified live state

A final read-only check was performed while creating this handoff.

| Item | Verified value |
| --- | --- |
| Namespace | `default` |
| Argo CD Application | `jellyfin` in `argocd` |
| Deployment | `jellyfin` |
| Desired replicas / ready replicas | 1 / 1 |
| Running server image | `jellyfin/jellyfin:10.11.11@sha256:aefb67e6a7ff1debdd154a78a7bbb780fd0c873d8639210a7f6a2016ad2b35db` |
| Live init containers | None |
| Latest observed server pod | `jellyfin-75bd779b6-fz5wq` |
| Pod phase / readiness / restart count | Running / true / 0 |
| Last known server node | `brainiac-02` |
| Application sync / health | Synced / Healthy |
| Last sync operation phase | Succeeded |
| Argo CD compared revision | `10dea10be0ec3ca9c79cbdf5a104b95fca2c3f4c` |
| Auto-sync / self-heal | Disabled; no `spec.syncPolicy.automated` |
| Sync options | `ServerSideApply=true`, `CreateNamespace=true` |
| Temporary `jellyfin-maintenance` pod | Absent |
| Backup copy/hash processes | No matching active `kubectl exec ... jellyfin-maintenance` processes at handoff |

The HTTP `/health` endpoint returned `Healthy` after the backup cancellation and restart. The final snapshot reconfirmed pod readiness and Argo CD health.

The Meilisearch side deployment stayed running throughout maintenance. It was previously observed ready with zero restarts, using `getmeili/meilisearch:v1.36`. It was not upgraded, scaled down, or reconfigured in this session.

Pod names are transient: rediscover them rather than assuming the recorded name is still current.

## 5. Git history and working tree

The user made these commits after stage-1 preparation:

| Commit | Subject |
| --- | --- |
| `6797ccb` | `chore(renovate): Adjust Jellyfin versioning and pinning` |
| `fcbb2f4` | `feat(jellyfin): Use official image and configure data dirs` |
| `10dea10` | `docs(jellyfin): Add migration and transcoding notes` |

At the start of handoff writing, `git status --short` showed only:

```text
 M kubernetes/apps/default/jellyfin/deploy.yaml
```

This handoff is an additional newly created file:

```text
docs/jellyfin-upgrade-handoff-2026-10-06.md
```

No stage-2 changes have been staged or committed by the agent. Inspect current `git status` because the user may make further changes between sessions.

## 6. Stage 1: what changed and is now deployed

### Deployment changes

- Replaced `lscr.io/linuxserver/jellyfin:10.11.11` with the digest-pinned official image at the same server version.
- Set pod `runAsUser: 1000`, `runAsGroup: 1000`; retained `fsGroup: 1000`.
- Removed LinuxServer-specific `PUID`, `PGID`, and `DOCKER_MODS`.
- Preserved LinuxServer's persistent layout with explicit variables:

| Variable | Value |
| --- | --- |
| `JELLYFIN_DATA_DIR` | `/config/data` |
| `JELLYFIN_CONFIG_DIR` | `/config` |
| `JELLYFIN_CACHE_DIR` | `/config/cache` |
| `JELLYFIN_LOG_DIR` | `/config/log` |
| `XDG_CACHE_HOME` | `/config/cache` |
| `TZ` | `America/New_York` |

- Kept the official image defaults for the web client and FFmpeg:
  - Web: `/jellyfin/jellyfin-web`.
  - FFmpeg: `/usr/lib/jellyfin-ffmpeg/ffmpeg`.
- Retained the Intel GPU resource request and limit: `gpu.intel.com/i915: "1"`.
- Retained requests of 1 CPU / 4 GiB and limits of 4 CPUs / 16 GiB.
- Retained `/transcode` as an 8 GiB memory-backed `emptyDir`.
- Retained `/data/tv` and `/data/movies` mount paths and existing shared claims.
- Retained `jellyfin-config-lh` as the existing 100 GiB `longhorn-prod` RWO configuration claim.
- Retained `Recreate` and disabled auto-sync.

### Renovate changes already committed

The Jellyfin package rule now:

- Matches `jellyfin/jellyfin`.
- Uses `versioning: 'loose'` because releases changed from three components (`10.11.11`) to two (`12.2`).
- Allows only numeric two- or three-component tags with regex `/^\d+\.\d+(?:\.\d+)?$/` (appropriately escaped in JSON5).
- Sets `pinDigests: true`.
- Sets `automerge: false`.
- Groups updates under `Jellyfin` / `jellyfin`.

### Documentation already committed

- `kubernetes/apps/default/jellyfin/TRANSCODING-CONFIG.md` was rewritten around the official image and corrected the transcode scratch size to 8 GiB.
- `kubernetes/apps/default/jellyfin/MIGRATION.md` was added with the two-stage plan, backup procedure, plugin acceptance table, and rollback requirements.

**These documents contain stale status statements.** They were written before deployment and before the user waived the backup. Update them during stage-2 preparation; this handoff records the newer factual state and authorization.

## 7. Stage-1 validation completed

### Repository validation at preparation time

- `kustomize build kubernetes/apps/default/jellyfin` passed.
- `kubeconform -strict -ignore-missing-schemas -summary` on the rendered output passed:
  - 10 resources total.
  - 8 valid.
  - 0 invalid / 0 errors.
  - 2 custom resources skipped because schemas were unavailable (`BitwardenSecret`, `IngressRoute`).
- `renovate-config-validator renovate.json5` passed.
- `git diff --check` passed.

These results apply to the committed stage-1 change. They **do not validate the new stage-2 init container**.

### Live validation after stage-1 deployment

- Correct official image and pinned digest observed in the live deployment/pod.
- Argo CD Synced/Healthy.
- Effective identity was `uid=1000 gid=1000 groups=1000`.
- Config and data directories were owned by `1000:1000`, mode `2775`.
- Render device `/dev/dri/renderD128` was accessible, mode `0666`.
- Startup logs confirmed all intended data/config/cache/log/web paths and the bundled FFmpeg path.
- Startup completed successfully in approximately 6.8 seconds on the first official-image pod.
- All nine third-party plugins loaded, along with Jellyfin's built-in providers.
- `/health` returned `Healthy`.
- `/web/index.html` returned HTTP 200.
- `vainfo` initialized the Intel iHD driver and listed decode/encode profiles.
- A 60-frame synthetic H.264 QSV encode passed.
- OpenCL device initialization passed.
- Server restart count remained zero.
- The user reported successful desktop playback through **Fladder**.

### What these checks do not prove

- Fladder's session was not classified as direct-play vs transcode.
- No real HDR-to-SDR playback test was verified in this session.
- No before/after account/library count or watched/resume-state comparison was completed.
- Plugin load success is not functional validation of all nine plugins.
- No metadata refresh, webhook delivery test, Session Cleaner behavior test, Meilisearch reindex/search test, or known-episode skip interaction was completed by the agent.
- The user chose to move forward; keep these checks pending for acceptance, without pretending they already passed.

## 8. Diagnostic pitfalls and observed warnings

### Important: deployment-based exec/logs selected Meilisearch

The Jellyfin deployment selector is broad (`app: jellyfin`), and Meilisearch also uses that app label. During diagnostics, both `kubectl logs deployment/jellyfin` and `kubectl exec deployment/jellyfin` selected the Meilisearch pod. This produced misleading output (root UID, no `/config`, no FFmpeg, connection refused on 8096).

Those were **commands against the wrong pod**, not faults in the official Jellyfin image.

Use the server component label to find the correct pod and then specify the container:

```bash
jf_pod=$(kubectl get pods -n default -l app=jellyfin,component=server \
  -o jsonpath='{.items[0].metadata.name}')
kubectl logs -n default "$jf_pod" -c jellyfin
kubectl exec -n default "$jf_pod" -c jellyfin -- id
```

Do not blindly use old deployment-based verification commands in `TRANSCODING-CONFIG.md`; update them to select the actual server pod. Changing an existing Deployment selector is not a routine mutable patch, so do not expand this upgrade into a selector migration without considering its implications.

### Startup warnings observed

The first official-image startup had warnings about:

- ASP.NET using an in-memory/ephemeral data-protection key repository.
- No XML key encryptor configured.
- Missing `/wwwroot` for static file middleware.

The web client at its correct official-image path returned HTTP 200. No startup errors were observed in that diagnostic capture. These warnings were reported but not fixed or fully investigated. Later filesystem inspection showed a `/config/.aspnet/DataProtection-Keys` directory; that fact alone does not prove the warnings are resolved.

### OpenCL diagnostic command ordering

An initial OpenCL test failed because it referenced `va` before creating it. The corrected command initialized VAAPI first and passed. Do not interpret the initial CLI ordering error as an OpenCL runtime failure.

### Slow startup after backup cancellation

The replacement pod spent time in `ContainerCreating`. Its event said volume ownership changes were taking longer than expected and suggested `fsGroupChangePolicy: OnRootMismatch`. It subsequently became healthy without intervention.

`fsGroupChangePolicy` was **not changed**. It is a potential future optimization, not a prerequisite or a completed fix.

## 9. Cancelled stopped-backup attempt: exact accounting

### Why the destination changed

- `/config` used about **27 GiB**.
- `/tmp` was a **2 GiB tmpfs**, unsuitable for the archive or extraction.
- The filesystem containing `/home/michael` had over **900 GiB free**.
- The agent created a private mode-0700 directory outside the repository:

```text
/home/michael/backups/jellyfin-official-10.11.11-20261006
```

### Actions that actually occurred

1. Verified auto-sync/self-heal was disabled.
2. Created a temporary `jellyfin-maintenance` pod on the same node as the server.
3. Used `python:3.13-bookworm` with a sleeping process and read-only mount of the existing config claim.
4. Saved the then-current deployment JSON privately in the backup directory.
5. Scaled only `deployment/jellyfin` to zero.
6. Waited for the original server pod to terminate.
7. Started a GNU tar archive preserving numeric owners, ACLs, extended attributes and sparse files.
8. Cancelled the uncompressed transfer and restarted with `gzip -1` compression to shorten downtime.
9. Started a separate read-only SHA-256/content/metadata inventory of the stopped source.
10. Downloaded the local Docker `python:3.13-bookworm` image to support later extraction/integrity checks.
11. The user cancelled the backup work before any verification completed.
12. Terminated the active copy and inventory clients, deleted the helper pod, restored deployment replicas to one, and verified service health.

### Files left behind at final inspection

| File under the private backup directory | Approximate size / state |
| --- | --- |
| `config.tar.partial` | 2.5 GiB; aborted uncompressed transfer |
| `config.tar.gz.partial` | 6.1 GiB; aborted compressed transfer |
| `deployment.json` | 6.3 KiB; prior official-10.11.11 deployment |
| `source-inventory.json` | **0 bytes**; inventory never completed |
| `source-root-metadata.json` | 74 bytes; root directory metadata only |

There is **no completed archive, no verified checksum, no completed restore extraction, no completed source comparison, and no SQLite integrity result** from this attempt.

Do not rename these partial files to make them look complete. Do not rely on them for rollback. They occupy about 8.5 GiB and remain sensitive application data even though incomplete. They were not deleted, committed, or published. Cleanup is separate from the requested upgrade; do not resume downloading them.

### Temporary working files and image

These may survive locally, but `/tmp` is ephemeral:

```text
/tmp/jellyfin-backup-work/pod.json
/tmp/jellyfin-backup-work/inventory.py
/tmp/jellyfin-backup-work/verify.py
/tmp/jellyfin-stage1.log
/tmp/jellyfin-rendered.yaml
```

- `pod.json` is the old **read-only** helper definition, not an active pod.
- `inventory.py` and `verify.py` were scratch scripts, not a completed backup solution. They were not committed. Do not assume their verification ever ran.
- The local verification image pull completed. No restored extraction was performed.
- The source config volume was not intentionally altered by the backup helper; it was mounted read-only.
- Restarting Jellyfin afterward naturally resumed normal application writes.

### Longhorn backup status

The original supplied plan said the configuration volume was healthy and had a backup recorded on October 6. This session did **not** inspect/restore/validate that backup or prove it was taken with Jellyfin stopped. Do not promote that earlier finding into a guaranteed current rollback point.

The user has explicitly waived the new full backup. Keep the rollback limitation factual and do not restart the backup approval discussion.

## 10. Verified stage-2 release and image information

The official release page identified **12.2** as stable/latest when checked on October 6, 2026. The version tag is **`12.2`**, not an invented `12.2.0`.

Official Docker Hub tag metadata returned:

```text
jellyfin/jellyfin:12.2@sha256:357724bf0ae27a672c7cbaa899db2d9abeb13dbd8657ccce750258a4c059d037
```

The JSON was saved to `/tmp/jellyfin-12.2-image.json`.

Relevant upstream instructions:

- Jellyfin 12 supports upgrading from 10.11.x.
- Remove repository-installed plugins before migration; install compatible builds afterward.
- Run a full library scan after migrating to restore alternate-version relationships.
- Jellyfin 12 uses .NET 10 and changes plugin APIs substantially.
- Deprecated API authentication mechanisms are disabled by default in 12; use current documented authorization methods for any API tooling.
- Database rollback requires compatible old data, not merely an old image.

Sources:

- [12.2 release](https://github.com/jellyfin/jellyfin/releases/tag/v12.2)
- [12.0 release and migration instructions](https://github.com/jellyfin/jellyfin/releases/tag/v12.0)
- [Migration/path guidance](https://jellyfin.org/docs/general/administration/migrate/)
- [Official container documentation](https://jellyfin.org/docs/general/installation/container/)
- [Renovate Docker versioning behavior](https://docs.renovatebot.com/modules/versioning/docker/)

Recheck upstream metadata if a substantial amount of time passes, but retain the requested target unless the user changes it.

## 11. Plugin inventory and verified upgrade candidates

All nine listed plugins loaded on official 10.11.11. Installed plugin metadata had previously reported `Active`. The following candidate versions were rechecked in upstream catalogs during stage-2 preparation:

| Plugin | Installed on 10.11.11 | Candidate | Target ABI |
| --- | --- | --- | --- |
| Fanart | 14.0.0.0 | 15.0.0.0 | 12.0.0.0 |
| Artwork | 2.0.0.0 | 3.0.0.0 | 12.0.0.0 |
| TheTVDB | 22.0.0.0 | 24.0.0.0 | 12.0.0.0 |
| AniDB | 11.0.0.0 | 13.0.0.0 | 12.0.0.0 |
| Webhook | 21.0.0.0 | 22.0.0.0 | 12.0.0.0 |
| Session Cleaner | 5.0.0.0 | 6.0.0.0 | 12.0.0.0 |
| Meilisearch | 1.11.1.15 | 1.12.1.4 | 12.0.0.0 |
| Intro Skipper | 1.10.11.24 | 12.0.4.0 | 12.0.0.0 |
| File Transformation | 3.0.1.0, 10.11 build | 3.0.1.0, **12.1 build** | 12.1.0.0 |

### File Transformation deserves special attention

The catalog has multiple builds with the same plugin version:

- `Release-12.0.0.zip`, target ABI `12.0.0.0`.
- `Release-12.1.0.zip`, target ABI `12.1.0.0`.

The planned candidate is the newer **12.1 build** for the 12.2 server. Published compatibility is not a runtime pass. Verify both actual package ABI and working web transformations. Do not leave the installed 10.11 build in place simply because it also says `3.0.1.0`.

### Catalog checksums from the fetched manifests

These are package checksums from upstream manifests, not checksums this agent computed over downloaded packages. **Package ZIPs have not been downloaded or verified in this session.**

| Candidate | Manifest checksum |
| --- | --- |
| Fanart 15.0.0.0 | `bbe8ea54bc956933b238388b0a78b9ce` |
| Artwork 3.0.0.0 | `8993c10376a1aba60748e7ac2913ccde` |
| TheTVDB 24.0.0.0 | `4ed207018366e6711ce6b5f440bcb18f` |
| AniDB 13.0.0.0 | `ee3a952012bc8a4c306fa45665dec9e7` |
| Webhook 22.0.0.0 | `1bb9033caa69ff54ef56cfa8669b5ac5` |
| Session Cleaner 6.0.0.0 | `3334bbd5e76e32d5f25d5476b03afa77` |
| Meilisearch 1.12.1.4 | `1491849543d4a588555371a767c61908` |
| Intro Skipper 12.0.4.0 | `de89ee9cf3e05d41bb02e584769ba1b0` |
| File Transformation 3.0.1.0, 12.1 build | `1451642C8DC6F036CB00AA703A9F0834` |

### Catalog locations

- Official: `https://repo.jellyfin.org/files/plugin/manifest.json`
- Meilisearch: `https://raw.githubusercontent.com/arnesacnussem/jellyfin-plugin-meilisearch/refs/heads/master/manifest.json`
- File Transformation: `https://www.iamparadox.dev/jellyfin/plugins/manifest.json`
- Intro Skipper: `https://intro-skipper.org/manifest.json`

**Intro Skipper is version-aware.** A guessed `master/manifest.json` GitHub raw URL returned 404. The current README specifies the hosted manifest and says it requires a Jellyfin version in the request. This worked:

```bash
curl -fsSL -A 'Jellyfin-Server/12.2' https://intro-skipper.org/manifest.json
```

The catalog also lists other plugins. Do not install those unrelated plugins.

Local cached catalog files:

```text
/tmp/jellyfin-official-plugins.json
/tmp/jellyfin-meilisearch-plugins.json
/tmp/jellyfin-paradox-plugins.json
/tmp/jellyfin-introskipper-plugins.json
```

The raw catalog values contain public download URLs. Use those catalog entries when installing, rather than guessing filenames.

## 12. On-disk plugin layout observed

Package directories under `/config/data/plugins`:

```text
Fanart_14.0.0.0
Artwork_2.0.0.0
TheTVDB_22.0.0.0
Intro Skipper_1.10.11.24
Meilisearch_1.11.1.15
File Transformation_3.0.1.0
Webhook_21.0.0.0
AniDB_11.0.0.0
Session Cleaner_5.0.0.0
```

An inspection to depth two showed assemblies, package metadata, logos, and some PDB/dependency files in these package directories. Configuration XML files are in the separate `plugins/configurations` directory. A `.jellyfin-plugin` marker was also present.

Do **not** delete or move the entire plugins directory. Do not delete plugin XML files, API keys in those XMLs, or Intro Skipper data. The depth-two inspection did not establish the complete location and integrity of all analysis data; verify it before asserting it is preserved.

The persistent data layout has a nested `/config/data/data` directory. It accounted for about 19 GiB during size inspection. Metadata occupied approximately 7.4 GiB, and cache about 575 MiB. Do not “correct” the nested data path based on assumptions about official-image defaults—the explicit paths preserve the existing installation.

## 13. Uncommitted stage-2 implementation already written

File: `kubernetes/apps/default/jellyfin/deploy.yaml`.

### Image change

The application image has been changed in the working tree to the verified 12.2 digest above.

### New init container

Name: `quarantine-jellyfin-10-plugins`.

- Uses the same official 12.2 image and digest.
- Inherits pod UID/GID 1000.
- Mounts only the existing config volume.
- Runs `/bin/sh -ec` before the application starts.
- Scans immediate plugin subdirectories containing `meta.json`.
- Matches a `targetAbi` beginning with `10.`.
- Moves those directories outside plugin discovery to `/config/plugin-binaries-pre12`.
- Refuses to overwrite a same-named directory already in quarantine.
- Leaves the separate configuration directory and all unrelated data in place.
- On later starts, 12.x packages should not match, including File Transformation's same-version replacement package.

Current script body:

```sh
plugins=/config/data/plugins
quarantine=/config/plugin-binaries-pre12
for package in "$plugins"/*; do
  [ -d "$package" ] || continue
  [ -f "$package/meta.json" ] || continue
  if grep -Eq '"targetAbi"[[:space:]]*:[[:space:]]*"10\.' "$package/meta.json"; then
    mkdir -p "$quarantine"
    name=${package##*/}
    if [ -e "$quarantine/$name" ]; then
      echo "Refusing to overwrite quarantined plugin: $name" >&2
      exit 1
    fi
    mv "$package" "$quarantine/$name"
    echo "Quarantined Jellyfin 10 plugin: $name"
  fi
done
```

### Why this approach was chosen

The user previously performed the commit/push/sync independently. Encoding plugin quarantine as an init container ensures a future sync cannot start the new server before moving known incompatible 10.x packages aside. It also avoids another manual maintenance pod and full backup transfer.

It does **not** automatically install replacement plugins or prove they work. The server's first migrated start is intentionally without these repository packages; compatible builds must be installed after migrations complete.

### Review/test work still required

The edit was interrupted immediately after it was written. Before deploying:

1. Confirm the exact image contains the shell/grep/mv tools used by the init container, or validate an equivalent reliable way.
2. Test against temporary fixtures, not production config:
   - 10.x package moves successfully.
   - Configuration XMLs and unrelated data remain unchanged.
   - Names containing spaces work.
   - 12.x packages stay in place.
   - File Transformation 3.0.1.0 with 12.1 ABI stays in place even though the name matches the old version.
   - A second run is safe.
   - A partial earlier run can continue for remaining packages.
   - Conflicting source/destination names cause a visible failure without overwriting data.
   - Missing/empty plugin directories are handled.
3. Decide whether malformed metadata or unexpected packages need an explicit failure check. Do not claim the current grep approach handles all future formats.
4. Render and validate manifests.
5. Update migration/transcoding documentation to reflect the current state and backup waiver.
6. Keep both image references consistent if changing the pinned version/digest.

No live plugin directories have been moved by this init container yet. There is no evidence from this session that a quarantine directory already exists; inspect rather than assume.

## 14. Concrete continuation sequence

### A. Reestablish context without repeating completed work

1. Read `AGENTS.md`, this handoff, and the actual current working tree.
2. Verify live image, readiness, auto-sync status, and current Git revision with filtered read-only queries.
3. Confirm no user changes supersede the unfinished stage-2 edit.
4. Do not restart the cancelled backup or ask again for its waiver.

### B. Finish the stage-2 repository change

1. Review and test the quarantine init container as described above.
2. Keep the application on the verified 12.2 image in the prepared Git change.
3. Preserve UID/GID, directories, GPU allocation, media mounts, resource limits and `Recreate`.
4. Keep automatic sync disabled.
5. Update `MIGRATION.md`:
   - Stage 1 is deployed and basic checks passed.
   - User reported successful Fladder playback.
   - Full backup attempt was cancelled and explicitly waived for this run.
   - Partial archives are not rollback points.
   - Init container replaces manual pre-migration package relocation for this implementation.
   - Stage-2 plugin package installs/functional validation/full scan are pending.
   - File Transformation target should specify the selected 12.1 ABI build.
6. Update `TRANSCODING-CONFIG.md` status and pod-selection commands as appropriate, without marking pending checks passed.
7. Validate:

   ```bash
   kustomize build kubernetes/apps/default/jellyfin > /tmp/jellyfin-stage2-rendered.yaml
   kubeconform -strict -ignore-missing-schemas -summary /tmp/jellyfin-stage2-rendered.yaml
   git diff --check
   ```

8. Present the concrete prepared change for the user's commit/push. Do not auto-stage, commit, or push.

### C. After the user's commit/push

1. Verify Argo CD sees the intended revision and auto-sync remains disabled.
2. Explicitly sync the Jellyfin Application within the already authorized upgrade scope.
3. Watch the quarantine init container and the actual server container.
4. Let database migrations finish without interruption. A short rollout timeout is a diagnostic event, not a reason to delete/restart the migrating pod.
5. Confirm correct existing data paths, completed migrations, health endpoint, and web client.
6. Do not mark the upgrade accepted just because the pod is Ready. The deployment currently has no application-level readiness probe, so query Jellyfin's HTTP health and logs as well.

### D. Restore plugin functionality after migration

1. Verify configured plugin repositories and install all nine compatible builds from the verified catalogs.
2. Use the Jellyfin UI/catalog or documented API with proper current authentication. No administrative token was acquired or API installation script prepared in this session.
3. Preserve existing plugin configuration and Intro Skipper analysis. Do not reset or reanalyze merely because the binary packages were reinstalled.
4. Restart only after migrations complete and when package installation requires it.
5. Verify loaded versions/ABIs; do not rely only on directory names or package version strings.
6. Run the required full library scan after providers are installed; allow it to complete.
7. Allow Meilisearch indexing to complete and verify representative searches.
8. Perform the acceptance checks below and record results honestly.

### E. If something fails

- Inspect init/server logs and application health before changing anything.
- Do not repeatedly kill a migrating server.
- Do not run 10.11.11 against a database already migrated to 12.x.
- Do not delete the existing PVC.
- Quarantined old plugin binaries are **not** a database backup.
- There is no verified local full rollback point from this session. Any rollback involving an older Longhorn backup requires separately assessing that backup and its consistency; do not pretend it is proven.
- Report a failing plugin as an acceptance blocker and investigate it. The user's backup waiver did not waive plugin functionality.

## 15. Acceptance checklist and current evidence

| Check | Current evidence / required next action |
| --- | --- |
| Official 10.11.11 stage-1 rollout | Passed |
| Correct persistent paths and identity | Passed on 10.11.11 |
| Desktop Fladder playback | User reported good results on 10.11.11 |
| Synthetic QSV encode / OpenCL initialization | Passed on 10.11.11 |
| Real HDR-to-SDR playback | Pending |
| 12.2 migration and readiness | Not started |
| Account/library count preservation | No baseline comparison completed; verify |
| Watched/resume-state preservation | Pending representative verification |
| Fanart | Loaded on 10.11.11; retrieve artwork after upgrade |
| Artwork | Loaded on 10.11.11; verify configured artwork behavior |
| TheTVDB | Loaded on 10.11.11; verify TV metadata retrieval |
| AniDB | Loaded on 10.11.11; verify anime metadata retrieval |
| Webhook | Loaded on 10.11.11; verify intended delivery to existing destinations |
| Session Cleaner | Loaded on 10.11.11; verify configured behavior without arbitrary settings changes |
| Meilisearch | Loaded on 10.11.11; verify indexing and search after migration |
| Intro Skipper | Loaded on 10.11.11; verify retained analysis and skip interaction |
| File Transformation | Loaded on 10.11.11; verify correct 12.1 ABI package and actual web enhancement behavior |
| Full post-upgrade library scan | Pending |
| Full stopped backup | Cancelled, incomplete, explicitly waived |
| Overall 12.2 acceptance | Not achieved |

## 16. Useful exact commands

Use these as references, adapting to current pod names and state. Do not print private credentials or unfiltered plugin configuration.

### Read-only status

```bash
kubectl get application jellyfin -n argocd -o json \
  | jq '{sync:.status.sync.status,health:.status.health.status,revision:.status.sync.revision,automated:.spec.syncPolicy.automated}'

kubectl get deployment jellyfin -n default -o json \
  | jq '{replicas:.spec.replicas,image:.spec.template.spec.containers[0].image,ready:.status.readyReplicas}'

kubectl get pods -n default -l app=jellyfin,component=server -o json \
  | jq '[.items[]|{name:.metadata.name,phase:.status.phase,containers:[.status.containerStatuses[]?|{name,ready,restartCount}]}]'
```

### Health and driver checks on the actual server

```bash
jf_pod=$(kubectl get pods -n default -l app=jellyfin,component=server \
  -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n default "$jf_pod" -c jellyfin -- curl -fsS --max-time 10 http://localhost:8096/health
kubectl exec -n default "$jf_pod" -c jellyfin -- id
kubectl exec -n default "$jf_pod" -c jellyfin -- /usr/lib/jellyfin-ffmpeg/vainfo --display drm --device /dev/dri/renderD128
```

### Previously successful synthetic tests

```bash
kubectl exec -n default "$jf_pod" -c jellyfin -- \
  /usr/lib/jellyfin-ffmpeg/ffmpeg -hide_banner -loglevel error \
  -init_hw_device vaapi=va:/dev/dri/renderD128 \
  -init_hw_device qsv=qs@va -filter_hw_device qs \
  -f lavfi -i testsrc2=size=1280x720:rate=30 \
  -vf 'format=nv12,hwupload=extra_hw_frames=64' \
  -c:v h264_qsv -frames:v 60 -f null -

kubectl exec -n default "$jf_pod" -c jellyfin -- \
  /usr/lib/jellyfin-ffmpeg/ffmpeg -hide_banner -loglevel error \
  -init_hw_device vaapi=va:/dev/dri/renderD128 \
  -init_hw_device opencl=ocl@va \
  -f lavfi -i color=size=64x64 -frames:v 1 -f null -
```

These are smoke tests, not substitutes for real playback and tone-mapping acceptance.

## 17. Tool/environment notes

- Shell: zsh.
- `kustomize`, `kubeconform`, `renovate-config-validator`, `node`, `docker`, and `python3` were available.
- Local Python did not have PyYAML installed at the time of checking.
- `yamllint` was not found in PATH.
- Cluster/network commands initially failed under the sandbox and succeeded with the tool's normal escalation mechanism.
- Schema downloads for kubeconform also required network access.
- Writable workspace roots were the repository and `/tmp`; creating the large backup under the home directory required tool-level escalation, which was used.
- Do not work around permission boundaries; use the normal tool escalation if needed.
- No secrets were printed intentionally or committed, and no authentication token for Jellyfin was established for later API work.
- No new permanent PVC, backup job, or cluster backup policy was created.

## 18. Recommended first response from the next LLM

A useful continuation would be: “I’ve read the handoff. Jellyfin is healthy on official 10.11.11, the backup waiver is recorded, and the 12.2 change is still uncommitted. I’ll finish testing the plugin-quarantine step and update the migration notes before your commit/push.”

Then do that work. Avoid re-explaining the entire backup discussion or claiming the upgrade is already complete.
