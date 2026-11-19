# MariaDB image packaging

Official MariaDB 11.8.9 retains the existing /config/databases in place as UID/GID1000. The startup guard rejects missing initialized data; there is no chown, new database, or automatic upgrade. Existing Bitwarden-managed Secret references remain unchanged.

The compatibility ConfigMap uses public LinuxServer stock server options, compared privately against the actual existing configuration. The stock-only slave_connections_needed_for_purge override was absent from the existing file and is not introduced. Packaging-specific user, basedir, datadir, socket, pid-file and locale paths are omitted or replaced by explicit runtime arguments and the vendor defaults. Existing READ-COMMITTED, charset/collation, binlogs and log paths are retained. DNS resolution and host cache remain explicitly at their prior effective values.

The old /config/custom.cnf remains on the original PVC for rollback but is not loaded by the official image; make future desired server settings changes in the Git-managed compatibility ConfigMap. The Nextcloud web image, routing, PHP mitigations and app/data mount layout are not changed by this database-only cutover.
