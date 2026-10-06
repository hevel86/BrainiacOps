# Jellyfin migration maintenance procedure

## Deployment gates

Stage 1 (LinuxServer 10.11.11 → official 10.11.11 at UID/GID 1000, existing directory layout) is **deployed** (commit `fcbb2f4`). Stage 2 (official 12.2) is prepared in `deploy.yaml` as a separate change. Do not combine image migration and database upgrade in one sync.

Status on 2026-10-06:

- Stage 1 rolled out cleanly: correct digest, UID/GID 1000, expected data/config/cache/log/web/FFmpeg paths, all nine plugins loaded, `/health` Healthy, web client HTTP 200, `vainfo`/QSV/OpenCL smoke tests passed, zero restarts. Desktop playback through Fladder was reported good. Not yet verified: real HDR-to-SDR playback, account/library/watched-state comparison against a baseline, and plugin functional checks.
- **The stopped full backup was attempted, cancelled, and explicitly waived by the owner for this upgrade.** Partial archives left from the cancelled attempt are incomplete and are **not** rollback points. A Longhorn backup recorded on 2026-10-06 exists but has not been validated or confirmed to be crash-consistent with Jellyfin stopped. There is therefore no verified rollback point for stage 2.
- Stage 2 deployed 2026-10-06 (commit `320b1bc`). The init container quarantined all nine 10.11 plugin packages; all 39 database/code migrations applied with no errors; startup completed in 22 s; `/health` Healthy, web client HTTP 200, server reports 12.2.0, zero restarts. `vainfo`, the synthetic QSV encode and OpenCL initialization passed on 12.2. All four plugin repositories remain configured.
- Remaining for acceptance: install the nine 12.x plugin builds, run the full library scan and Meilisearch indexing, then the functional/playback checks below.

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

## Stage 2: official 12.2

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

| Plugin | Stage-1 installed | Stage-2 candidate | Required functional check |
| --- | --- | --- | --- |
| Fanart | 14.0.0.0 | 15.0.0.0 | Retrieve artwork for a test item |
| Artwork | 2.0.0.0 | 3.0.0.0 | Retrieve configured artwork |
| TheTVDB | 22.0.0.0 | 24.0.0.0 | Retrieve TV metadata |
| AniDB | 11.0.0.0 | 13.0.0.0 | Retrieve anime metadata |
| Webhook | 21.0.0.0 | 22.0.0.0 | Confirm delivery to existing destinations |
| Session Cleaner | 5.0.0.0 | 6.0.0.0 | Confirm configured schedule and cleanup behavior |
| Meilisearch | 1.11.1.15 | 1.12.1.4 | Index completes; known-title search returns correct results |
| Intro Skipper | 1.10.11.24 | 12.0.4.0 | Analysis retained; skip action works on a known episode |
| File Transformation | 3.0.1.0 (10.11 build) | 3.0.1.0, `Release-12.1.0` build (target ABI 12.1.0.0) | Correct ABI; web transformations work without errors |

Catalogs: [official](https://repo.jellyfin.org/files/plugin/manifest.json), [Meilisearch](https://raw.githubusercontent.com/arnesacnussem/jellyfin-plugin-meilisearch/refs/heads/master/manifest.json), [Intro Skipper](https://intro-skipper.org/manifest.json) (version-aware; requests need a Jellyfin user agent such as `Jellyfin-Server/12.2`), [File Transformation](https://www.iamparadox.dev/jellyfin/plugins/manifest.json). File Transformation's version string alone cannot distinguish the builds; the catalog also lists a `Release-12.0.0` build, so verify the installed package's `targetAbi` is 12.1.0.0. Its published support through 12.1 does not prove compatibility with 12.2; failure blocks acceptance.

5. After metadata providers are reinstalled, run the required full library scan and allow it and Meilisearch indexing to finish. Verify retained Intro Skipper analysis before scheduling any reanalysis. Repeat the entire acceptance checklist.

## Acceptance after each stage

- [ ] Argo CD Synced/Healthy; expected image/digest; ready server pod with stable restart count during playback and plugin tests.
- [ ] Startup/migration logs show completion, correct existing data paths and no database/plugin load errors.
- [ ] Existing accounts can log in; account/library counts, media accessibility, watched status and resume state match the baseline.
- [ ] Direct playback, QSV transcoding, HDR-to-SDR tone mapping and seeking pass [transcoding verification](TRANSCODING-CONFIG.md).
- [ ] All nine plugins are loaded and pass their functional checks above; preserved settings and analysis confirmed. Active package metadata alone is insufficient.
- [ ] Stage 2 only: full library scan and Meilisearch indexing finish successfully.
- [ ] Backups remain available and verified until final acceptance. (Waived for stage 2; see status.)

No stage has fully passed this checklist yet. Any failing plugin blocks upgrade acceptance.

## Rollback

For stage 2 no verified stopped archive exists (backup waived), so the procedure below cannot currently be followed as written. Any rollback would first require assessing the Longhorn backup's age and consistency.

Stop the server with automatic sync still disabled and wait for termination. Mount the same retained PVC in the maintenance pod. Preserve the failed state separately for diagnosis, then restore the **entire** verified archive into an empty config directory on that PVC, preserving numeric owners, permissions, ACLs and extended attributes. Do not overlay an old database onto migrated files, leave migrated sidecars behind, or replace the PVC.

Restore the matching prior deployment in Git (LinuxServer configuration for stage 1; official 10.11.11 configuration for stage 2). The user commits/pushes. Remove the maintenance pod, sync the matching image/configuration, then repeat readiness and data/playback checks. Never start 10.11 against a 12.x database; restoring the image alone is not rollback.
