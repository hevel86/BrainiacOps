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

# restore volumes/PVs only and let GitOps create PVCs
./longhorn-restore-backups.sh --execute --skip-pvc
```

Key env vars:
- `BACKUP_TARGET` – backup target URL (default: `nfs://truenas1-nfs.torquasmvo.internal:/mnt/fast/longhorn-backup`)
- `RECURRING_JOB_GROUP` – recurring job group label to apply (default: `prod`)
- `FRONTEND` – Longhorn frontend for restored volumes (default: `blockdev`)

Flags:
- `--execute` – Perform the restore (create Volume/PV/PVC). Without this flag, runs in dry-run mode showing what would be created.
- `--use-backup-volume-name` – Restore with the original Longhorn volume name (default behavior, optional flag for clarity)
- `--skip-pvc` – Do not create PVCs; rely on GitOps to create them and bind via PV claimRef

Behavior:
- Creates Volume/PV/PVC with `kubectl create` to avoid persisting last-applied annotations on immutable fields.
- Automatically detects existing PVCs and reuses their bound PV names for idempotent restores.
- When a PVC already exists with a bound PV, the script uses the CSI volume handle from the existing PV as the restore volume name. This ensures the restore reconnects to the correct Longhorn volume rather than creating a duplicate.
- Applies the recurring job group label (`recurring-job-group.longhorn.io/<group>: enabled`) on all restored volumes.
- `--skip-pvc` restores Volume/PV only and relies on GitOps to create PVCs that bind via the PV `claimRef`.
- The PV `claimRef` pre-binds the restored volume to the intended PVC name/namespace, preventing Longhorn from provisioning a fresh volume.
- You may see a kubectl warning about `metadata.finalizers: "longhorn.io"` not being domain-qualified; this comes from the Longhorn Volume CRD and is safe to ignore.

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
