# LinuxServer image-provider migration — 2026-11-19

> **Follow-up:** Nextcloud was subsequently migrated to official 33.0.11 with live PHP 8.4.28 verification. The overall total is now 10 migrated workloads, with Sonarr, Mylar3 and Azahar unchanged. See `nextcloud-official-migration-2026-11-20.md`. The original snapshot below is retained as historical evidence; its Nextcloud exception is resolved.

## Result

9 of 13 workloads are cut over. Four remain on LinuxServer for the concrete exceptions below. This is not a claim that the entire LinuxServer migration is complete.

The final live inventory found all 13 Deployments ready, all owning Argo applications Synced/Healthy, and zero restarts in their active pods. The nine migrated workloads retain their existing application releases, claim identities and data paths. No custom image, Dockerfile, build pipeline, shared-media ownership rewrite or networking-controller rollout was introduced.

Verification snapshot (UTC): 2026-11-19T23:31:52.123512+00:00

## Migrated workloads

| Workload | Pinned replacement image |
|---|---|
| tautulli | `ghcr.io/home-operations/tautulli:2.18.2@sha256:d7ea1a79cf8cc2603890287d7c0e5bc277e4909c1df93f48f000833d2771eca0` |
| bazarr | `ghcr.io/home-operations/bazarr:1.5.6@sha256:80cb090162b47ea1bfb499d742b45a460b282f17ffefa4c01d518a5c8d52a5a4` |
| sabnzbd | `ghcr.io/home-operations/sabnzbd:5.1.3@sha256:07790a7829201d9ea302e8b862078beac4b1a07003fe8359e3f069b6bcd84a95` |
| transmission | `ghcr.io/home-operations/transmission:4.1.4@sha256:4d7179443512c84e564e2c8c5e5f17b0db069f63a48eded5f0e371f7429a7463` |
| plex | `ghcr.io/home-operations/plex:1.43.5.11079@sha256:06ef0fc23e9af9bbaf284c3f27972f94e703d13d6f745edeb6818fcbebf6c673` |
| syncthing | `docker.io/syncthing/syncthing:2.1.7@sha256:2b71da7c0d0a91a6ae5285ad079226fecc0a365d08b27720e1f7037b018f7546` |
| radarr | `ghcr.io/home-operations/radarr:6.3.0.10514@sha256:ca30ff27d24c1fd548b1c8efd684b6a9238b7fed2bd5b834ea700aa09c16fe11` |
| prowlarr | `ghcr.io/home-operations/prowlarr:2.3.0.5236@sha256:1a8a4b11972b2e62671b49949c622b8cb1110e2b5c77199ac795a6d79fe106e8` |
| nextcloud-mariadb | `docker.io/library/mariadb:11.8.9@sha256:d36f18d65a0459510b8b0f643b226a6d299e3206486e2b64ff20754a6d291707` |

## Runtime acceptance evidence

- **Tautulli:** same 2.18.2 release, status endpoint passed, existing authentication loaded, Plex discovery/stream monitoring started; authenticated history totals were not independently verified.
- **Bazarr:** authenticated health/integration checks passed, with 1,063 movies and 127 series observed at its cutover. Original media paths retained.
- **SABnzbd:** same 5.1.3 release and authenticated queue check passed.
- **Transmission:** authenticated RPC passed with all nine existing torrents retained and seeding; existing RPC authentication and settings preserved.
- **Plex:** exact full release 1.43.5.11079-b3b13e506 and server identity hash retained, four libraries with 1,116 movie items and 119 show items. A bounded own-session HLS test returned a playlist and segment and reported VAAPI decoding, VAAPI encoding and full hardware pipeline. Only that test session was stopped and its absence verified. Existing scratch target remains `/scratch`.
- **Syncthing:** exact v2.1.7 and device identity hash retained, seven folders, four devices, 13,940 local/global files and no folder errors. Peers were offline both before and after, so actual device-to-device transfer was not exercised.
- **Radarr:** exact 6.3.0.10514 and master branch retained; authenticated API key identity, 1,106 movies, 9,103 history records and two download clients matched before/after.
- **Prowlarr:** exact 2.3.0.5236 and master branch retained; authenticated API key identity, eight indexers, three application integrations and two download clients matched. Its three pre-existing health-check sources remained: IndexerLongTermStatusCheck, IndexerNoDefinitionCheck and UpdateCheck. Those were not introduced or repaired by this packaging change.
- **MariaDB:** exact upstream 11.8.9 retained (the server now adds the official Ubuntu packaging suffix). Authenticated Nextcloud database access passed, all 133 application tables remained, and compared isolation, charset/collation, SQL mode, binlog/log paths, page/log sizes, encryption state, case sensitivity, packet limit, DNS resolution and host cache settings matched. Only expected package version/locale/plugin-directory strings differed. The database stayed under `/config/databases`, UID/GID1000, without chown or automatic upgrade. A fresh mode-0600 logical Nextcloud dump was created on the existing database PVC before cutover; this supplements existing off-volume backups and is not a restore test. Nextcloud's web Deployment UID, generation and pod template were unchanged. Its status and login page returned HTTP200, installed=true, maintenance=false and needsDbUpgrade=false.

