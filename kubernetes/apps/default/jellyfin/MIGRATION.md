# Jellyfin migration maintenance procedure

## Deployment gates

Stage 1 is prepared in Git: LinuxServer 10.11.11 → official 10.11.11 at UID/GID 1000, with the existing directory layout. Stage 2 targets official 12.2 and must be prepared as a separate change only after stage 1 passes every acceptance check. Do not combine image migration and database upgrade in one sync.

Preflight on 2026-10-06: production was healthy on LinuxServer 10.11.11; Argo CD was Synced/Healthy with automatic sync disabled; nine installed plugin manifests reported Active. This is not functional validation. No stopped backup or rollout has yet been performed.

The user performs every Git operation. Commit and push each prepared stage, then explicitly sync only after its stopped backup is verified. Keep `app.yaml` automatic sync disabled throughout. Do not recreate any PVC or change endpoints or media paths.

References: [migration paths](https://jellyfin.org/docs/general/administration/migrate/), [12.0 upgrade instructions](https://github.com/jellyfin/jellyfin/releases/tag/v12.0), [12.2 release](https://github.com/jellyfin/jellyfin/releases/tag/v12.2).

## Stopped backup before each stage

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

## Stage 1: official image, same version

After the user commits/pushes stage 1 and the stopped LinuxServer backup is verified:

```bash
argocd app sync jellyfin
kubectl rollout status -n default deployment/jellyfin --timeout=10m
argocd app wait jellyfin --sync --health --timeout 600
```

A wait timeout is a diagnostic signal, not permission to interrupt migrations. Confirm the running image digest, effective UID/GID and startup paths. Stop if Jellyfin presents a new-server setup wizard or missing libraries. Check web enhancements against the official web path; do not copy LinuxServer's web directory over the image's bundled client.

Complete every check below on 10.11.11 before preparing stage 2. Record results privately, including before/after counts and observed behavior. Keep the stage-1 archive until the entire upgrade is accepted.

## Stage 2: official 12.2

1. After stage-1 acceptance, prepare a separate `deploy.yaml` change to `jellyfin/jellyfin:12.2` with a freshly verified official registry digest. The user commits/pushes this change. Keep all other stage-1 settings and auto-sync disabled.
2. Repeat the stopped backup procedure, establishing the official-10.11.11 rollback point. Preserve configuration and analysis data. With the server still stopped, inventory plugin contents and move only installed plugin binary/package directories from `/config/data/plugins` to a quarantine directory **outside** plugin discovery (for example `/config/plugin-binaries-pre12`). Preserve `plugins/configurations`, data directories and analysis databases; inspect mixed-content package directories before moving anything. Never delete the whole plugins directory.
3. Remove the maintenance pod, explicitly sync, and allow migrations to finish without interruption. Do not add a short liveness deadline that would repeatedly kill the migration.
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
| File Transformation | 3.0.1.0 | 3.0.1.0, Jellyfin 12 build | Correct ABI; web transformations work without errors |

Catalogs: [official](https://repo.jellyfin.org/files/plugin/manifest.json), [Meilisearch](https://raw.githubusercontent.com/arnesacnussem/jellyfin-plugin-meilisearch/refs/heads/master/manifest.json), [Intro Skipper](https://github.com/intro-skipper/intro-skipper), [File Transformation](https://www.iamparadox.dev/jellyfin/plugins/manifest.json). File Transformation's version string alone cannot distinguish the builds. Its published support through 12.1 does not prove compatibility with 12.2; failure blocks acceptance.

5. After metadata providers are reinstalled, run the required full library scan and allow it and Meilisearch indexing to finish. Verify retained Intro Skipper analysis before scheduling any reanalysis. Repeat the entire acceptance checklist.

## Acceptance after each stage

- [ ] Argo CD Synced/Healthy; expected image/digest; ready server pod with stable restart count during playback and plugin tests.
- [ ] Startup/migration logs show completion, correct existing data paths and no database/plugin load errors.
- [ ] Existing accounts can log in; account/library counts, media accessibility, watched status and resume state match the baseline.
- [ ] Direct playback, QSV transcoding, HDR-to-SDR tone mapping and seeking pass [transcoding verification](TRANSCODING-CONFIG.md).
- [ ] All nine plugins are loaded and pass their functional checks above; preserved settings and analysis confirmed. Active package metadata alone is insufficient.
- [ ] Stage 2 only: full library scan and Meilisearch indexing finish successfully.
- [ ] Backups remain available and verified until final acceptance.

No stage has passed this checklist yet. Any failing plugin blocks upgrade acceptance.

## Rollback

Stop the server with automatic sync still disabled and wait for termination. Mount the same retained PVC in the maintenance pod. Preserve the failed state separately for diagnosis, then restore the **entire** verified archive into an empty config directory on that PVC, preserving numeric owners, permissions, ACLs and extended attributes. Do not overlay an old database onto migrated files, leave migrated sidecars behind, or replace the PVC.

Restore the matching prior deployment in Git (LinuxServer configuration for stage 1; official 10.11.11 configuration for stage 2). The user commits/pushes. Remove the maintenance pod, sync the matching image/configuration, then repeat readiness and data/playback checks. Never start 10.11 against a 12.x database; restoring the image alone is not rollback.
