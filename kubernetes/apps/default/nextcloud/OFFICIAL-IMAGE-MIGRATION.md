# Official Nextcloud image and upgrade lifecycle

The web app uses official Nextcloud 33.0.11 FPM with PHP8.4.28 and official NGINX1.30.7. All image references are immutable. MariaDB is managed separately and is not restarted by this web cutover.

## Persistent layout and identity

Both original claims remain: config at /config and user data at /data, UID/GID1000. Existing instance ID, secrets, salt, authentication configuration, and TLS certificate/key are preserved. The original /config/www/nextcloud installation is retained for recovery.

The first upgrade init copies legacy configuration and themes to /config/official-nextcloud and preserves only apps not bundled with the new release as custom_apps. New bundled apps come from the official core. The prepared marker prevents a retry from overwriting upgraded configuration with old configuration. Existing apps_paths were verified absent and no supplemental configuration existed before the cutover; the new public supplemental file defines exactly core and writable custom paths.

Core is regenerated in a 2Gi emptyDir on each Pod start. Persistent config/custom_apps/themes are symlinked from that shared core into the config PVC, at identical absolute paths in PHP, cron and NGINX. The init explicitly runs occ upgrade and requires success before web/cron start; a seeded version.php alone does not make the official entrypoint upgrade the database.

Only the roots of ephemeral core and NGINX tmp emptyDirs receive a nonrecursive chown. No PVC, user data or shared-media ownership rewrite is performed. Root initialization has no persistent mounts and no credentials.

## HTTPS, uploads and PHP hardening

The existing TLS-passthrough route and Service443 are unchanged. NGINX listens on8443, reuses /config/keys/cert.crt and cert.key, and passes external SERVER_PORT443/HTTPS to loopback FPM9000. Core/config mounts in NGINX are read-only. The NGINX config follows the official Nextcloud33 root-installation example, including DAV/well-known routing and private-path denies.

Existing PHP INI and FPM admin hardening files remain unchanged and are mounted at their official-image locations. APCu is enabled for CLI to support the preserved cache configuration. PHP upload/post limits100G and execution/input times0/-1 match the old base-image settings; nginx retains client_max_body_size0 and client_body_timeout300s. Active-worker limits of the old container were not directly inspected.

Current official guidance buffers FastCGI request bodies. To avoid a small node-local tmp limit, NGINX has access only to a dedicated /data/.nginx-upload-cache subPath for upload buffering, not the rest of the user-data tree. Temporary uploads therefore consume existing data-volume free space; they do not allocate a new PVC. NGINX cleans ordinary request buffers as requests finish. Its PID and other small temp files use a separate64Mi emptyDir.

A loopback-only8080 endpoint reports actual FPM worker PHP version, UID, hardening and module availability. The cron sidecar verifies this before starting, logs the safe result, then runs PHP cron at approximately five-minute intervals with signal forwarding. It does not use the root-oriented image cron daemon.

## Updates and recovery

Renovate is restricted to Nextcloud33 FPM maintenance releases and NGINX1.30 Alpine patch releases, with reviewed immutable-digest PRs and no automerge. A future Nextcloud major upgrade requires explicit review. Subsequent Pod starts regenerate core and run occ upgrade against the preserved official configuration; legacy files are needed only for the initial preparation.

The migration quiesces the old web app through GitOps, takes a fresh logical database dump and retained config/data/database storage checkpoints, then starts the new stack. A database upgrade cannot be undone by merely switching back to the old image. Use the pre-upgrade database/config/data recovery points and a reviewed GitOps rollback if required; do not delete or replace the original claims.

Sources: official Nextcloud33 NGINX documentation and exact published image entrypoint/configuration. No custom image builds are required.
