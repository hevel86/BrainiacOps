# Archived Minecraft Manifests

> [!WARNING]
> The files in this directory are for archival and one-time migration purposes only. They represent the old NFS-based storage configuration and the jobs used to migrate data to Longhorn.
>
> **Do not apply these manifests to the cluster unless you are intentionally performing a data migration.**

## Contents

This directory contains the Kubernetes manifests that were used before migrating the Minecraft servers' storage from NFS to Longhorn.

### `nfs-pvc.yaml`

This file defines the `PersistentVolume` (PV) and `PersistentVolumeClaim` (PVC) resources that connected the Minecraft pods to the NFS shares on `truenas1-nfs.torquasmvo.internal`. These are retained for historical reference.

### `creative-migrate.yaml` & `survival-migrate.yaml`

These are one-time Kubernetes `Job` manifests designed to migrate the world data.

**How they work:**
1. They mount both the old NFS PVC and the new Longhorn PVC.
2. They use an `alpine` container with `rsync` to copy all data from the old volume (`/old`) to the new one (`/new`).
3. The `rsync` command includes `--chown=1000:1000` to ensure the file permissions are correct for the `itzg/minecraft-server` container.
