# Jellyfin 12.2 upgrade: session handoff

**Last updated:** 2026-10-06, America/New_York\
**Purpose:** Let a new LLM session continue the Jellyfin upgrade without repeating completed work.

## 1. Current state

Production runs **official `jellyfin/jellyfin:12.2`** (digest-pinned in `kubernetes/apps/default/jellyfin/deploy.yaml`). Both migration stages are deployed; the upgrade is **not yet accepted**.

**Source of truth for status, results and remaining work:** [`kubernetes/apps/default/jellyfin/MIGRATION.md`](../kubernetes/apps/default/jellyfin/MIGRATION.md), especially its *Status*, plugin table, *Acceptance* and *Remaining work* sections. Read it before doing anything. This handoff only adds context that does not belong there.

Summary of what is done:

- Stage 1 (LinuxServer → official 10.11.11) deployed in `fcbb2f4`.
- Stage 2 (official 12.2 + plugin-quarantine init container) deployed in `320b1bc`. All 39 database/code migrations succeeded; startup took 22 s.
- 8 of 9 plugins reinstalled at 12.x builds, loaded Active, settings retained.
- Full library scan and Meilisearch reindex completed.

What is left (details in `MIGRATION.md` → *Remaining work*):

1. Install **File Transformation** once its author publishes a 12.2 build (blocked upstream as of 2026-10-06).
2. Owner playback/behavior checks: HDR-to-SDR, Intro Skipper skip button, watched/resume state, Webhook delivery, Session Cleaner.
3. Post-acceptance cleanup: remove the init container, delete `/config/plugin-binaries-pre12`, optionally add `fsGroupChangePolicy: OnRootMismatch`.

## 2. Decisions already made by the owner

- **The full stopped backup was waived** for this upgrade after a cancelled attempt. Do not ask again. There is no verified rollback point; never run 10.11 against the migrated 12.x database.
- **Plugin functionality was not waived.** All nine plugins remain acceptance requirements.
- **Do not hand-install File Transformation's 12.1 build** on 12.2. Wait for the catalog to offer a 12.2 build.
- The owner performs **all Git operations**. Never stage, commit or push. Argo CD auto-sync for `jellyfin` is intentionally disabled; after the owner pushes, sync explicitly (`argocd app sync jellyfin`).

## 3. Operational lessons

- **Select the server pod explicitly.** Meilisearch shares the `app: jellyfin` label, so `kubectl exec/logs deployment/jellyfin` can land on the wrong pod:

  ```bash
  jf_pod=$(kubectl get pods -n default -l app=jellyfin,component=server -o jsonpath='{.items[0].metadata.name}')
  kubectl logs -n default "$jf_pod" -c jellyfin
  ```

- **API access.** Jellyfin 12 disables legacy auth. Use an API key (Dashboard → API Keys) from inside the pod:

  ```bash
  kubectl exec -n default "$jf_pod" -c jellyfin -- curl -fsS \
    -H "Authorization: MediaBrowser Token=\"$JF_API_KEY\"" http://localhost:8096/Plugins
  ```

  The owner provides the key per session; it is rotated and must never be written to the repository. Useful endpoints: `/Plugins`, `/Plugins/{id}/Configuration` (print keys, not values), `/System/Info`, `/System/Restart` (check `/Sessions` for active playback first), `/ScheduledTasks`, `/Items/Counts`, `/MediaSegments/{itemId}`.
- **Plugin catalogs filter by server version.** Intro Skipper and File Transformation return different (or empty) manifests depending on the `Jellyfin-Server/<version>` user agent. Query with `-A 'Jellyfin-Server/12.2.0'` to see what the server sees.
- **Plugin restarts.** Catalog installs show status `Restart` until Jellyfin restarts; a dashboard/API restart is in-process and does not replace the pod.
- **Pod replacement is slow** without `fsGroupChangePolicy: OnRootMismatch` because Kubernetes re-owns the 100 GiB config volume.
- **Expected count change.** Episode count dropped 5,670 → 5,658 because the 12.x scan regrouped 12 alternate versions. This is not data loss.
- **zsh does not word-split** unquoted variables; use `${=var}` or a `while read` loop when iterating over IDs.

## 4. Local artifacts (workstation only, not in Git)

- `~/backups/jellyfin-official-10.11.11-20261006/`: partial, unverified archives from the cancelled backup (about 8.5 GiB, sensitive). Not a rollback point; delete when convenient.
- Scratch files under `/tmp` from earlier sessions are disposable; nothing remaining depends on them.
- On the config volume: `/config/plugin-binaries-pre12` holds the nine quarantined 10.11 plugin packages. They are not a database backup.

## 5. Suggested opening for the next session

> Read `docs/jellyfin-upgrade-handoff-2026-10-06.md` and `kubernetes/apps/default/jellyfin/MIGRATION.md`, verify live Jellyfin state read-only, then continue with *Remaining work*: check whether File Transformation has a 12.2 build.
