# Longhorn PVC Storage Analysis

**Last Updated:** 2026-01-12 15:51:01 UTC

## Executive Summary

- **Total Allocated:** 1,139.0 GiB
- **Total Used:** 205.8 GiB
- **Overall Efficiency:** 18%
- **Total Waste:** 933.2 GiB (82% unused storage)
- **Storage Class:** longhorn / longhorn-prod
- **Replica Count:** 3 (across brainiac-00, brainiac-01, brainiac-02)

## Current PVC Inventory

### Large Volumes (100+ GiB)

| PVC Name | Allocated | Used | Usage % | Waste | Status |
|----------|-----------|------|---------|-------|--------|
| default/sabnzbd-incomplete-pvc-lh | 250.0 GiB | 4.4 GiB | 2% | 245.6 GiB | 🔴 Severely over-allocated |
| default/plex-config-pvc | 250.0 GiB | 97.7 GiB | 39% | 152.3 GiB | ⚠️ Over-allocated |
| default/opencloud-data-pvc-lh | 100.0 GiB | 2.3 GiB | 2% | 97.7 GiB | 🔴 Severely over-allocated |
| default/nextcloud-data-pvc | 100.0 GiB | 2.4 GiB | 2% | 97.6 GiB | 🔴 Severely over-allocated |
| default/jellyfin-config-lh | 100.0 GiB | 51.9 GiB | 52% | 48.1 GiB | ✅ Acceptable |

### Medium Volumes (15-100 GiB)

| PVC Name | Allocated | Used | Usage % | Waste | Status |
|----------|-----------|------|---------|-------|--------|
| default/handbrake-output-pvc | 50.0 GiB | 1.0 GiB | 2% | 49.0 GiB | 🔴 Severely over-allocated |
| default/karakeep-data-pvc-lh | 20.0 GiB | 0.6 GiB | 3% | 19.4 GiB | 🔴 Severely over-allocated |
| default/obsidian-config-lh | 20.0 GiB | 0.6 GiB | 3% | 19.4 GiB | 🔴 Severely over-allocated |
| default/minecraft-creative-data-longhorn | 20.0 GiB | 1.1 GiB | 6% | 18.9 GiB | 🔴 Severely over-allocated |
| default/tdarr-config | 20.0 GiB | 1.2 GiB | 6% | 18.8 GiB | 🔴 Severely over-allocated |
| default/minecraft-survival-data-longhorn | 20.0 GiB | 1.8 GiB | 9% | 18.2 GiB | 🔴 Severely over-allocated |
| default/romm-resources-pvc | 20.0 GiB | 17.2 GiB | 86% | 2.8 GiB | ✅ Good |

### Standard Config Volumes (7-15 GiB)

| PVC Name | Allocated | Used | Usage % | Waste | Status |
|----------|-----------|------|---------|-------|--------|
| default/stirling-pdf-config-pvc-lh | 10.0 GiB | 0.2 GiB | 2% | 9.8 GiB | 🔴 Severely over-allocated |
| default/karakeep-meilisearch-pvc-lh | 10.0 GiB | 0.3 GiB | 3% | 9.7 GiB | 🔴 Severely over-allocated |
| default/vikunja-data-pvc-lh | 10.0 GiB | 0.3 GiB | 3% | 9.7 GiB | 🔴 Severely over-allocated |
| default/komga-config-lh | 10.0 GiB | 0.4 GiB | 4% | 9.6 GiB | 🔴 Severely over-allocated |
| default/mealie-data-pvc-lh | 10.0 GiB | 0.4 GiB | 4% | 9.6 GiB | 🔴 Severely over-allocated |
| default/syncthing-config | 10.0 GiB | 0.5 GiB | 5% | 9.5 GiB | 🔴 Severely over-allocated |
| default/mysql-data-pvc | 10.0 GiB | 0.5 GiB | 5% | 9.5 GiB | 🔴 Severely over-allocated |
| default/bazarr-config | 10.0 GiB | 0.8 GiB | 8% | 9.2 GiB | 🔴 Severely over-allocated |
| default/minecraft-fox-data-longhorn | 10.0 GiB | 0.9 GiB | 9% | 9.1 GiB | 🔴 Severely over-allocated |
| default/sabnzbd-config | 10.0 GiB | 1.2 GiB | 12% | 8.8 GiB | ⚠️ Could reduce |
| default/sonarr-config | 10.0 GiB | 3.8 GiB | 38% | 6.2 GiB | ⚠️ Over-allocated |
| default/radarr-config | 10.0 GiB | 6.8 GiB | 68% | 3.2 GiB | ✅ Acceptable |

