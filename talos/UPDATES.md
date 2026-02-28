# Talos/Kubernetes Upgrade Notes (v1.12.4 / v1.35.0)

This document summarizes the successful upgrade process performed in February 2026.

## Cluster Upgrade Overview

- Talos upgraded to v1.12.4 via `tuppr` (all control-plane nodes).
- Kubernetes v1.35.0 is current; target upgrade to v1.35.2 is pending for the next maintenance window.
- Longhorn volume health checks integrated into the automated upgrade process.

## Problems Observed

- No significant issues reported; `tuppr` handled the Talos node transitions and health checks smoothly.

---

# Talos/Kubernetes Upgrade Notes (v1.12.0 / v1.35.0)

This document summarizes the manual upgrade process and the issues encountered during the Kubernetes v1.35.0 rollout on the Talos cluster.

## What Changed in Git

- `talos/talconfig.yaml`: pinned kubelet image to `ghcr.io/siderolabs/kubelet:v1.35.0`.
- `talos/talconfig.yaml`: removed the `stableHostname: true` patch to unblock `talhelper genconfig`.

## Cluster Upgrade Overview

- Talos upgraded to v1.12.0 (all control-plane nodes).
- Kubernetes upgraded to v1.35.0, one node at a time.

## Key Commands Used

### Talos upgrade (one node at a time)

```
talosctl -n <node-ip> upgrade --image factory.talos.dev/installer/284a1fe978ff4e6221a0e95fc1d01278bab28729adcb54bb53f7b0d3f2951dcc:v1.12.0
```

### Kubernetes upgrade (one node at a time)

```
talosctl -n <node-ip> upgrade-k8s --to v1.35.0
```

### Health checks

```
kubectl get nodes
kubectl -n longhorn-system get volumes
```

## Problems Observed During Kubernetes Upgrades

### Symptom

- Node becomes `NotReady`.
- `talosctl services` shows `kubelet` in `Waiting` with: `Waiting for volumes /var/mnt to be mounted`.
- Talos logs show `block.MountController` failures trying to unmount `u-longhorn` with `device or resource busy`.
- Longhorn volumes temporarily degrade during node transitions.

### Example Log Snippet

```
user: warning: [2025-12-26T03:11:37.684885Z]: [talos] controller failed {"component": "controller-runtime", "controller": "block.MountController", "error": "failed to unmount \"u-longhorn\": 2 error(s) occurred:\n\tdevice or resource busy\n\ttimeout"}
```

### Root Cause

The Longhorn data path (`/var/mnt/longhorn`) was busy during the upgrade. Talos attempted to reconcile mounts, but could not unmount the Longhorn unit cleanly, which blocked kubelet startup.

### Recovery Actions

1. Restart kubelet:
   ```
   talosctl -n <node-ip> service kubelet restart
   ```

2. If kubelet still stuck after a few minutes, reboot node:
   ```
   talosctl -n <node-ip> reboot
   ```

3. Wait for `Ready` state and Longhorn volumes to return to `healthy` before upgrading the next node.

## Longhorn Notes

- Longhorn volumes should be `healthy` before starting the next node upgrade.
- Drain operations were blocked by instance-manager PDBs with `minAvailable: 1` and `allowedDisruptions: 0`.
- To drain, use `--delete-emptydir-data` and either:
  - Temporarily relax instance-manager PDBs, or
  - Disable Longhorn scheduling for the node and wait for replicas to move.

### Drain example

```
kubectl drain <node> --ignore-daemonsets --delete-emptydir-data
kubectl uncordon <node>
```

## Observed Disk Error on brainiac-01

- Kernel log showed I/O and EXT4 journal errors on `sdf`, which went offline.
- `/var/mnt/longhorn` itself remained on NVMe and looked healthy.
- Node recovered after reboot; volumes returned to healthy.

## Recommendations for Future Upgrades

- Disable Longhorn scheduling on the node before upgrading.
- Drain the node with `--ignore-daemonsets --delete-emptydir-data`.
- Watch kubelet state and `/var/mnt` mount status; reboot if kubelet remains stuck.
- Wait for all Longhorn volumes to return to `healthy` before proceeding.
