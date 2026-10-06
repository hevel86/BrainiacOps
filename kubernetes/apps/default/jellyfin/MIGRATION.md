# Jellyfin migration maintenance procedure

## Deployment gates

Stage 1 (LinuxServer 10.11.11 → official 10.11.11 at UID/GID 1000, existing directory layout) is **deployed** (commit `fcbb2f4`). Stage 2 (official 12.2) is **deployed** (commit `320b1bc`). Production runs Jellyfin 12.2.0. The upgrade is **not yet accepted**; see [Remaining work](#remaining-work).

Status on 2026-10-06:

- Stage 1 rolled out cleanly: correct digest, UID/GID 1000, expected data/config/cache/log/web/FFmpeg paths, all nine plugins loaded, `/health` Healthy, web client HTTP 200, `vainfo`/QSV/OpenCL smoke tests passed, zero restarts. Desktop playback through Fladder was reported good. Not yet verified: real HDR-to-SDR playback, account/library/watched-state comparison against a baseline, and plugin functional checks.
- **The stopped full backup was attempted, cancelled, and explicitly waived by the owner for this upgrade.** Partial archives left from the cancelled attempt are incomplete and are **not** rollback points. A Longhorn backup recorded on 2026-10-06 exists but has not been validated or confirmed to be crash-consistent with Jellyfin stopped. There is therefore no verified rollback point for stage 2.
- Stage 2 deployed 2026-10-06 (commit `320b1bc`). The init container quarantined all nine 10.11 plugin packages; all 39 database/code migrations applied with no errors; startup completed in 22 s; `/health` Healthy, web client HTTP 200, server reports 12.2.0, zero restarts. `vainfo`, the synthetic QSV encode and OpenCL initialization passed on 12.2. All four plugin repositories remain configured.
- Plugins (2026-10-06): eight of nine reinstalled from the catalogs at the target versions (all ABI 12.0.0.0) and loaded Active after a restart, with no load errors. Existing configuration was retained for all eight (Artwork's repository list was already empty before the upgrade). Intro Skipper converted its data to `introskipper-v2.db`; 27 of 40 randomly sampled episodes still have Intro/Outro/Recap media segments.
- **File Transformation is blocked upstream.** Its catalog serves builds per Jellyfin minor version and returns an empty list for 12.2 (latest 3.0.1.0 ships 10.11.11, 12.0 and 12.1 builds only). Do not hand-install the 12.1 build; install from the catalog once a 12.2 build is published (the 12.1 build appeared about 10 hours after Jellyfin 12.1).
- Full library scan completed in about 2 minutes. Episode count went from 5,670 to 5,658 because the scan regrouped 12 episodes as alternate versions (expected Jellyfin 12 behavior); it also removed one pathless virtual episode. Migration cleaned four stale `theme.mp3` entries. Movies (1,091), series (119), users (3) and libraries unchanged. Two `The Greatest Adventure Stories from the Bible` files (S01E07, S01E09; dated 2017) fail ffprobe and fingerprinting; they appear to be broken files rather than upgrade damage.
- Meilisearch reindexed 42,520 items; typo-tolerant search (for example `batmn beyond`) returns correct results.
- Read-only provider lookups passed: Fanart and TheTVDB return images, TheTVDB and AniDB remote series search return matches.
- Jellyfin took its own pre-migration `jellyfin.db` backup and deleted it after migrations succeeded, so it is not a rollback point.
- Still pending: File Transformation, Webhook delivery, Session Cleaner behavior, an Intro Skipper skip action during playback, real HDR-to-SDR playback, and representative watched/resume-state checks.

The user performs every Git operation. Keep `app.yaml` automatic sync disabled throughout and sync each stage explicitly after commit/push. Do not recreate any PVC or change endpoints or media paths.

References: [migration paths](https://jellyfin.org/docs/general/administration/migrate/), [12.0 upgrade instructions](https://github.com/jellyfin/jellyfin/releases/tag/v12.0), [12.2 release](https://github.com/jellyfin/jellyfin/releases/tag/v12.2).

## Stopped backup before each stage

> Waived for the stage-2 run on 2026-10-06 (see status above). Retained as the reference procedure for future upgrades.

1. Record the running image/digest and matching deployment configuration for rollback. Capture account/library counts, representative watched/resume state, plugin versions/settings and Intro Skipper analysis counts privately under `/tmp`. Record existing webhook destinations without exposing credentials. Ensure sufficient space for the entire config archive and a verification extraction.
2. Confirm `spec.syncPolicy.automated` is absent on the live Argo CD Application. During the maintenance window, scale only `deployment/jellyfin` to zero and wait for its server pod to terminate. This temporary maintenance scale is safe only while auto-sync/self-heal is disabled; do not sync or restart the server while backing up. Keep Meilisearch running and retain its PVC.
3. Mount the existing `jellyfin-config-lh` claim in a temporary maintenance pod with no Jellyfin process. Use GNU tar with numeric ownership, ACLs, extended attributes and permissions to archive **all** of `/config` (including hidden files, database sidecars, plugin configuration, cache and analysis data). Stream the archive to a private mode-0700 directory under `/tmp`, outside the pod and source PVC. For example, with the maintenance pod named `jellyfin-maintenance`:

   ```bash
   umask 077
   # Set jf_backup to a new, empty private directory for this stage.
   kubectl exec -n default jellyfin-maintenance -- tar --numeric-owner --acls --xattrs -cpf - -C /config . > "$jf_backup/config.tar"
   tar -tf "$jf_backup/config.tar" > "$jf_backup/archive-list.txt"
   sha256sum "$jf_backup/config.tar" > "$jf_backup/config.tar.sha256"
   ```

   Check every command's exit status. An archive listing or checksum alone is insufficient: extract to separate scratch storage with ownership/permissions preserved, compare file contents and metadata with the stopped source, and run SQLite integrity checks on the extracted databases using SQLite with the required extensions. Do not write integrity-check outputs or application data into Git. Retain a protected durable backup beyond local `/tmp` for the rollback retention period.
4. Record successful verification and the backup's corresponding image. Remove the maintenance pod to release its mount before syncing. A recorded Longhorn backup supplements this archive; it does not establish that this stopped backup was made or verified.

If backup creation or verification fails, do not switch images. Remove the maintenance pod and restore the original server replica count while automatic sync remains disabled.

## Stage 1: official image, same version (deployed)

After the user commits/pushes stage 1 and the stopped LinuxServer backup is verified:

```bash
argocd app sync jellyfin
kubectl rollout status -n default deployment/jellyfin --timeout=10m
argocd app wait jellyfin --sync --health --timeout 600
```

A wait timeout is a diagnostic signal, not permission to interrupt migrations. Confirm the running image digest, effective UID/GID and startup paths. Stop if Jellyfin presents a new-server setup wizard or missing libraries. Check web enhancements against the official web path; do not copy LinuxServer's web directory over the image's bundled client.

Complete every check below on 10.11.11 before preparing stage 2. Record results privately, including before/after counts and observed behavior. Keep the stage-1 archive until the entire upgrade is accepted.

## Stage 2: official 12.2 (deployed)

1. `deploy.yaml` pins `jellyfin/jellyfin:12.2@sha256:357724bf…d037` (verified against Docker Hub on 2026-10-06) for both the server and the init container below. All other stage-1 settings are unchanged; auto-sync stays disabled. The user commits/pushes this change.
2. Plugin quarantine is automated by the `quarantine-jellyfin-10-plugins` init container instead of a manual maintenance pod. Before the server starts, it moves every package directory under `/config/data/plugins` whose `meta.json` has a `targetAbi` beginning with `10.` to `/config/plugin-binaries-pre12` (outside plugin discovery). It leaves `plugins/configurations`, the `.jellyfin-plugin` marker, Intro Skipper data and all other data in place; logs every kept package and warns about packages without `meta.json` or `targetAbi`; refuses (exit 1, pod stays in `Init`) to overwrite an existing quarantined directory of the same name; and is a no-op on later starts. Packages with a 12.x ABI, including File Transformation 3.0.1.0's 12.1 build in the same-named directory, are kept. Tested against fixtures in the pinned 12.2 image as UID 1000, including a replica of the live nine-package layout. Quarantined binaries are not a database backup.
3. Explicitly sync and allow migrations to finish without interruption:

   ```bash
   argocd app sync jellyfin
   jf_pod=$(kubectl get pods -n default -l app=jellyfin,component=server -o jsonpath='{.items[0].metadata.name}')
   kubectl logs -n default "$jf_pod" -c quarantine-jellyfin-10-plugins
   kubectl logs -n default "$jf_pod" -c jellyfin -f
   ```

   The deployment has no readiness probe, so a Ready pod does not mean migrations are complete; check the logs and `/health`. Do not add a short liveness deadline or delete the pod mid-migration.
4. Install the following compatible packages through Jellyfin's catalog after verifying each package's current target ABI and checksum. These are upgrade candidates from the migration plan, not runtime-approved builds. Retain configured repositories and secrets. Restart only when migrations finish and the plugin installer requires it.

| Plugin | Stage-1 installed | Stage-2 target | Required functional check | Status (2026-10-06) |
| --- | --- | --- | --- | --- |
| Fanart | 14.0.0.0 | 15.0.0.0 | Retrieve artwork for a test item | Installed; remote image lookup returns Fanart images |
| Artwork | 2.0.0.0 | 3.0.0.0 | Retrieve configured artwork | Installed; no artwork repositories configured (also empty before upgrade) |
| TheTVDB | 22.0.0.0 | 24.0.0.0 | Retrieve TV metadata | Installed; remote series search and image lookup pass |
| AniDB | 11.0.0.0 | 13.0.0.0 | Retrieve anime metadata | Installed; remote series search passes |
| Webhook | 21.0.0.0 | 22.0.0.0 | Confirm delivery to existing destinations | Installed; one generic destination retained; delivery **pending** |
| Session Cleaner | 5.0.0.0 | 6.0.0.0 | Confirm configured schedule and cleanup behavior | Installed; `Days` setting retained; behavior **pending** |
| Meilisearch | 1.11.1.15 | 1.12.1.4 | Index completes; known-title search returns correct results | Passed (42,520 items; typo search works) |
| Intro Skipper | 1.10.11.24 | 12.0.4.0 | Analysis retained; skip action works on a known episode | Analysis retained; skip action in playback **pending** |
| File Transformation | 3.0.1.0 (10.11 build) | 3.0.1.0, `Release-12.1.0` build (target ABI 12.1.0.0) | Correct ABI; web transformations work without errors | **Blocked**: no 12.2 build published yet |

Catalogs: [official](https://repo.jellyfin.org/files/plugin/manifest.json), [Meilisearch](https://raw.githubusercontent.com/arnesacnussem/jellyfin-plugin-meilisearch/refs/heads/master/manifest.json), [Intro Skipper](https://intro-skipper.org/manifest.json) (version-aware; requests need a Jellyfin user agent such as `Jellyfin-Server/12.2`), [File Transformation](https://www.iamparadox.dev/jellyfin/plugins/manifest.json). File Transformation's version string alone cannot distinguish the builds; the catalog also lists a `Release-12.0.0` build, so verify the installed package's `targetAbi` is 12.1.0.0. Its published support through 12.1 does not prove compatibility with 12.2; failure blocks acceptance.

5. After metadata providers are reinstalled, run the required full library scan and allow it and Meilisearch indexing to finish. Verify retained Intro Skipper analysis before scheduling any reanalysis. Repeat the entire acceptance checklist.

## Acceptance after each stage

Stage-2 state as of 2026-10-06:

- [x] Argo CD Synced/Healthy; expected image/digest; ready server pod, zero restarts so far. (Recheck during playback tests.)
- [x] Startup/migration logs show completion, correct existing data paths and no database/plugin load errors.
- [ ] Existing accounts can log in; account/library counts, media accessibility, watched status and resume state match the baseline. Counts verified (see status); login and watched/resume state **pending**.
- [ ] Direct playback, QSV transcoding, HDR-to-SDR tone mapping and seeking pass [transcoding verification](TRANSCODING-CONFIG.md). Synthetic QSV/OpenCL passed; real playback **pending**.
- [ ] All nine plugins are loaded and pass their functional checks above. 8/9 loaded; File Transformation blocked; Webhook, Session Cleaner and Intro Skipper playback checks pending.
- [x] Stage 2 only: full library scan and Meilisearch indexing finish successfully.
- [ ] Backups remain available and verified until final acceptance. Waived for stage 2.

Any failing plugin blocks upgrade acceptance.

## Remaining work

1. **File Transformation.** Check whether a 12.2 build exists, then install it from Dashboard → Plugins → Catalog and verify its `targetAbi` and web transformations:

   ```bash
   curl -fsSL -A 'Jellyfin-Server/12.2.0' https://www.iamparadox.dev/jellyfin/plugins/manifest.json \
     | jq -r '.[]|select(.name=="File Transformation")|.versions[]|"\(.version) \(.targetAbi)"'
   ```

   An empty result means no 12.2 build has been published yet.
2. **Owner checks with a real client:** HDR-to-SDR transcode on an SDR client, Intro Skipper skip button on an analyzed episode, watched/resume state, Webhook delivery to the existing destination, and Session Cleaner's scheduled run.
3. **Cleanup after acceptance** (a Git change plus one in-cluster deletion):
   - Remove the `quarantine-jellyfin-10-plugins` init container from `deploy.yaml`. It is a no-op now and duplicates the image digest that Renovate must keep in sync.
   - Delete `/config/plugin-binaries-pre12` from the config volume (not managed by Git).
   - Optionally add `fsGroupChangePolicy: OnRootMismatch` to the pod `securityContext`; without it, each pod replacement recursively re-owns the 100 GiB config volume and can sit in `ContainerCreating` for a while.
   - Delete the incomplete local backup archives under `~/backups/jellyfin-official-10.11.11-20261006/` on the workstation used for the cancelled backup (about 8.5 GiB, sensitive, not a rollback point).
4. **Optional investigation:** the two unreadable `The Greatest Adventure Stories from the Bible` files (S01E07, S01E09), and the ASP.NET data-protection warnings at startup (also present on 10.11).

## Rollback

For stage 2 no verified stopped archive exists (backup waived), so the procedure below cannot currently be followed as written. Any rollback would first require assessing the Longhorn backup's age and consistency.

Stop the server with automatic sync still disabled and wait for termination. Mount the same retained PVC in the maintenance pod. Preserve the failed state separately for diagnosis, then restore the **entire** verified archive into an empty config directory on that PVC, preserving numeric owners, permissions, ACLs and extended attributes. Do not overlay an old database onto migrated files, leave migrated sidecars behind, or replace the PVC.

Restore the matching prior deployment in Git (LinuxServer configuration for stage 1; official 10.11.11 configuration for stage 2). The user commits/pushes. Remove the maintenance pod, sync the matching image/configuration, then repeat readiness and data/playback checks. Never start 10.11 against a 12.x database; restoring the image alone is not rollback.
