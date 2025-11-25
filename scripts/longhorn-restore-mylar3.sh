#!/usr/bin/env bash
set -euo pipefail

BACKUP_TARGET="${BACKUP_TARGET:-nfs://truenas1-nfs.torquasmvo.internal:/mnt/fast/longhorn-backup}"
EXECUTE=0
USE_BACKUP_VOLUME_NAME=1
TARGET_PVC="mylar3-config-pvc-lh"
TARGET_NS="default"
FRONTEND="blockdev"
RECURRING_JOB_GROUP="${RECURRING_JOB_GROUP:-prod}"

usage() {
  cat <<EOF
Usage: $0 [--execute] [--use-backup-volume-name]
Restore ONLY the mylar3 volume from its latest Longhorn backup on the NFS target.
Defaults to dry-run (no changes). Set BACKUP_TARGET env var to override target.
Set RECURRING_JOB_GROUP env var to pick a recurring job group (default: prod).

  --execute                  Perform the restore (create Volume/PV/PVC). Otherwise dry-run.
  --use-backup-volume-name   Restore with the original Longhorn volume name ("Use Previous Name" in UI). (default)
EOF
}

for arg in "$@"; do
  case "$arg" in
    --execute) EXECUTE=1 ;;
    --use-backup-volume-name) USE_BACKUP_VOLUME_NAME=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $arg" >&2; usage; exit 1 ;;
  esac
done

log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*"; }

require() { command -v "$1" >/dev/null 2>&1 || { log "Missing dependency: $1"; exit 1; }; }
require kubectl
require jq

