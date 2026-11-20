# Nextcloud official-image migration — completed

Verified UTC: 2026-11-20T02:16:46.012401+00:00

## Live result

- Nextcloud upgraded from33.0.5 to **33.0.11** (internal version33.0.11.2).
- Official Nextcloud FPM and NGINX images, immutable digests; no custom builds.
- Actual running PHP-FPM workers—not just image metadata—report **PHP8.4.28**, fpm-fcgi, UID1000, session.upload_progress.enabled0 and admin memory_limit-1. APCu and PDO MySQL are loaded; upload/post limits remain100G.
- The upgrade init completed successfully. installed=true, maintenance=false, needsDbUpgrade=false.
- Argo application nextcloud is Synced/Healthy, with all three containers ready and zero restarts at verification.
- Original config/data/database PVC identities remain unchanged. The MariaDB deployment was not changed/restarted by this web migration. Existing HTTPS route and Service443 remain unchanged.

## Data and functionality checks

- Preserved **1 user**, **106 user-home filecache entries**, **1 share**, and the complete **47-app enabled set**.
- Instance ID, secret, salt and existing public-share token matched their private pre-upgrade hashes; no values or hashes are published here.
- Existing public-share page returns200 and is nonempty. Login page returns200. Background mode remains cron, and an actual cron cycle succeeded.
- Total filecache entries changed from181 to178; the difference is outside the unchanged user-home entry count. These are cache metadata entries, including directories—not an independent full-content hash of every file. The specific non-home cache removals were not individually identified.
- CSS and JavaScript assets return200 with correct MIME types. CalDAV/CardDAV discovery returns301 without leaking internal8443. Unauthenticated DAV returns the expected401.
- Private config/data/lib/dotenv/dependency metadata paths return404. The FPM runtime-verification endpoint is not exposed through public HTTPS.
- The public hostname cloud.torquasmvo.com returns200 with Nextcloud33.0.11 and valid TLS from the in-cluster test vantage, using a normal browser user agent. Cloudflare rejects the bare Python user agent with403; no WAF settings were changed.

Password-based user login, a new upload, authenticated DAV content operations, large-upload load testing and full backup restoration were not exercised. They require an authorized user session or a separate recovery rehearsal; no new user credentials were created for testing.

## Recovery checkpoints

- Verified annotated configuration tag: `pre-nextcloud-official-33.0.11`.
- The old web app was fully stopped through a GitOps commit before taking a fresh successful logical database dump.
- Three new retained storage checkpoints—config, data and database—were observed readyToUse before the upgrade started. The database storage checkpoint is an online database snapshot supplemented by the quiesced logical dump, not a claim of tested restoration.
- Original legacy files remain under /config/www/nextcloud. The new persistent configuration namespace is /config/official-nextcloud; core is reproducible in an ephemeral volume.
- A private recovery receipt is retained by Hermes. SQL dumps remain mode0600 on the existing database PVC; no SQL or credentials are in Git or this report.
- A database/schema upgrade must not be rolled back merely by changing the image. Use the coordinated pre-upgrade database/config/data recovery points and reviewed GitOps state. Destructive restoration still requires the appropriate approval.

## Publication and future maintenance

Migration commit: `b6c025c07c2d79b67d2726d4a8c0f6224bf49a63`. Its GitHub kubeconform check completed successfully. Two migration contract tests and strict validation of all11 rendered native resources passed. Real-image PHP/FPM configuration and TLS NGINX validation passed before deployment.

Renovate is constrained to reviewed Nextcloud33 FPM maintenance updates and NGINX1.30 Alpine patch updates, with immutable digests and automerge disabled. See kubernetes/apps/default/nextcloud/OFFICIAL-IMAGE-MIGRATION.md for the init, mounts, PHP, TLS, upload-cache, probes and cron lifecycle.

The original LinuxServer inventory now has **10 migrated workloads and3 unchanged**. Sonarr remains waiting for a suitable matching image; Mylar3 and Azahar are left alone as requested.
