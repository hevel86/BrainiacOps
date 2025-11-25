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
- Creates Volume/PV/PVC with `kubectl create` to avoid persisting last-applied annotations on immutable fields.
- Skips existing PVC/PV and reuses bound PV names so restore stays idempotent.
- Applies the recurring job group label on restored volumes.

If you previously restored with these scripts and hit immutable `volumeName` errors when running `kubectl apply -k`, drop the last-applied annotation on the PVCs before re-applying, e.g.:
```bash
kubectl -n <ns> annotate pvc <pvc-name> kubectl.kubernetes.io/last-applied-configuration-
```

## Notes
- `longhorn-restore-mylar3.sh` is kept as a single-volume test/example; it mirrors the same options but targets only the mylar3 PVC.