data="$(
  kubectl -n longhorn-system get backupvolumes.longhorn.io -o json \
  | jq -r --arg pvc "$TARGET_PVC" --arg ns "$TARGET_NS" '.items[]
    | select(.status.lastBackupName != null)
    | select((.status.labels.KubernetesStatus | try fromjson | .pvcName == $pvc) and
             (.status.labels.KubernetesStatus | try fromjson | .namespace == $ns))
    | [
        .spec.volumeName,
        .metadata.name,
        .status.lastBackupName,
        (.status.size // "0"),
        (.status.storageClassName // "longhorn"),
        (.status.labels."longhorn.io/volume-access-mode" // "rwo"),
        (.status.labels.KubernetesStatus | try fromjson | .namespace // empty),
        (.status.labels.KubernetesStatus | try fromjson | .pvcName // empty),
        (.status.labels.KubernetesStatus | try fromjson | .pvName // empty)
      ] | @tsv'
)"

if [[ -z "$data" ]]; then
  log "No matching backup volume found for ${TARGET_NS}/${TARGET_PVC}; nothing to do."
  exit 0
fi

while IFS=$'\t' read -r VOL_NAME BACKUP_VOLUME LAST_BACKUP SIZE_BYTES STORAGE_CLASS ACCESS_LABEL PVC_NS PVC_NAME PV_NAME_FROM_BACKUP; do
  case "${ACCESS_LABEL,,}" in
    rwx|readwriteoncepod|readwritemany) ACCESS_MODE="ReadWriteMany" ;;
    *) ACCESS_MODE="ReadWriteOnce" ;;
  esac

  if [[ -n "$PV_NAME_FROM_BACKUP" ]]; then
    PV_NAME="$PV_NAME_FROM_BACKUP"
  else
    PV_NAME="pv-${PVC_NS}-${PVC_NAME}"
  fi
  RJG_LABEL_KEY="recurring-job-group.longhorn.io/${RECURRING_JOB_GROUP}"
  if [[ "$USE_BACKUP_VOLUME_NAME" -eq 1 ]]; then
    RESTORE_VOLUME="${VOL_NAME}"
  else
    RESTORE_VOLUME="${PVC_NAME}"
  fi
  if kubectl -n "$PVC_NS" get pvc "$PVC_NAME" >/dev/null 2>&1; then
    EXISTING_PV_NAME="$(kubectl -n "$PVC_NS" get pvc "$PVC_NAME" -o jsonpath='{.spec.volumeName}' 2>/dev/null || true)"
    if [[ -n "$EXISTING_PV_NAME" && "$RESTORE_VOLUME" != "$EXISTING_PV_NAME" ]]; then
      log "PVC ${PVC_NS}/${PVC_NAME} bound to PV ${EXISTING_PV_NAME}; using volume name ${EXISTING_PV_NAME} for restore instead of ${RESTORE_VOLUME}"
      RESTORE_VOLUME="${EXISTING_PV_NAME}"
    fi
  fi
  FROM_BACKUP="${BACKUP_TARGET}?volume=${VOL_NAME}&backup=${LAST_BACKUP}"
  STORAGE_GI="$(( (SIZE_BYTES + (1<<30) - 1) / (1<<30) ))Gi"

  log "Volume: $RESTORE_VOLUME | PVC: ${PVC_NS}/${PVC_NAME} | StorageClass: $STORAGE_CLASS | AccessMode: $ACCESS_MODE | Size: $STORAGE_GI | LatestBackup: $LAST_BACKUP | SourceVol: $VOL_NAME | RecurringJobGroup: $RECURRING_JOB_GROUP"

  if [[ "$EXECUTE" -eq 0 ]]; then
    continue
  fi

  kubectl get namespace "$PVC_NS" >/dev/null 2>&1 || kubectl create namespace "$PVC_NS"

  if ! kubectl -n longhorn-system get volume "$RESTORE_VOLUME" >/dev/null 2>&1; then
    cat <<EOF | kubectl apply -f -
apiVersion: longhorn.io/v1beta2
kind: Volume
metadata:
  name: ${RESTORE_VOLUME}
  namespace: longhorn-system
  labels:
    ${RJG_LABEL_KEY}: enabled
spec:
  fromBackup: ${FROM_BACKUP}
  numberOfReplicas: 3
  staleReplicaTimeout: 30
  frontend: ${FRONTEND}
EOF
  else
    log "Volume $RESTORE_VOLUME already exists; skipping volume create"
  fi

  if ! kubectl get pv "$PV_NAME" >/dev/null 2>&1; then
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolume
metadata:
  name: ${PV_NAME}
spec:
  capacity:
    storage: ${STORAGE_GI}
  volumeMode: Filesystem
  accessModes:
    - ${ACCESS_MODE}
  persistentVolumeReclaimPolicy: Retain
  storageClassName: ${STORAGE_CLASS}
  claimRef:
    namespace: ${PVC_NS}
    name: ${PVC_NAME}
  csi:
    driver: driver.longhorn.io
    fsType: ext4
    volumeHandle: ${RESTORE_VOLUME}
EOF
  else
    log "PV $PV_NAME already exists; skipping PV create"
  fi

  cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ${PVC_NAME}
  namespace: ${PVC_NS}
spec:
  accessModes:
    - ${ACCESS_MODE}
  storageClassName: ${STORAGE_CLASS}
  resources:
    requests:
      storage: ${STORAGE_GI}
  volumeMode: Filesystem
  volumeName: ${PV_NAME}
EOF

done <<<"$data"

if [[ "$EXECUTE" -eq 0 ]]; then
  log "Dry-run complete. Re-run with --execute to perform the mylar3 restore."
else
  log "Mylar3 restore completed."
  log "Assigning Longhorn recurring job group '${RECURRING_JOB_GROUP}' to volume ${RESTORE_VOLUME}"
  kubectl -n longhorn-system patch volume "${RESTORE_VOLUME}" --type=merge -p "$(jq -n --arg k "${RJG_LABEL_KEY}" '{"metadata":{"labels":{($k):"enabled"}}}')" || log "Warning: failed to set recurring job group on ${RESTORE_VOLUME}"
fi
