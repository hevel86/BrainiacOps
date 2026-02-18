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
*Created: 2026-02-17*
