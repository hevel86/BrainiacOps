# Meilisearch Migration Guide

## Problem

After a Meilisearch version upgrade from v1.11.1 to v1.26.0, the pod was in CrashLoopBackOff with the following error:

```
ERROR meilisearch: error=Your database version (1.11.1) is incompatible with your current engine version (1.26.0).
To migrate data between Meilisearch versions, please follow our guide on https://www.meilisearch.com/docs/learn/update_and_migration/updating.
```

**Root Cause**: Meilisearch does not support automatic in-place database migrations between major versions. The persistent volume contained data in v1.11.1 format, which v1.26.0 cannot read directly.

## Solution Overview (v1.11.1 → v1.26.0)

The migration requires:
1. Downgrading to v1.11.1 to access the old data
2. Creating a dump file (Meilisearch's native export format)
3. Upgrading to v1.26.0 with a clean database
4. Importing the dump file into the new version

**Migration Date**: 2025-11-23
**Result**: Successful migration of 67 bookmarks with zero data loss
**Downtime**: Approximately 14 minutes

## Prerequisites

- `kubectl` access to the cluster
- Write access to the deployment manifest
- Sufficient disk space in `/tmp` for the dump file
- Master key available in the `karakeep-secrets` Secret (via Bitwarden Secrets Operator)

## Step-by-Step Migration Process

### 1. Scale Down the Crashing Deployment

```bash
kubectl scale deployment karakeep-meilisearch -n default --replicas=0
```

This stops the CrashLoopBackOff pod and releases the PVC.

### 2. Downgrade to v1.11.1

Edit `deploy-meilisearch.yaml`:

```yaml
# Change from:
image: getmeili/meilisearch:v1.26.0

# To:
image: getmeili/meilisearch:v1.11.1
```

Apply and scale up:

```bash
kubectl apply -f kubernetes/apps/default/karakeep/deploy-meilisearch.yaml
kubectl scale deployment karakeep-meilisearch -n default --replicas=1
```

Wait for the pod to reach Running state:

```bash
kubectl get pods -n default -l component=meilisearch -w
```

### 3. Create Database Dump

Trigger the dump creation using the Meilisearch API:

```bash
kubectl exec -n default deployment/karakeep-meilisearch -- sh -c \
  'curl -X POST "http://localhost:7700/dumps" -H "Authorization: Bearer $MEILI_MASTER_KEY"'
```

Response will include a `taskUid`. Check the task status:

```bash
kubectl exec -n default deployment/karakeep-meilisearch -- sh -c \
  'curl -s "http://localhost:7700/tasks/<taskUid>" -H "Authorization: Bearer $MEILI_MASTER_KEY"'
```

Wait for `"status":"succeeded"`. The response will include the dump filename in `details.dumpUid`.

### 4. Download the Dump File

List the dumps directory:

```bash
kubectl exec -n default deployment/karakeep-meilisearch -- ls -lh /meili_data/dumps/
```

Copy the dump to your local machine:

```bash
kubectl cp default/$(kubectl get pods -n default -l component=meilisearch -o jsonpath='{.items[0].metadata.name}'):/meili_data/dumps/<dumpfile>.dump /tmp/meilisearch-migration.dump
```

**Important**: Keep this backup file until you've verified the migration succeeded.

### 5. Clean the Persistent Volume

Scale down the deployment:

```bash
kubectl scale deployment karakeep-meilisearch -n default --replicas=0
```

Remove all old data from the PVC:

```bash
kubectl run cleanup-pod --image=busybox --restart=Never -n default --overrides='
{
  "spec": {
    "containers": [
      {
        "name": "cleanup",
        "image": "busybox",
        "command": ["sh", "-c", "rm -rf /meili_data/* && echo Cleanup complete"],
        "volumeMounts": [
          {
            "name": "data",
            "mountPath": "/meili_data"
          }
        ]
      }
    ],
    "volumes": [
      {
        "name": "data",
        "persistentVolumeClaim": {
          "claimName": "karakeep-meilisearch-pvc-lh"
        }
      }
    ]
  }
}'
```

Wait for completion and cleanup:

```bash
kubectl wait --for=condition=complete pod/cleanup-pod -n default --timeout=60s
kubectl logs cleanup-pod -n default
kubectl delete pod cleanup-pod -n default
```

### 6. Upgrade to v1.26.0 with Import Flag

Edit `deploy-meilisearch.yaml`:

```yaml
containers:
  - name: meilisearch
    image: getmeili/meilisearch:v1.26.0
    imagePullPolicy: IfNotPresent
    args: ["meilisearch", "--import-dump", "/meili_data/dumps/migration.dump"]
    ports:
      # ... rest of config
```

Apply the configuration:

```bash
kubectl apply -f kubernetes/apps/default/karakeep/deploy-meilisearch.yaml
kubectl scale deployment karakeep-meilisearch -n default --replicas=1
```

### 7. Copy Dump File to New Container

Wait for the pod to be running:

```bash
kubectl wait --for=condition=ready pod -l component=meilisearch -n default --timeout=60s
```

Copy the dump file into the container:

```bash
kubectl cp /tmp/meilisearch-migration.dump \
  default/$(kubectl get pods -n default -l component=meilisearch -o jsonpath='{.items[0].metadata.name}'):/meili_data/dumps/migration.dump
```

### 8. Restart to Import

The container should restart and import the dump automatically. If not, restart it:

```bash
kubectl rollout restart deployment/karakeep-meilisearch -n default
```

Monitor the logs to verify the import:

```bash
kubectl logs -n default -l component=meilisearch -f
```

You should see:

```
INFO meilisearch: Importing a dump of meilisearch version=V6
INFO meilisearch: Importing index `bookmarks`.
INFO meilisearch: All documents successfully imported.
```

### 9. Remove Import Flag

After successful import, edit `deploy-meilisearch.yaml` to remove the import arguments:

```yaml
containers:
  - name: meilisearch
    image: getmeili/meilisearch:v1.26.0
    imagePullPolicy: IfNotPresent
    # REMOVE: args: ["meilisearch", "--import-dump", "/meili_data/dumps/migration.dump"]
    ports:
      # ... rest of config
```

Apply the normal configuration:

```bash
kubectl apply -f kubernetes/apps/default/karakeep/deploy-meilisearch.yaml
kubectl rollout restart deployment/karakeep-meilisearch -n default
```

### 10. Verify Migration

Check that the pod is running:

```bash
kubectl get pods -n default -l component=meilisearch
```

Verify the indexes exist:

```bash
kubectl exec -n default deployment/karakeep-meilisearch -- sh -c \
  'curl -s "http://localhost:7700/indexes" -H "Authorization: Bearer $MEILI_MASTER_KEY"'
```

Check document count:

```bash
kubectl exec -n default deployment/karakeep-meilisearch -- sh -c \
  'curl -s "http://localhost:7700/indexes/bookmarks/stats" -H "Authorization: Bearer $MEILI_MASTER_KEY"'
```

### 11. Cleanup

Remove the temporary dump file:

```bash
rm -f /tmp/meilisearch-migration.dump
```

## Troubleshooting

### Issue: "Multi-Attach error for volume"

**Symptom**: New pod can't start because volume is still attached to old pod.

**Solution**: Delete the old pod manually:

```bash
kubectl delete pod <old-pod-name> -n default
```

### Issue: "database already exists at /meili_data/data.ms"

**Symptom**: Import fails because v1.26.0 created a new database before importing.

**Solution**: Clean the `data.ms` directory specifically:

```bash
kubectl scale deployment karakeep-meilisearch -n default --replicas=0

kubectl run cleanup-pod2 --image=busybox --restart=Never -n default --overrides='
{
  "spec": {
    "containers": [
      {
        "name": "cleanup",
        "image": "busybox",
        "command": ["sh", "-c", "rm -rf /meili_data/data.ms && echo Cleanup complete"],
        "volumeMounts": [{"name": "data", "mountPath": "/meili_data"}]
      }
    ],
    "volumes": [{"name": "data", "persistentVolumeClaim": {"claimName": "karakeep-meilisearch-pvc-lh"}}]
  }
}'

kubectl wait --for=condition=complete pod/cleanup-pod2 -n default --timeout=60s
kubectl delete pod cleanup-pod2 -n default
kubectl scale deployment karakeep-meilisearch -n default --replicas=1
```

### Issue: "Resource temporarily unavailable (os error 11)"

**Symptom**: Multiple pods trying to access the same PVC simultaneously.

**Solution**: Scale to 0, wait for all pods to terminate, then scale to 1:

```bash
kubectl scale deployment karakeep-meilisearch -n default --replicas=0
kubectl get pods -n default -l component=meilisearch -w  # Wait until none remain
kubectl scale deployment karakeep-meilisearch -n default --replicas=1
```

## Key Learnings

1. **Meilisearch doesn't support automatic migrations**: Always use the dump/restore process for major version upgrades.

2. **Import flag requires clean database**: The `--import-dump` flag fails if a database already exists. Clean the PVC completely before importing.

3. **PVC access mode matters**: With `ReadWriteOnce`, only one pod can access the volume at a time. Always scale to 0 before operations that require exclusive access.

4. **Master key is required**: The dump creation and all API operations require authentication via the `MEILI_MASTER_KEY` environment variable.

5. **Remove import flag after migration**: Running with `--import-dump` continuously will cause errors on subsequent restarts.

## References

- [Meilisearch Update and Migration Guide](https://www.meilisearch.com/docs/learn/update_and_migration/updating)
- [Meilisearch Dumps API](https://www.meilisearch.com/docs/reference/api/dump)
- Deployment manifest: `kubernetes/apps/default/karakeep/deploy-meilisearch.yaml`
- PVC manifest: `kubernetes/apps/default/karakeep/pvc.yaml`

## Migration Summary

- **Database Version**: 1.11.1 → 1.26.0
- **Index Migrated**: bookmarks (67 documents)
- **Data Loss**: None
- **Downtime**: ~14 minutes
- **Migration Date**: 2025-11-23
- **Performed By**: Claude Code (automated migration)

---

# Quick Migration Notes: v1.26.0 → v1.27.0 (2025-12-01)

This was a straightforward dump/import using the same PVC (RWO). Keep the Deployment `strategy: Recreate` to avoid multi-attach errors.

1. **Scale down** to release the PVC:
   ```
   kubectl scale deployment karakeep-meilisearch -n default --replicas=0
   ```
2. **Run v1.26.0 to create a dump**:
   - Set `image: getmeili/meilisearch:v1.26.0` in `deploy-meilisearch.yaml`.
   - Apply and scale to 1, wait until Running.
   - Create dump:
     ```
     kubectl exec -n default deploy/karakeep-meilisearch -- \
       sh -c 'curl -s -X POST "http://localhost:7700/dumps" -H "Authorization: Bearer $MEILI_MASTER_KEY"'
     ```
   - Note the `dumpUid` (e.g., `20251201-213154576.dump`).
3. **Backup the dump locally (optional but recommended)**:
   ```
   kubectl cp default/$(kubectl get pods -n default -l component=meilisearch -o jsonpath='{.items[0].metadata.name}'):/meili_data/dumps/20251201-213154576.dump /tmp/karakeep-meili-20251201.dump
   ```
4. **Clean the PVC** to ensure import succeeds:
   ```
   kubectl scale deploy karakeep-meilisearch -n default --replicas=0
   kubectl run meili-cleanup --image=busybox --restart=Never -n default --overrides='{"spec":{"containers":[{"name":"cleanup","image":"busybox","command":["sh","-c","rm -rf /meili_data/* && echo Cleanup complete"],"volumeMounts":[{"name":"data","mountPath":"/meili_data"}]}],"volumes":[{"name":"data","persistentVolumeClaim":{"claimName":"karakeep-meilisearch-pvc-lh"}}]}}'
   kubectl wait --for=condition=complete pod/meili-cleanup -n default --timeout=120s
   kubectl delete pod meili-cleanup -n default
   ```
5. **Stage the dump back onto the PVC**:
   ```
   kubectl run meili-stager --image=busybox --restart=Never -n default --overrides='{"spec":{"containers":[{"name":"stager","image":"busybox","command":["sh","-c","sleep 3600"],"volumeMounts":[{"name":"data","mountPath":"/meili_data"}]}],"volumes":[{"name":"data","persistentVolumeClaim":{"claimName":"karakeep-meilisearch-pvc-lh"}}]}}'
   kubectl wait --for=condition=ready pod/meili-stager -n default --timeout=60s
   kubectl exec -n default meili-stager -- sh -c 'mkdir -p /meili_data/dumps'
   kubectl cp /tmp/karakeep-meili-20251201.dump default/meili-stager:/meili_data/dumps/20251201-213154576.dump
   kubectl delete pod meili-stager -n default
   ```
6. **Start v1.27.0 with import flag**:
   - Set in `deploy-meilisearch.yaml`:
     ```
     image: getmeili/meilisearch:v1.27.0
     args:
       - meilisearch
       - --import-dump
       - /meili_data/dumps/20251201-213154576.dump
     ```
   - Apply and scale to 1; watch logs for successful import (`All documents successfully imported.`).
7. **Return to normal config**:
   - Remove the `args` block.
   - Apply the manifest; the pod should start cleanly on 1.27.0.
8. **Verify**:
   ```
   kubectl exec -n default deploy/karakeep-meilisearch -- \
     sh -c 'curl -s "http://localhost:7700/indexes" -H "Authorization: Bearer $MEILI_MASTER_KEY"'
   kubectl exec -n default deploy/karakeep-meilisearch -- \
     sh -c 'curl -s "http://localhost:7700/indexes/bookmarks/stats" -H "Authorization: Bearer $MEILI_MASTER_KEY"'
   ```
9. **Cleanup**:
   - Remove the staged dump from the PVC: `kubectl exec -n default deploy/karakeep-meilisearch -- rm -f /meili_data/dumps/20251201-213154576.dump`
   - Delete the local backup when you’re satisfied: `rm /tmp/karakeep-meili-20251201.dump`

### Notes
- PVC access mode is `ReadWriteOnce`; keep `strategy: Recreate` on the Deployment to avoid multi-attach errors during rollouts.
- PodSecurity warnings appear because the chart lacks restricted defaults; functional but noisy. Consider adding `runAsNonRoot`, dropping capabilities, and `seccompProfile` later.
