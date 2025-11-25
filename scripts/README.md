# Scripts

Helper scripts for restoring Longhorn volumes from backups.

## Prerequisites
- `kubectl` configured to the cluster with Longhorn installed
- `jq`
- Access to the Longhorn backup target (default NFS path is baked into the scripts)

## longhorn-restore-backups.sh
Restore **all** Longhorn volumes from their latest backups.

```bash
# dry-run (lists what would be created)
./longhorn-restore-backups.sh

# execute restores with default settings
./longhorn-restore-backups.sh --execute
```

Key env vars:
- `BACKUP_TARGET` – backup target URL (default: NFS path in the script)
- `RECURRING_JOB_GROUP` – recurring job group label to apply (default: `prod`)
- `FRONTEND` – Longhorn frontend for restored volumes (default: `blockdev`)
- `USE_BACKUP_VOLUME_NAME` – `1` to use the original Longhorn volume name (`--use-backup-volume-name`), `0` to use the PVC name

Behavior:
- Creates Volume/PV/PVC if missing; skips or reuses existing PVC/PV to stay idempotent.
- Applies the recurring job group label on restored volumes.

## Notes
- `longhorn-restore-mylar3.sh` is kept as a single-volume test/example; it mirrors the same options but targets only the mylar3 PVC.
