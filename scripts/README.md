# Scripts

Helper scripts for cluster operations, Longhorn volume management, and infrastructure maintenance.

## Prerequisites
- `kubectl` configured to the cluster
- `python3` (for `analyze-pvc-usage.sh`, `longhorn-instance-manager-rollover.py`)
- `jq` (for restore scripts and `clean-pvc-last-applied.sh`)
- Access to the Longhorn backup target (default NFS path is baked into the restore scripts)

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

Run periodically to track storage utilization and identify optimization opportunities.

## longhorn-instance-manager-rollover.py
Roll Longhorn-attached workloads one-by-one to migrate them off old instance-manager instances (e.g., after a Longhorn upgrade). Shows live migration metrics as each workload cycles.

```bash
# dry-run: show what would be restarted and current migration state
python3 longhorn-instance-manager-rollover.py

# execute restarts with default bounce strategy
python3 longhorn-instance-manager-rollover.py --execute

# target a specific node only
python3 longhorn-instance-manager-rollover.py --execute --node brainiac-01

# use rollout restart instead of scale-to-zero bounce
python3 longhorn-instance-manager-rollover.py --execute --strategy rollout
```

Key flags:
- `--execute` – Perform restarts (default is dry-run)
- `--node NODE` – Only process workloads whose attached volume is on this node
- `--namespace NS` – Only process workloads in this namespace
- `--include REGEX` – Regex filter on workload names
- `--limit N` – Max number of workloads to process
- `--strategy {bounce,rollout}` – `bounce` (default) scales to 0 then back up to force volume detach/reattach; `rollout` does a rolling restart
- `--down-wait N` – Seconds to wait after scale-to-0 before scaling back up (default: 20)
- `--timeout N` – Rollout timeout per workload in seconds (default: 900)
- `--continue-on-error` – Continue to next workload if one fails
- `--no-skip-migrated` – Process workloads even if already on the new instance-manager

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
Remove the kubectl last-applied annotation from PVCs to clear stale, immutable patches.

```bash
# clean default namespace
./clean-pvc-last-applied.sh

# clean another namespace
NAMESPACE=media ./clean-pvc-last-applied.sh
```

## update-ip-addresses.sh
Query the cluster for all LoadBalancer services and regenerate `docs/ip_addresses.md` with a current IP inventory table. Also reads the MetalLB pool configuration and reports total/used/free IP counts.

```bash
./update-ip-addresses.sh
```

Writes output to `docs/ip_addresses.md`. Requires `kubectl` and `python3` (used internally to count pool IPs).

## monthly-tag.sh
Create a dated Git tag (`YYYY.MM.DD`) for the current state of the repo. Auto-commits any uncommitted changes before tagging.

```bash
./monthly-tag.sh
```

Pushes both the commit (if any) and the tag to `origin`. Skips tag creation if the tag already exists.

## technitium/manage.py
Unified management tool for the Technitium DNS cluster (Proxmox LXC nodes).

```bash
python3 technitium/manage.py <command> [options]
```

Commands:
- `status` – Check cluster status, blocklists, and sync state
- `setup` – Run initial setup (zones, settings) on Primary/Secondary nodes
- `reverse-dns` – Configure conditional forwarder zones for reverse DNS on all nodes
- `forwarders` – Update upstream DNS providers
- `import` – Migrate records from a Pi-hole Teleporter ZIP
- `analyze` – Analyze NXDOMAIN query logs