### Small Volumes (3-7 GiB)

| PVC Name | Allocated | Used | Usage % | Waste | Status |
|----------|-----------|------|---------|-------|--------|
| default/opencloud-config-pvc-lh | 5.0 GiB | 0.2 GiB | 4% | 4.8 GiB | 🔴 Severely over-allocated |
| default/romm-assets-pvc | 5.0 GiB | 0.2 GiB | 4% | 4.8 GiB | 🔴 Severely over-allocated |
| default/semaphore-postgres-pvc-lh | 5.0 GiB | 0.3 GiB | 6% | 4.7 GiB | 🔴 Severely over-allocated |
| default/prowlarr-config-lh | 5.0 GiB | 0.7 GiB | 15% | 4.3 GiB | ⚠️ Could reduce |
| default/nextcloud-mariadb-config-pvc | 5.0 GiB | 1.4 GiB | 28% | 3.6 GiB | ⚠️ Over-allocated |
| default/tautulli-config-lh | 5.0 GiB | 1.8 GiB | 36% | 3.2 GiB | ⚠️ Over-allocated |

### Minimal Volumes (<3 GiB)

| PVC Name | Allocated | Used | Usage % | Waste | Status |
|----------|-----------|------|---------|-------|--------|
| default/handbrake-config-pvc | 2.0 GiB | 0.1 GiB | 5% | 1.9 GiB | 🔴 Severely over-allocated |
| default/stirling-pdf-logs-pvc-lh | 2.0 GiB | 0.1 GiB | 5% | 1.9 GiB | 🔴 Severely over-allocated |
| default/romm-redis-data-pvc | 2.0 GiB | 0.1 GiB | 5% | 1.9 GiB | 🔴 Severely over-allocated |
| default/mylar3-watch-pvc-lh | 1.0 GiB | 0.0 GiB | 5% | 1.0 GiB | 🔴 Severely over-allocated |
| portainer/portainer | 1.0 GiB | 0.1 GiB | 7% | 0.9 GiB | 🔴 Severely over-allocated |
| default/semaphore-config-pvc-lh | 1.0 GiB | 0.1 GiB | 7% | 0.9 GiB | 🔴 Severely over-allocated |
| default/romm-config-pvc | 1.0 GiB | 0.1 GiB | 9% | 0.9 GiB | 🔴 Severely over-allocated |
| default/transmission-config-pvc-lh | 1.0 GiB | 0.1 GiB | 9% | 0.9 GiB | 🔴 Severely over-allocated |
| default/audiobookshelf-config-pvc-lh | 1.0 GiB | 0.1 GiB | 10% | 0.9 GiB | 🔴 Severely over-allocated |
| default/transmission-vpn-config | 1.0 GiB | 0.1 GiB | 10% | 0.9 GiB | ⚠️ Could reduce |
| default/n8n-data-pvc-lh | 1.0 GiB | 0.1 GiB | 11% | 0.9 GiB | ⚠️ Could reduce |
| default/semaphore-static-pvc-lh | 1.0 GiB | 0.1 GiB | 12% | 0.9 GiB | ⚠️ Could reduce |
| default/audiobookshelf-metadata-pvc-lh | 1.0 GiB | 0.1 GiB | 12% | 0.9 GiB | ⚠️ Could reduce |
| default/jellyseerr-config-pvc | 1.0 GiB | 0.2 GiB | 21% | 0.8 GiB | ⚠️ Over-allocated |
| default/jdownloader-config-pvc-lh | 1.0 GiB | 0.6 GiB | 56% | 0.4 GiB | ✅ Acceptable |
| default/nextcloud-config-pvc | 1.0 GiB | 0.7 GiB | 70% | 0.3 GiB | ✅ Good |

## Recommendations for Space Optimization

### Critical Priority (High Impact)

**Potential Recovery: ~560 GiB**


1. **default/sabnzbd-incomplete-pvc-lh**: 250Gi → 5Gi (saves ~245 GiB)
   - Currently using 4.4 GiB (2%)
   - File: `kubernetes/apps/default/sabnzbd-incomplete-pvc-lh/pvc.yaml`

2. **default/plex-config-pvc**: 250Gi → 147Gi (saves ~103 GiB)
   - Currently using 97.7 GiB (39%)
   - File: `kubernetes/apps/default/plex-config-pvc/pvc.yaml`

