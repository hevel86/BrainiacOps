# Tuppr Deployment and Troubleshooting Guide

## Overview

This document describes the current `tuppr` deployment in BrainiacOps and notes the historical issues that mattered during initial rollout.

Current repo state:

- The controller is deployed by the Argo CD app in [kubernetes/infrastructure/tuppr/app.yaml](/home/michael/gitstuff/BrainiacOps/kubernetes/infrastructure/tuppr/app.yaml:1).
- Upgrade resources live in:
  - [kubernetes/infrastructure/tuppr/config/talos-upgrade.yaml](/home/michael/gitstuff/BrainiacOps/kubernetes/infrastructure/tuppr/config/talos-upgrade.yaml:1)
  - [kubernetes/infrastructure/tuppr/config/kubernetes-upgrade.yaml](/home/michael/gitstuff/BrainiacOps/kubernetes/infrastructure/tuppr/config/kubernetes-upgrade.yaml:1)
- The chart version currently deployed is `0.1.9`.
- BrainiacOps does not currently use a separate `tuppr-crds` Argo CD app or a dedicated image tag override in `app.yaml`.

## Current Deployment Model

BrainiacOps uses two long-lived upgrade resources instead of creating a new manifest per upgrade:

- One `TalosUpgrade` named `talos-upgrade`
- One `KubernetesUpgrade` named `kubernetes-upgrade`

Upgrades are normally performed by editing the target version in those manifests and updating `talos/talconfig.yaml` in the same PR so Git remains the source of truth.

## Historical Notes

### Cluster Connectivity Loss

During the initial rollout, Service `LoadBalancer` IPs became unreachable because every control-plane node carried the `node.kubernetes.io/exclude-from-external-load-balancers` label. Since this cluster is entirely control-plane nodes, MetalLB had nowhere to announce from.

The fix was:

1. Remove the label patch from `talos/talconfig.yaml`
2. Regenerate Talos config with `talhelper genconfig`
3. Apply the new node configuration

### Maintenance Window Phase Validation

An early CRD schema did not include the `MaintenanceWindow` phase in the validation enum, which caused controller errors. Upstream `tuppr` now includes that phase in the API type, and BrainiacOps monitoring expects it.

## Verification

Check the Argo CD apps:

- `tuppr`
- `tuppr-config`

Both should be `Synced` and `Healthy`.

Basic runtime checks:

```bash
kubectl get applications -n argocd
kubectl get talosupgrade
kubectl get kubernetesupgrade
kubectl get pods -n system-upgrade
```

## Kubernetes Upgrade Operations

### Running Outside the Normal Maintenance Window

The `KubernetesUpgrade` resource only starts during an open maintenance window. To force a same-day retry, add a temporary second window to [kubernetes/infrastructure/tuppr/config/kubernetes-upgrade.yaml](/home/michael/gitstuff/BrainiacOps/kubernetes/infrastructure/tuppr/config/kubernetes-upgrade.yaml:1), then remove it once the upgrade finishes.

```yaml
maintenance:
  windows:
    - start: "0 3 * * 0"
      duration: "4h"
      timezone: "America/New_York"
    - start: "30 14 * * 0"   # temporary - remove after upgrade completes
      duration: "4h"
      timezone: "America/New_York"
```

### Resetting a Failed Upgrade

Current upstream `tuppr` supports resetting a failed upgrade by changing the reset annotation instead of manually patching status fields:

```bash
kubectl annotate kubernetesupgrade kubernetes-upgrade \
  tuppr.home-operations.com/reset="$(date -Iseconds)" --overwrite
```

If a stuck job also needs clearing first:

```bash
kubectl get jobs -n system-upgrade
kubectl delete job <job-name> -n system-upgrade
kubectl annotate kubernetesupgrade kubernetes-upgrade \
  tuppr.home-operations.com/reset="$(date -Iseconds)" --overwrite
```

You can still inspect the current failure details with:

```bash
kubectl describe kubernetesupgrade kubernetes-upgrade
```

### Cross-Upgrade Coordination

Current upstream `tuppr` will not run `TalosUpgrade` and `KubernetesUpgrade` concurrently. If one is active, the other remains pending until the active upgrade reaches a terminal phase.

This means BrainiacOps currently gets two layers of sequencing:

- Time-based sequencing from the staggered maintenance windows
- Controller-level blocking so Talos and Kubernetes upgrades do not execute at the same time

## Known Talos/Kubernetes Upgrade Issues

### Kubelet Stuck on "Waiting for volumes /var/mnt to be mounted"

**Symptom:** During a Kubernetes upgrade, a node goes `NotReady` and `talosctl services` shows:

```text
kubelet   Waiting   Fail   Waiting for volumes /var/mnt to be mounted
```

The `machined` logs show the `block.MountController` looping:

```text
failed to unmount "u-longhorn": device or resource busy, timeout
```

**Cause:** This was a Talos regression present in v1.11.4 through v1.12.4. Longhorn processes kept the device open while Talos tried to recycle the user volume mount during kubelet restart.

**Fix:** Reboot the affected node.

```bash
talosctl -n <node-ip> reboot
```

Wait for the node to return `Ready` and verify:

```bash
kubectl get nodes -o wide
```

**Status:** The permanent fix landed in Talos v1.12.5 and later. This remains useful only as a historical troubleshooting note for older upgrade runs.

### Tuppr Job Stuck After Node Reboot

**Symptom:** After rebooting a node during a Kubernetes upgrade recovery, the node returns `Ready` at the target version but the upgrade job remains stuck.

**Cause:** Earlier `tuppr` behavior could wait on kubelet restart acknowledgement even after the node had already come back on the expected version.

**Fix:** Delete the stuck job and reset the upgrade:

```bash
kubectl delete job <job-name> -n system-upgrade
kubectl annotate kubernetesupgrade kubernetes-upgrade \
  tuppr.home-operations.com/reset="$(date -Iseconds)" --overwrite
```

**Status:** Treat this as a historical edge case, not the normal expected path on current Talos and current `tuppr`.

### Do Not Pin `kubelet.image` in talconfig.yaml

If `kubelet.image` is explicitly pinned in `talos/talconfig.yaml`, it creates a second source of truth that can undo a `tuppr`-managed Kubernetes upgrade on the next `talhelper genconfig` and apply cycle.

The correct model is:

- `talos/talconfig.yaml` owns `kubernetesVersion`
- `tuppr` performs the actual rolling Kubernetes upgrade
- `kubelet.image` should not be independently pinned in Talos patches

---
Created: 2026-02-17
Updated: 2026-04-28
