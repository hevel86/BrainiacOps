# Scripts

Helper scripts for Longhorn volume management and operations.

## Prerequisites
- `kubectl` configured to the cluster with Longhorn installed
- `python3` (for analyze-pvc-usage.sh)
- `jq` (for restore scripts)
- Access to the Longhorn backup target (default NFS path is baked into the scripts)

## analyze-pvc-usage.sh
Analyze Longhorn PVC storage allocation and actual usage across the cluster.

```bash
./analyze-pvc-usage.sh
```

Generates a comprehensive markdown report at `docs/longhorn-pvc-usage.md` containing:
- Total allocated vs. used storage with efficiency metrics
- Volume inventory categorized by size
- Over-allocated volumes with waste calculations
- Optimization recommendations prioritized by impact
- Volumes at/over capacity requiring immediate action
- Storage efficiency breakdown by category

Run this periodically to track storage utilization and identify optimization opportunities.

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
- `USE_BACKUP_VOLUME_NAME` – `1` (default, also via `--use-backup-volume-name` flag) to use the original Longhorn volume name; `0` (via env var) to use the PVC name.

Behavior:
- Creates Volume/PV/PVC with `kubectl create` to avoid persisting last-applied annotations on immutable fields.
- Skips existing PVC/PV and reuses bound PV names so restore stays idempotent.
- Applies the recurring job group label on restored volumes.

If you previously restored with these scripts and hit immutable `volumeName` errors when running `kubectl apply -k`, drop the last-applied annotation on the PVCs before re-applying, e.g.:
```bash
kubectl -n <ns> annotate pvc <pvc-name> kubectl.kubernetes.io/last-applied-configuration-
```

## clean-pvc-last-applied.sh
Remove the kubectl last-applied annotation from PVCs (default namespace: `default`) to clear stale, immutable patches.

```bash
# clean default namespace
./clean-pvc-last-applied.sh

# clean another namespace
NAMESPACE=media ./clean-pvc-last-applied.sh
```

## Notes
- `longhorn-restore-mylar3.sh` is kept as a single-volume test/example; it mirrors the same options but targets only the mylar3 PVC.