3. **default/opencloud-data-pvc-lh**: 100Gi → 3Gi (saves ~97 GiB)
   - Currently using 2.3 GiB (2%)
   - File: `kubernetes/apps/default/opencloud-data-pvc-lh/pvc.yaml`

4. **default/nextcloud-data-pvc**: 100Gi → 4Gi (saves ~96 GiB)
   - Currently using 2.4 GiB (2%)
   - File: `kubernetes/apps/default/nextcloud-data-pvc/pvc.yaml`

5. **default/handbrake-output-pvc**: 50Gi → 2Gi (saves ~48 GiB)
   - Currently using 1.0 GiB (2%)
   - File: `kubernetes/apps/default/handbrake-output-pvc/pvc.yaml`

6. **default/karakeep-data-pvc-lh**: 20Gi → 2Gi (saves ~18 GiB)
   - Currently using 0.6 GiB (3%)
   - File: `kubernetes/apps/default/karakeep-data-pvc-lh/pvc.yaml`

7. **default/obsidian-config-lh**: 20Gi → 2Gi (saves ~18 GiB)
   - Currently using 0.6 GiB (3%)
   - File: `kubernetes/apps/default/obsidian-config-lh/pvc.yaml`

8. **default/minecraft-creative-data-longhorn**: 20Gi → 2Gi (saves ~18 GiB)
   - Currently using 1.1 GiB (6%)
   - File: `kubernetes/apps/default/minecraft-creative-data-longhorn/pvc.yaml`


### Medium Priority (Moderate Impact)

**Potential Recovery: ~66 GiB**


9. **default/stirling-pdf-config-pvc-lh**: 10Gi → 2Gi
10. **default/karakeep-meilisearch-pvc-lh**: 10Gi → 2Gi
11. **default/vikunja-data-pvc-lh**: 10Gi → 2Gi
12. **default/komga-config-lh**: 10Gi → 2Gi
13. **default/mealie-data-pvc-lh**: 10Gi → 2Gi
14. **default/syncthing-config**: 10Gi → 2Gi
15. **default/mysql-data-pvc**: 10Gi → 2Gi
16. **default/bazarr-config**: 10Gi → 2Gi
17. **default/minecraft-fox-data-longhorn**: 10Gi → 2Gi
18. **default/sabnzbd-config**: 10Gi → 2Gi

## PVC Expansion Process

To expand a Longhorn PVC:

```bash
# 1. Edit the PVC manifest to increase storage size
# 2. Apply the updated manifest
kubectl apply -f kubernetes/apps/default/<app>/pvc.yaml

# 3. Restart the deployment to trigger filesystem resize
kubectl rollout restart deployment/<app> -n default

# 4. Wait for rollout to complete
kubectl rollout status deployment/<app> -n default

# 5. Verify expansion
kubectl get pvc -n default <pvc-name>
```

**Note:** Some PVCs require a second restart for the filesystem resize to complete. Check for `FileSystemResizePending` condition:

```bash
kubectl describe pvc -n default <pvc-name>
```

## Storage Efficiency by Category

| Category | Count | Total Allocated | Total Used | Efficiency | Waste |
|----------|-------|-----------------|------------|------------|-------|
| Large (100+ GiB) | 5 | 800 GiB | 159 GiB | 20% | 641 GiB |
| Medium (15-100 GiB) | 7 | 170 GiB | 24 GiB | 14% | 146 GiB |
| Standard (7-15 GiB) | 12 | 120 GiB | 16 GiB | 13% | 104 GiB |
| Small (3-7 GiB) | 6 | 30 GiB | 5 GiB | 15% | 25 GiB |
| Minimal (<3 GiB) | 16 | 19 GiB | 3 GiB | 14% | 16 GiB |

## Longhorn Storage Architecture

- **Cluster:** talos-rao
- **Nodes:** 3 (brainiac-00, brainiac-01, brainiac-02)
- **Default Replica Count:** 3 (data on all nodes)
- **Storage Classes:**
  - `longhorn`: Standard replication
  - `longhorn-prod`: 3 replicas with `dataLocality: best-effort`
- **High Availability:** Automatic pod failover on node failure
- **Disk Requirements:** >= 1.5TB for Longhorn data disks

## Notes

- This analysis excludes NFS-backed volumes (media-movies, media-tv, plex-zfstranscode, etc.)
- All sizes reflect actual Longhorn volume allocations with 3-way replication
- Total physical storage used = Used * 3 replicas = ~617 GiB across cluster
- Longhorn auto-snapshots may increase actual disk usage beyond reported values