The database compatibility ConfigMap contains public stock settings compared privately against the live file. No private configuration, credential values, SQL dump, identity hashes or internal volume identifiers are included in this report.

## Stable-channel update policy

Home Operations Radarr/Prowlarr packaging advertises develop. Both now explicitly set their update branch to master and mount a read-only package-info ConfigMap retaining original package metadata except Branch=master. Runtime APIs confirmed master after startup.

Renovate permits reviewed digest-refresh PRs at the verified exact application versions, with automerge disabled. Application version bumps are intentionally held for manual stable-release verification. A future approved upgrade must update the image tag/digest, package-info PackageVersion and allowedVersions rule together. This is not unrestricted automatic stable-stream tracking. See each app's IMAGE-MIGRATION.md.

## Unchanged exceptions

| Workload | Concrete reason |
|---|---|
| Sonarr | Live application is 4.0.20.3014. The Home Operations alias 4.0.20 packages 4.0.20.3012, which is a downgrade. A final registry check for exact 4.0.20.3014 returned HTTP404. No downgrade or channel change was authorized. |
| Nextcloud web | Exact 33.0.5 official apache, fpm and fpm-alpine variants all bundle PHP8.4.22. This predates the PHP8.4.27 upstream critical-security fix. Existing image CLI reports PHP8.4.16; distro backports were not assessed. Existing PHP mitigations remain intact, but should not be confused with a complete upstream patch. Moving to a suitable patched official image needs an approved maintenance-version upgrade plus the known webroot/custom-app, UID, PHP, cron and TLS-routing conversion. Its database migration is already complete independently. |
| Mylar3 | No maintained matching official/Home Operations image was verified; upstream recommends LinuxServer. Keep unchanged pending an approved alternative publisher or replacement decision. |
| Azahar | The available room-server image does not replace the existing browser-streamed Selkies/GPU emulator UI. Keep unchanged pending a suitable maintained alternative or application-replacement decision. |

PHP primary advisory: https://github.com/php/php-src/security/advisories/GHSA-6wmf-4rv5-p3rp (CVE-2026-109619), whose PHP8.4 entry lists 8.4.27 as the patched version. All three assessed official Nextcloud33.0.5 image configs were fetched directly from their immutable registry manifests and report PHP8.4.22.

## Recovery and publication

Each application change was committed, pushed, read back from GitHub, and selectively synced through its owning Argo application at the verified commit with pruning disabled. Strict native-resource schema validation and migration contract checks passed before rollout. The final database cutover commit is `fffb203ea6ba8833f94c886c8e24a39422d491a9`; its GitHub kubeconform check completed successfully.

The pre-cutover annotated Git tag `pre-homeops-migration-2026-11-19` remains the configuration rollback checkpoint. It is not an application-data backup. Use reviewed per-workload Git reverts and targeted Argo syncs rather than force-pushing shared history; use the appropriate retained data recovery point if a rollback requires it. Preserve the original PVCs and existing recovery backups.

## Decisions still needed

Prioritize an approved Nextcloud maintenance-version upgrade to obtain a patched official runtime, followed by its coordinated layout/web-server cutover. Leave Sonarr unchanged rather than downgrade; an application upgrade would require explicit approval. Leave Mylar3/Azahar as explicit LinuxServer exceptions unless a suitable approved publisher or replacement is chosen.
