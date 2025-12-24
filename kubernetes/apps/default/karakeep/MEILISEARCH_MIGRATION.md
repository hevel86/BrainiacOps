---
# LLM AUTOMATION METADATA
# This YAML frontmatter enables automated migration by LLMs (Claude, Gemini, Codex)
automation:
  type: database-migration
  service: meilisearch
  namespace: default
  deployment: karakeep-meilisearch
  pvc_name: karakeep-meilisearch-pvc-lh
  pvc_access_mode: ReadWriteOnce
  secret_env_var: MEILI_MASTER_KEY
  api_port: 7700
  api_base_url: "http://localhost:7700"
  index_name: bookmarks
  dumps_path: /meili_data/dumps
  data_path: /meili_data
  manifest_path: kubernetes/apps/default/karakeep/deploy-meilisearch.yaml
  label_selector: component=meilisearch
  deployment_strategy: Recreate

current_state:
  version: "v1.31.0"
  last_migration: "2025-12-24"
  document_count: 72

prerequisites:
  - kubectl cluster access
  - write access to deploy-meilisearch.yaml
  - disk space in /tmp for dump file (~10MB typical)
  - MEILI_MASTER_KEY injected via Bitwarden Secrets Operator

estimated_downtime_minutes: 15
---

# Meilisearch Migration Guide

