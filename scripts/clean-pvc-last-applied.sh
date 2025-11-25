#!/usr/bin/env bash
set -euo pipefail

# Remove kubectl last-applied annotations from PVCs in the default namespace.
# This avoids immutable field errors (e.g., volumeName) when reapplying manifests.

log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*"; }

command -v kubectl >/dev/null 2>&1 || { log "Missing dependency: kubectl"; exit 1; }
command -v jq >/dev/null 2>&1 || { log "Missing dependency: jq"; exit 1; }

NAMESPACE="${NAMESPACE:-default}"

log "Removing kubectl.kubernetes.io/last-applied-configuration from PVCs in namespace '${NAMESPACE}'"

kubectl -n "$NAMESPACE" get pvc -o json \
  | jq -r '.items[] | select(.metadata.annotations["kubectl.kubernetes.io/last-applied-configuration"]) | .metadata.name' \
  | xargs -r -n1 -I{} kubectl -n "$NAMESPACE" annotate pvc {} kubectl.kubernetes.io/last-applied-configuration-

log "Done."
