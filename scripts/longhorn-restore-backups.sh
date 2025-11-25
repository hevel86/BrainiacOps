#!/usr/bin/env bash
set -euo pipefail

BACKUP_TARGET="${BACKUP_TARGET:-nfs://truenas1-nfs.torquasmvo.internal:/mnt/fast/longhorn-backup}"
EXECUTE=0
USE_BACKUP_VOLUME_NAME=1
RECURRING_JOB_GROUP="${RECURRING_JOB_GROUP:-prod}"
FRONTEND="${FRONTEND:-blockdev}"

usage() {
  cat <<EOF
Usage: $0 [--execute] [--use-backup-volume-name]
Restore Longhorn volumes from latest backups on the configured NFS target.
Defaults to dry-run (no changes). Set BACKUP_TARGET env var to override target.
Set RECURRING_JOB_GROUP env var to pick a recurring job group (default: prod).
Set FRONTEND env var if you need a different Longhorn frontend (default: blockdev).

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
  | jq -r '.items[]
    | select(.status.lastBackupName != null)
    | [
        .spec.volumeName,
        .metadata.name,
        .status.lastBackupName,
        (.status.size // "0"),
        (.status.storageClassName // "longhorn"),
        (.status.labels."longhorn.io/volume-access-mode" // "rwo"),
        (.status.labels.KubernetesStatus | try fromjson | .namespace // empty),
        (.status.labels.KubernetesStatus | try fromjson | .pvcName // empty)
      ] | @tsv'
)"

if [[ -z "$data" ]]; then
  log "No backup volumes with a last backup found; nothing to do."
  exit 0
fi

while IFS=$'\t' read -r VOL_NAME BACKUP_VOLUME LAST_BACKUP SIZE_BYTES STORAGE_CLASS ACCESS_LABEL PVC_NS PVC_NAME; do
  case "${ACCESS_LABEL,,}" in
    rwx|readwriteoncepod|readwritemany) ACCESS_MODE="ReadWriteMany" ;;
    *) ACCESS_MODE="ReadWriteOnce" ;;
  esac

  if [[ -z "$PVC_NS" || -z "$PVC_NAME" ]]; then
    log "Missing PVC namespace/name for backup volume $BACKUP_VOLUME; skipping"
    continue
  fi

  PV_NAME="pv-${PVC_NS}-${PVC_NAME}"
  RJG_LABEL_KEY="recurring-job-group.longhorn.io/${RECURRING_JOB_GROUP}"
  if [[ "$USE_BACKUP_VOLUME_NAME" -eq 1 ]]; then
    RESTORE_VOLUME="${VOL_NAME}"
  else
    RESTORE_VOLUME="${PVC_NAME}"
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

  log "Ensuring recurring job group label '${RECURRING_JOB_GROUP}' on volume ${RESTORE_VOLUME}"
  kubectl -n longhorn-system patch volume "${RESTORE_VOLUME}" --type=merge -p "$(jq -n --arg k "${RJG_LABEL_KEY}" '{"metadata":{"labels":{($k):"enabled"}}}')" || log "Warning: failed to set recurring job group on ${RESTORE_VOLUME}"

done <<<"$data"

if [[ "$EXECUTE" -eq 0 ]]; then
  log "Dry-run complete. Re-run with --execute to perform restores."
else
  log "Restore run completed."
fi
