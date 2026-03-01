# Tuppr Deployment and Troubleshooting Guide

## Overview
This document details the resolution of deployment issues with `tuppr` (Talos Upgrade Controller) and associated cluster connectivity problems encountered during the initial setup.

## Issue 1: Image Pull BackOff (Tag 0.0.0)
**Symptom:** `tuppr` pod failed to start with `ImagePullBackOff` for tag `0.0.0`.
**Cause:** The Helm chart defaults to `0.0.0` if no tag is provided.
**Fix:** Explicitly set the image tag in the Argo CD Application manifest.
```yaml
helm:
  parameters:
    - name: image.tag
      value: "0.0.72"
```

## Issue 2: Missing CRDs for Tuppr Config
**Symptom:** `tuppr-config` Application failed to sync with "no matches for kind KubernetesUpgrade".
**Cause:** The `tuppr` Helm chart does not include CRDs in its default installation.
**Fix:**
1.  Extracted CRDs from the chart source.
2.  Placed them in `kubernetes/infrastructure/tuppr/crds/`.
3.  Renamed files to `kubernetes-upgrades.yaml` and `talos-upgrades.yaml` for clarity.
4.  Added a `tuppr-crds` Application to `app.yaml` to install them.

## Issue 3: Cluster Connectivity Loss (Ingress/Service IPs)
**Symptom:** Loss of access to all Service LoadBalancer IPs (e.g., Argo CD at `10.0.0.209`).
**Cause:** All control plane nodes had the label `node.kubernetes.io/exclude-from-external-load-balancers`. Since the cluster is 100% control plane nodes, MetalLB had no nodes to announce from.
**Fix:**
1.  Removed the label patch from `talos/talconfig.yaml`.
2.  Regenerated Talos config (`talhelper genconfig`).
3.  Applied the new configuration to all nodes (`talosctl apply-config`).

## Issue 4: CRD Enum Validation Error
**Symptom:** `tuppr` controller logs showed repeated errors: `Invalid value: "MaintenanceWindow"`.
**Cause:** The status phase `MaintenanceWindow` was missing from the `enum` validation list in the CRD schema.
**Fix:**
1.  Edited `kubernetes-upgrades.yaml` and `talos-upgrades.yaml`.
2.  Added `MaintenanceWindow` to the `status.phase` enum list.

## Verification
- **Tuppr**: Ensure `tuppr`, `tuppr-crds`, and `tuppr-config` apps are `Synced` and `Healthy` in Argo CD.
- **Connectivity**: Verify access to Argo CD UI and other services.

---

## Kubernetes Upgrade Operations

### Running an Upgrade Outside the Maintenance Window

The `KubernetesUpgrade` resource only runs during configured maintenance windows. To trigger an upgrade at a different time (e.g., to retry a failed upgrade the same day), add a temporary second window to `kubernetes/infrastructure/tuppr/config/kubernetes-upgrade.yaml`:

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

Then reset the phase if the upgrade is in `Failed` state (see below) and remove the temporary window once done.

### Resetting a Failed Upgrade

When tuppr marks an upgrade as `Failed` it stops all processing. Check the failure reason:

```bash
kubectl describe kubernetesupgrade kubernetes-upgrade
```

To reset and retry:

```bash
kubectl patch kubernetesupgrade kubernetes-upgrade \
  --type=merge --subresource=status \
  -p '{"status":{"phase":"Pending","retries":0,"lastError":"","message":""}}'
```

If there is a stuck job that needs clearing first:

```bash
kubectl get jobs -n system-upgrade
kubectl delete job <job-name> -n system-upgrade
# then reset the phase as above
```

### Issue 5: Kubelet Stuck on "Waiting for volumes /var/mnt to be mounted"

**Symptom:** During a Kubernetes upgrade, a node goes `NotReady` and `talosctl services` shows:
```
kubelet   Waiting   Fail   Waiting for volumes /var/mnt to be mounted
```
The `machined` logs show the `block.MountController` looping:
```
failed to unmount "u-longhorn": device or resource busy, timeout
```

**Cause:** This is a confirmed Talos bug ([siderolabs/talos#12797](https://github.com/siderolabs/talos/issues/12797)), a regression present in Talos v1.11.4 through v1.12.4. When the kubelet service restarts due to a machine config change, Talos's `block.MountController` tries to cycle the `u-longhorn` user volume mount. Longhorn's replica and engine processes keep the block device open at the kernel level, causing the unmount to fail and the kubelet to never start.

**Fix:** Reboot the affected node. The clean shutdown releases the device and the kubelet starts normally with the new config on boot.

```bash
talosctl -n <node-ip> reboot
```

Wait for the node to return `Ready` and verify the kubelet version:

```bash
kubectl get nodes -o wide
```

**Permanent fix:** Upgrade to Talos v1.12.5 or later, which contains the fix from PR #12819.

**Note:** This can affect each node in sequence during a Kubernetes upgrade. After rebooting one node, wait for Longhorn volumes to return to `healthy` before the next node is attempted — tuppr's health check gates this automatically.

### Issue 6: Tuppr Job Stuck After Node Reboot

**Symptom:** After rebooting a node to recover from Issue 5, the node comes back `Ready` at the correct Kubernetes version, but the tuppr upgrade job remains stuck on `waiting for kubelet restart` indefinitely and never proceeds to the next node.

**Cause:** `talosctl upgrade-k8s` waits for a machine config generation acknowledgment from the kubelet service rather than simply checking the running version. After a reboot, the kubelet is already running at the target version, but the job doesn't detect this and waits forever.

**Fix:** Delete the stuck job and reset the phase. Tuppr will create a new job, detect the rebooted node is already at the target version, and proceed to the next node.

```bash
kubectl delete job <job-name> -n system-upgrade
kubectl patch kubernetesupgrade kubernetes-upgrade \
  --type=merge --subresource=status \
  -p '{"status":{"phase":"Pending","retries":0,"lastError":"","message":""}}'
```

This is a tuppr limitation that will be resolved once Talos v1.12.5 is available, since the kubelet will restart cleanly without requiring a reboot.

### Issue 7: Do Not Pin `kubelet.image` in talconfig.yaml

**Symptom:** After tuppr completes a Kubernetes upgrade, running `talhelper genconfig && talosctl apply-config` reverts the kubelet to an older version. Alternatively, Renovate creates PRs that bump the kubelet image independently of the upgrade cycle, causing extra machine config changes and triggering the volume unmount issue (Issue 5) more frequently.

**Cause:** If `kubelet.image` is explicitly pinned in `talos/talconfig.yaml` patches, it creates two independent systems managing the same field: Renovate (via talconfig) and tuppr (via direct machine config patch). After tuppr upgrades the kubelet, the talconfig pin becomes stale.

**Fix:** Remove the `kubelet.image` pin from talconfig.yaml entirely. The `kubernetesVersion` field at the top of talconfig is the correct source of truth. Tuppr manages the kubelet image exclusively during upgrades.

```yaml
# Remove this from talconfig.yaml patches:
kubelet:
  # renovate: datasource=docker depName=ghcr.io/siderolabs/kubelet
  image: ghcr.io/siderolabs/kubelet:vX.XX.X   # <-- remove these two lines
  extraMounts:
    ...
```

---
*Created: 2026-02-17*
*Updated: 2026-03-01 — Added upgrade operations, Issues 5–7*