> **For LLM Agents**: See [LLM Automation Instructions](#llm-automation-instructions) for machine-executable procedures.

## Table of Contents

1. [LLM Automation Instructions](#llm-automation-instructions)
2. [Decision Tree](#decision-tree)
3. [Standard Migration Procedure](#standard-migration-procedure)
4. [Rollback Procedure](#rollback-procedure)
5. [Troubleshooting](#troubleshooting)
6. [Migration History](#migration-history)
7. [References](#references)

---

## LLM Automation Instructions

This section provides structured instructions for LLM agents (Claude, Gemini, Codex) to automate Meilisearch migrations.

### Context Detection

Before starting, gather current state:

```bash
# Get current image version
kubectl get deploy karakeep-meilisearch -n default -o jsonpath='{.spec.template.spec.containers[0].image}'

# Check pod status
kubectl get pods -n default -l component=meilisearch -o wide

# Check if pod is crashing (version mismatch indicator)
kubectl get pods -n default -l component=meilisearch -o jsonpath='{.items[0].status.containerStatuses[0].state}'
```

### Variable Template

Before executing migration, populate these variables:

```yaml
# MIGRATION VARIABLES - Fill before executing
SOURCE_VERSION: ""        # e.g., "v1.28.2"
TARGET_VERSION: ""        # e.g., "v1.29.0"
DUMP_FILENAME: ""         # Generated: YYYYMMDD-HHMMSSmmm.dump
LOCAL_BACKUP_PATH: ""     # e.g., "/tmp/karakeep-meili-20251208.dump"
TASK_UID: ""              # Returned from dump creation API call
```

### Executable Migration Steps

Each step includes the command, expected output, and verification checkpoint.

#### STEP 1: Scale Down Deployment

```bash
kubectl scale deploy karakeep-meilisearch -n default --replicas=0
kubectl wait --for=delete pod -l component=meilisearch -n default --timeout=60s
```

**Verification**:
- Command exits with code 0
- `kubectl get pods -n default -l component=meilisearch` returns no resources

#### STEP 2: Start Source Version (if not running)

Only execute if current version differs from SOURCE_VERSION or pod is crashed:

```bash
# Edit deploy-meilisearch.yaml to set: image: getmeili/meilisearch:${SOURCE_VERSION}
kubectl apply -f kubernetes/apps/default/karakeep/deploy-meilisearch.yaml
kubectl scale deploy karakeep-meilisearch -n default --replicas=1
kubectl wait --for=condition=ready pod -l component=meilisearch -n default --timeout=120s
```

**Verification**:
- Pod status is `Running`
- `kubectl logs -n default -l component=meilisearch --tail=10` shows no errors

#### STEP 3: Create Database Dump

```bash
# Create dump
kubectl exec -n default deploy/karakeep-meilisearch -- \
  sh -c 'curl -s -X POST "http://localhost:7700/dumps" -H "Authorization: Bearer $MEILI_MASTER_KEY"'
```

**Expected Output**: `{"taskUid":NNN,"indexUid":null,"status":"enqueued",...}`

**Capture**: Save `taskUid` value as TASK_UID variable.

```bash
# Check task status (replace TASK_UID)
kubectl exec -n default deploy/karakeep-meilisearch -- \
  sh -c 'curl -s "http://localhost:7700/tasks/${TASK_UID}" -H "Authorization: Bearer $MEILI_MASTER_KEY"'
```

**Verification**:
- Response contains `"status":"succeeded"`
- Response contains `"dumpUid":"YYYYMMDD-HHMMSSmmm"` - save as DUMP_FILENAME

#### STEP 4: Download Dump to Local Machine

```bash
# List dumps to confirm
kubectl exec -n default deploy/karakeep-meilisearch -- ls -lh /meili_data/dumps/

# Copy dump locally (replace DUMP_FILENAME)
kubectl cp default/$(kubectl get pods -n default -l component=meilisearch -o jsonpath='{.items[0].metadata.name}'):/meili_data/dumps/${DUMP_FILENAME}.dump ${LOCAL_BACKUP_PATH}
```

**Verification**:
- Local file exists: `ls -lh ${LOCAL_BACKUP_PATH}`
- File size is non-zero (typically 1-50MB depending on data)

#### STEP 5: Clean Persistent Volume

```bash
# Scale down first
kubectl scale deploy karakeep-meilisearch -n default --replicas=0
kubectl wait --for=delete pod -l component=meilisearch -n default --timeout=60s

# Run cleanup pod
kubectl run meili-cleanup --image=busybox --restart=Never -n default --overrides='{"spec":{"containers":[{"name":"cleanup","image":"busybox","command":["sh","-c","rm -rf /meili_data/* && echo Cleanup complete"],"volumeMounts":[{"name":"data","mountPath":"/meili_data"}]}],"volumes":[{"name":"data","persistentVolumeClaim":{"claimName":"karakeep-meilisearch-pvc-lh"}}]}}'

# Wait and verify
kubectl wait --for=condition=complete pod/meili-cleanup -n default --timeout=120s
kubectl logs meili-cleanup -n default
kubectl delete pod meili-cleanup -n default
```

**Verification**:
- Logs show "Cleanup complete"
- Pod deleted successfully

#### STEP 6: Stage Dump Back onto PVC

```bash
# Create stager pod
kubectl run meili-stager --image=busybox --restart=Never -n default --overrides='{"spec":{"containers":[{"name":"stager","image":"busybox","command":["sh","-c","sleep 3600"],"volumeMounts":[{"name":"data","mountPath":"/meili_data"}]}],"volumes":[{"name":"data","persistentVolumeClaim":{"claimName":"karakeep-meilisearch-pvc-lh"}}]}}'
kubectl wait --for=condition=ready pod/meili-stager -n default --timeout=60s

# Create dumps directory and copy file
kubectl exec -n default meili-stager -- mkdir -p /meili_data/dumps
kubectl cp ${LOCAL_BACKUP_PATH} default/meili-stager:/meili_data/dumps/${DUMP_FILENAME}.dump

# Verify and cleanup stager
kubectl exec -n default meili-stager -- ls -lh /meili_data/dumps/
kubectl delete pod meili-stager -n default
```

**Verification**:
- `ls` output shows dump file with correct size
- Stager pod deleted

#### STEP 7: Deploy Target Version with Import Flag

Edit `deploy-meilisearch.yaml`:

```yaml
containers:
  - name: meilisearch
    image: getmeili/meilisearch:${TARGET_VERSION}
    imagePullPolicy: IfNotPresent
    args:
      - meilisearch
      - --import-dump
      - /meili_data/dumps/${DUMP_FILENAME}.dump
    # ... rest of container spec
```

```bash
kubectl apply -f kubernetes/apps/default/karakeep/deploy-meilisearch.yaml
kubectl rollout status deploy/karakeep-meilisearch -n default --timeout=120s
```

**Verification**:
- Check logs for success message:
```bash
kubectl logs -n default -l component=meilisearch | grep -E "(Importing|successfully imported)"
```
- Expected: `All documents successfully imported.`

#### STEP 8: Remove Import Flag and Finalize

Edit `deploy-meilisearch.yaml` to remove the `args` block (keep target version image).

```bash
kubectl apply -f kubernetes/apps/default/karakeep/deploy-meilisearch.yaml
kubectl rollout restart deploy/karakeep-meilisearch -n default
kubectl rollout status deploy/karakeep-meilisearch -n default --timeout=120s
```

**Verification**:
- Pod starts without import flag
- No errors in logs

#### STEP 9: Verify Data Integrity

```bash
# Check indexes exist
kubectl exec -n default deploy/karakeep-meilisearch -- \
  sh -c 'curl -s "http://localhost:7700/indexes" -H "Authorization: Bearer $MEILI_MASTER_KEY"'

# Check document count
kubectl exec -n default deploy/karakeep-meilisearch -- \
  sh -c 'curl -s "http://localhost:7700/indexes/bookmarks/stats" -H "Authorization: Bearer $MEILI_MASTER_KEY"'
```

**Verification**:
- Index `bookmarks` exists
- `numberOfDocuments` matches expected count (currently 71)

#### STEP 10: Cleanup (Optional)

```bash
# Remove dump from PVC
kubectl exec -n default deploy/karakeep-meilisearch -- rm -f /meili_data/dumps/${DUMP_FILENAME}.dump

# Remove local backup (only after verification)
rm -f ${LOCAL_BACKUP_PATH}
```

---

## Decision Tree

Use this flowchart to determine the correct action:

```
START: Meilisearch needs upgrade from VERSION_A to VERSION_B
│
├─► Is pod in CrashLoopBackOff with version mismatch error?
│   ├─► YES: Version mismatch detected
│   │   └─► REQUIRED: Full dump/restore migration
│   │       └─► Go to STEP 1
│   │
│   └─► NO: Pod is running normally
│       │
│       ├─► Is this a patch version bump? (e.g., 1.28.1 → 1.28.2)
│       │   ├─► YES: Try direct upgrade first
│       │   │   └─► Update image tag, apply, monitor
│       │   │       └─► If fails with version error → Full migration
│       │   │
│       │   └─► NO: Minor/major version change
│       │       └─► REQUIRED: Full dump/restore migration
│       │           └─► Go to STEP 1
│       │
│       └─► Does local backup already exist?
│           ├─► YES: Skip to STEP 5 (Clean PVC)
│           └─► NO: Start from STEP 1
│
└─► MIGRATION FAILED?
    └─► Go to Rollback Procedure
```

### Quick Reference: When to Use What

| Scenario | Action |
|----------|--------|
| Pod crashing with version mismatch | Full migration required |
| Minor version upgrade (1.27 → 1.28) | Full migration required |
| Patch version upgrade (1.28.1 → 1.28.2) | Try direct first, migrate if fails |
| Fresh install (no data) | Direct install, no migration |
| Restore from backup | Skip to STEP 5 with existing backup |

---

## Standard Migration Procedure

### Problem Background

Meilisearch does not support automatic in-place database migrations between versions. When upgrading, the pod crashes with:

```
ERROR meilisearch: error=Your database version (X.Y.Z) is incompatible with your current engine version (A.B.C).
To migrate data between Meilisearch versions, please follow our guide on https://www.meilisearch.com/docs/learn/update_and_migration/updating.
```

### Solution Overview

1. Run source version to create a dump (native export format)
2. Clean the persistent volume completely
3. Stage the dump file back onto the clean PVC
4. Start target version with `--import-dump` flag
5. Remove import flag after successful import

### Prerequisites

- `kubectl` access to the cluster
- Write access to `deploy-meilisearch.yaml`
- Sufficient disk space in `/tmp` for dump file
- Master key available via `MEILI_MASTER_KEY` environment variable

---

## Rollback Procedure

If migration fails at any step, use this procedure to restore service:

### Quick Rollback (Source Version Still Works)

```bash
# 1. Scale down
kubectl scale deploy karakeep-meilisearch -n default --replicas=0
kubectl wait --for=delete pod -l component=meilisearch -n default --timeout=60s

# 2. Clean PVC
kubectl run meili-cleanup --image=busybox --restart=Never -n default --overrides='{"spec":{"containers":[{"name":"cleanup","image":"busybox","command":["sh","-c","rm -rf /meili_data/* && echo Cleanup complete"],"volumeMounts":[{"name":"data","mountPath":"/meili_data"}]}],"volumes":[{"name":"data","persistentVolumeClaim":{"claimName":"karakeep-meilisearch-pvc-lh"}}]}}'
kubectl wait --for=condition=complete pod/meili-cleanup -n default --timeout=120s
kubectl delete pod meili-cleanup -n default

# 3. Stage backup
kubectl run meili-stager --image=busybox --restart=Never -n default --overrides='{"spec":{"containers":[{"name":"stager","image":"busybox","command":["sh","-c","sleep 3600"],"volumeMounts":[{"name":"data","mountPath":"/meili_data"}]}],"volumes":[{"name":"data","persistentVolumeClaim":{"claimName":"karakeep-meilisearch-pvc-lh"}}]}}'
kubectl wait --for=condition=ready pod/meili-stager -n default --timeout=60s
kubectl exec -n default meili-stager -- mkdir -p /meili_data/dumps
kubectl cp ${LOCAL_BACKUP_PATH} default/meili-stager:/meili_data/dumps/rollback.dump
kubectl delete pod meili-stager -n default

# 4. Deploy source version with import
# Edit deploy-meilisearch.yaml:
#   image: getmeili/meilisearch:${SOURCE_VERSION}
#   args: ["meilisearch", "--import-dump", "/meili_data/dumps/rollback.dump"]
kubectl apply -f kubernetes/apps/default/karakeep/deploy-meilisearch.yaml
kubectl rollout status deploy/karakeep-meilisearch -n default --timeout=120s

# 5. Remove import flag after success
# Edit deploy-meilisearch.yaml to remove args
kubectl apply -f kubernetes/apps/default/karakeep/deploy-meilisearch.yaml
kubectl rollout restart deploy/karakeep-meilisearch -n default
```

### Verification After Rollback

```bash
kubectl exec -n default deploy/karakeep-meilisearch -- \
  sh -c 'curl -s "http://localhost:7700/indexes/bookmarks/stats" -H "Authorization: Bearer $MEILI_MASTER_KEY"'
```

---

## Troubleshooting

### Issue: "Multi-Attach error for volume"

**Symptom**: New pod can't start because volume is still attached to old pod.

**Cause**: PVC access mode is `ReadWriteOnce`; only one pod can mount at a time.

**Solution**:
```bash
# Force delete stuck pod
kubectl delete pod <old-pod-name> -n default --force --grace-period=0

# Or scale to 0 and wait
kubectl scale deploy karakeep-meilisearch -n default --replicas=0
kubectl wait --for=delete pod -l component=meilisearch -n default --timeout=120s
```

### Issue: "database already exists at /meili_data/data.ms"

**Symptom**: Import fails because target version created a new database before importing.

**Cause**: PVC was not fully cleaned before starting target version.

**Solution**:
```bash
kubectl scale deploy karakeep-meilisearch -n default --replicas=0
kubectl run meili-cleanup --image=busybox --restart=Never -n default --overrides='{"spec":{"containers":[{"name":"cleanup","image":"busybox","command":["sh","-c","rm -rf /meili_data/data.ms && echo Cleanup complete"],"volumeMounts":[{"name":"data","mountPath":"/meili_data"}]}],"volumes":[{"name":"data","persistentVolumeClaim":{"claimName":"karakeep-meilisearch-pvc-lh"}}]}}'
kubectl wait --for=condition=complete pod/meili-cleanup -n default --timeout=60s
kubectl delete pod meili-cleanup -n default
kubectl scale deploy karakeep-meilisearch -n default --replicas=1
```

### Issue: "Resource temporarily unavailable (os error 11)"

**Symptom**: Multiple pods trying to access the same PVC simultaneously.

**Cause**: Race condition during scaling or leftover terminating pods.

**Solution**:
```bash
kubectl scale deploy karakeep-meilisearch -n default --replicas=0
kubectl get pods -n default -l component=meilisearch -w  # Wait until completely gone
kubectl scale deploy karakeep-meilisearch -n default --replicas=1
```

### Issue: Dump creation task stuck in "enqueued"

**Symptom**: Task never progresses to "succeeded".

**Cause**: Meilisearch may be under load or have resource constraints.

**Solution**:
```bash
# Check all tasks
kubectl exec -n default deploy/karakeep-meilisearch -- \
  sh -c 'curl -s "http://localhost:7700/tasks?limit=10" -H "Authorization: Bearer $MEILI_MASTER_KEY"'

# If stuck, restart and retry
kubectl rollout restart deploy/karakeep-meilisearch -n default
# Wait for ready, then retry dump creation
```

---

## Migration History

### Migration Log Format

```yaml
migration:
  date: "YYYY-MM-DD"
  source_version: "vX.Y.Z"
  target_version: "vA.B.C"
  dump_file: "YYYYMMDD-HHMMSSmmm.dump"
  local_backup: "/tmp/karakeep-meili-YYYYMMDD.dump"
  status: completed|failed|pending
  documents_migrated: N
  downtime_minutes: N
  notes: ""
```

### v1.28.2 → v1.30.0 (2025-12-16)

```yaml
migration:
  date: "2025-12-16"
  source_version: "v1.28.2"
  target_version: "v1.30.0"
  dump_file: "20251216-034934741.dump"
  local_backup: "/tmp/karakeep-meili-20251216.dump"
  status: completed
  documents_migrated: 71
  downtime_minutes: 6
  notes: "Automated migration via Claude Code. Skip v1.29.0, direct upgrade to v1.30.0. Silent import (no log messages in v1.30.0)"
```

### v1.30.0 → v1.31.0 (2025-12-24)

```yaml
migration:
  date: "2025-12-24"
  source_version: "v1.30.0"
  target_version: "v1.31.0"
  dump_file: "20251224-190735936.dump"
  local_backup: "/tmp/karakeep-meili-20251224.dump"
  status: completed
  documents_migrated: 72
  downtime_minutes: 8
  notes: "CrashLoopBackOff on version mismatch; full dump/restore completed successfully."
```

### v1.28.2 → v1.29.0 (2025-12-08)

```yaml
migration:
  date: "2025-12-08"
  source_version: "v1.28.2"
  target_version: "v1.29.0"
  dump_file: "20251208-150000000.dump"
  local_backup: "/tmp/karakeep-meili-20251208.dump"
  status: skipped
  documents_migrated: 0
  downtime_minutes: 0
  notes: "Skipped - upgraded directly to v1.30.0"
```

### v1.27.0 → v1.28.2 (2025-12-08)

```yaml
migration:
  date: "2025-12-08"
  source_version: "v1.27.0"
  target_version: "v1.28.2"
  dump_file: "20251208-145849091.dump"
  local_backup: "/tmp/karakeep-meili-20251208.dump"
  status: completed
  documents_migrated: 67
  downtime_minutes: 12
  notes: "Smooth migration, no issues"
```

### v1.26.0 → v1.27.0 (2025-12-01)

```yaml
migration:
  date: "2025-12-01"
  source_version: "v1.26.0"
  target_version: "v1.27.0"
  dump_file: "20251201-213154576.dump"
  local_backup: "/tmp/karakeep-meili-20251201.dump"
  status: completed
  documents_migrated: 67
  downtime_minutes: 14
  notes: "First migration using stager pod pattern"
```

### v1.11.1 → v1.26.0 (2025-11-23)

```yaml
migration:
  date: "2025-11-23"
  source_version: "v1.11.1"
  target_version: "v1.26.0"
  dump_file: "migration.dump"
  local_backup: "/tmp/meilisearch-migration.dump"
  status: completed
  documents_migrated: 67
  downtime_minutes: 14
  notes: "Initial migration after CrashLoopBackOff discovery"
```

---

## Key Learnings

1. **Meilisearch doesn't support automatic migrations**: Always use the dump/restore process for version upgrades.

2. **Import flag requires clean database**: The `--import-dump` flag fails if a database already exists. Clean the PVC completely before importing.

3. **PVC access mode matters**: With `ReadWriteOnce`, only one pod can access the volume at a time. Always scale to 0 before operations that require exclusive access.

4. **Master key is required**: All API operations require authentication via the `MEILI_MASTER_KEY` environment variable.

5. **Remove import flag after migration**: Running with `--import-dump` continuously will cause errors on subsequent restarts.

6. **Keep deployment strategy as Recreate**: Avoids multi-attach errors during rollouts with RWO PVC.

---

## References

- [Meilisearch Update and Migration Guide](https://www.meilisearch.com/docs/learn/update_and_migration/updating)
- [Meilisearch Dumps API](https://www.meilisearch.com/docs/reference/api/dump)
- Deployment manifest: `kubernetes/apps/default/karakeep/deploy-meilisearch.yaml`
- PVC manifest: `kubernetes/apps/default/karakeep/pvc.yaml`

---

## Summary

- **Current Version**: v1.30.0
- **Index**: bookmarks (71 documents)
- **Data Loss**: None across all migrations
- **Last Migration**: 2025-12-16
- **Automated By**: Claude Code
