#!/usr/bin/env bash
set -euo pipefail

# Longhorn PVC Usage Analysis Script
# Generates a comprehensive markdown report of all Longhorn PVC allocations and usage

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUTPUT_FILE="${REPO_ROOT}/docs/longhorn-pvc-usage.md"

echo "Analyzing Longhorn PVC usage..."

# Fetch data
kubectl get volumes.longhorn.io -n longhorn-system -o json > /tmp/lh-volumes.json
kubectl get pvc -A -o json > /tmp/lh-pvcs.json

# Generate the report using Python
python3 <<'EOF' > "${OUTPUT_FILE}"
import json
from datetime import datetime

# Load data
with open('/tmp/lh-volumes.json', 'r') as f:
    vol_data = json.load(f)

with open('/tmp/lh-pvcs.json', 'r') as f:
    pvc_data = json.load(f)

# Build PVC map for Longhorn volumes only
pvc_map = {}
pvc_storage = {}
for item in pvc_data['items']:
    vol_name = item['spec'].get('volumeName', '')
    storage_class = item['spec'].get('storageClassName', '')
    if vol_name and storage_class in ['longhorn', 'longhorn-prod']:
        ns = item['metadata']['namespace']
        name = item['metadata']['name']
        pvc_map[vol_name] = f'{ns}/{name}'
        pvc_storage[vol_name] = storage_class

# Process volumes
volumes = []
total_allocated = 0
total_used = 0

for item in vol_data['items']:
    if 'size' in item['spec'] and item['spec']['size']:
        vol_id = item['metadata']['name']
        pvc_name = pvc_map.get(vol_id, vol_id)

        # Skip if not a Longhorn PVC
        if vol_id not in pvc_map:
            continue

        allocated = int(item['spec']['size']) / (1024**3)
        used = int(item['status'].get('actualSize', 0)) / (1024**3)
        pct = (used / allocated * 100) if allocated > 0 else 0
        waste = allocated - used
        storage_class = pvc_storage.get(vol_id, 'unknown')

        volumes.append({
            'name': pvc_name,
            'allocated': allocated,
            'used': used,
            'pct': pct,
            'waste': waste,
            'storage_class': storage_class
        })

        total_allocated += allocated
        total_used += used

# Sort by waste (descending)
volumes.sort(key=lambda x: x['waste'], reverse=True)

# Categorize volumes
large_vols = [v for v in volumes if v['allocated'] >= 100]
medium_vols = [v for v in volumes if 15 <= v['allocated'] < 100]
standard_vols = [v for v in volumes if 7 <= v['allocated'] < 15]
small_vols = [v for v in volumes if 3 <= v['allocated'] < 7]
minimal_vols = [v for v in volumes if v['allocated'] < 3]

def get_status(vol):
    """Determine status emoji and text"""
    if vol['pct'] > 100:
        return '🔴 **OVER CAPACITY**'
    elif vol['pct'] >= 70:
        return '✅ Good'
    elif vol['pct'] >= 50:
        return '✅ Acceptable'
    elif vol['pct'] >= 20:
        return '⚠️ Over-allocated'
    elif vol['pct'] >= 10:
        return '⚠️ Could reduce'
    else:
        return '🔴 Severely over-allocated'

def format_table_row(vol):
    """Format a volume as a markdown table row"""
    return f"| {vol['name']} | {vol['allocated']:.1f} GiB | {vol['used']:.1f} GiB | {vol['pct']:.0f}% | {vol['waste']:.1f} GiB | {get_status(vol)} |"

# Generate markdown content
print(f"# Longhorn PVC Storage Analysis")
print(f"\n**Last Updated:** {datetime.now().strftime('%Y-%m-%d %H:%M:%S UTC')}")
print(f"\n## Executive Summary")
print(f"\n- **Total Allocated:** {total_allocated:,.1f} GiB")
print(f"- **Total Used:** {total_used:,.1f} GiB")
print(f"- **Overall Efficiency:** {(total_used/total_allocated*100):.0f}%")
print(f"- **Total Waste:** {(total_allocated-total_used):,.1f} GiB ({((total_allocated-total_used)/total_allocated*100):.0f}% unused storage)")
print(f"- **Storage Class:** longhorn / longhorn-prod")
print(f"- **Replica Count:** 3 (across brainiac-00, brainiac-01, brainiac-02)")

print(f"\n## Current PVC Inventory")

# Large volumes
if large_vols:
    print(f"\n### Large Volumes (100+ GiB)")
    print(f"\n| PVC Name | Allocated | Used | Usage % | Waste | Status |")
    print(f"|----------|-----------|------|---------|-------|--------|")
    for v in large_vols:
        print(format_table_row(v))

# Medium volumes
if medium_vols:
    print(f"\n### Medium Volumes (15-100 GiB)")
    print(f"\n| PVC Name | Allocated | Used | Usage % | Waste | Status |")
    print(f"|----------|-----------|------|---------|-------|--------|")
    for v in medium_vols:
        print(format_table_row(v))

# Standard volumes
if standard_vols:
    print(f"\n### Standard Config Volumes (7-15 GiB)")
    print(f"\n| PVC Name | Allocated | Used | Usage % | Waste | Status |")
    print(f"|----------|-----------|------|---------|-------|--------|")
    for v in standard_vols:
        print(format_table_row(v))

# Small volumes
if small_vols:
    print(f"\n### Small Volumes (3-7 GiB)")
    print(f"\n| PVC Name | Allocated | Used | Usage % | Waste | Status |")
    print(f"|----------|-----------|------|---------|-------|--------|")
    for v in small_vols:
        print(format_table_row(v))

# Minimal volumes
if minimal_vols:
    print(f"\n### Minimal Volumes (<3 GiB)")
    print(f"\n| PVC Name | Allocated | Used | Usage % | Waste | Status |")
    print(f"|----------|-----------|------|---------|-------|--------|")
    for v in minimal_vols:
        print(format_table_row(v))

# Recommendations
print(f"\n## Recommendations for Space Optimization")
print(f"\n### Critical Priority (High Impact)")

critical_waste = [v for v in volumes if v['waste'] > 15 and v['pct'] < 50]
if critical_waste:
    total_recoverable = sum(v['waste'] * 0.8 for v in critical_waste[:8])
    print(f"\n**Potential Recovery: ~{total_recoverable:.0f} GiB**")
    print(f"\n")
    for i, vol in enumerate(critical_waste[:8], 1):
        app_name = vol['name'].split('/')[1] if '/' in vol['name'] else vol['name']
        suggested = max(vol['used'] * 1.5, 2)
        if suggested < 10:
            suggested = min(suggested, 5)
        elif suggested < 50:
            suggested = min(suggested, 20)
        else:
            suggested = min(suggested, vol['allocated'] * 0.6)

        savings = vol['allocated'] - suggested
        if vol['pct'] > 100:
            print(f"{i}. **{vol['name']}**: Currently at {vol['pct']:.0f}% capacity ({vol['used']:.1f} GiB / {vol['allocated']:.1f} GiB)")
            print(f"   - **Action:** Increase to {vol['allocated']*2:.0f}Gi immediately")
        else:
            print(f"{i}. **{vol['name']}**: {vol['allocated']:.0f}Gi → {suggested:.0f}Gi (saves ~{savings:.0f} GiB)")
            print(f"   - Currently using {vol['used']:.1f} GiB ({vol['pct']:.0f}%)")

        # Try to determine the file path
        if '/' in vol['name']:
            ns, pvc = vol['name'].split('/')
            if ns == 'default':
                print(f"   - File: `kubernetes/apps/default/{app_name}/pvc.yaml`")
        print()

# Medium priority
medium_waste = [v for v in volumes if 5 <= v['waste'] < 15 and v['pct'] < 30]
if medium_waste:
    print(f"\n### Medium Priority (Moderate Impact)")
    total_recoverable = sum(v['waste'] * 0.7 for v in medium_waste)
    print(f"\n**Potential Recovery: ~{total_recoverable:.0f} GiB**")
    print(f"\n")
    for i, vol in enumerate(medium_waste[:10], 9):
        suggested = max(vol['used'] * 1.5, 2)
        if suggested < 10:
            suggested = min(suggested, 5)
        else:
            suggested = min(suggested, vol['allocated'] * 0.6)
        print(f"{i}. **{vol['name']}**: {vol['allocated']:.0f}Gi → {suggested:.0f}Gi")

# Over capacity volumes
over_capacity = [v for v in volumes if v['pct'] > 100]
if over_capacity:
    print(f"\n### Immediate Action Required")
    print(f"\n")
    for vol in over_capacity:
        print(f"🔴 **{vol['name']}**: Currently at {vol['pct']:.0f}% capacity ({vol['used']:.1f} GiB / {vol['allocated']:.1f} GiB)")
        print(f"- **Action:** Increase to {vol['allocated']*2:.0f}Gi immediately")
        app_name = vol['name'].split('/')[1] if '/' in vol['name'] else vol['name']
        if '/' in vol['name']:
            ns, pvc = vol['name'].split('/')
            if ns == 'default':
                print(f"- File: `kubernetes/apps/default/{app_name}/pvc.yaml`")
        print()

# PVC Expansion Process
print(f"\n## PVC Expansion Process")
print(f"\nTo expand a Longhorn PVC:")
print(f"\n```bash")
print(f"# 1. Edit the PVC manifest to increase storage size")
print(f"# 2. Apply the updated manifest")
print(f"kubectl apply -f kubernetes/apps/default/<app>/pvc.yaml")
print(f"\n# 3. Restart the deployment to trigger filesystem resize")
print(f"kubectl rollout restart deployment/<app> -n default")
print(f"\n# 4. Wait for rollout to complete")
print(f"kubectl rollout status deployment/<app> -n default")
print(f"\n# 5. Verify expansion")
print(f"kubectl get pvc -n default <pvc-name>")
print(f"```")
print(f"\n**Note:** Some PVCs require a second restart for the filesystem resize to complete. Check for `FileSystemResizePending` condition:")
print(f"\n```bash")
print(f"kubectl describe pvc -n default <pvc-name>")
print(f"```")

# Storage efficiency by category
print(f"\n## Storage Efficiency by Category")
print(f"\n| Category | Count | Total Allocated | Total Used | Efficiency | Waste |")
print(f"|----------|-------|-----------------|------------|------------|-------|")

categories = [
    ("Large (100+ GiB)", large_vols),
    ("Medium (15-100 GiB)", medium_vols),
    ("Standard (7-15 GiB)", standard_vols),
    ("Small (3-7 GiB)", small_vols),
    ("Minimal (<3 GiB)", minimal_vols)
]

for cat_name, cat_vols in categories:
    if cat_vols:
        cat_alloc = sum(v['allocated'] for v in cat_vols)
        cat_used = sum(v['used'] for v in cat_vols)
        cat_eff = (cat_used / cat_alloc * 100) if cat_alloc > 0 else 0
        cat_waste = cat_alloc - cat_used
        print(f"| {cat_name} | {len(cat_vols)} | {cat_alloc:.0f} GiB | {cat_used:.0f} GiB | {cat_eff:.0f}% | {cat_waste:.0f} GiB |")

# Architecture details
print(f"\n## Longhorn Storage Architecture")
print(f"\n- **Cluster:** talos-rao")
print(f"- **Nodes:** 3 (brainiac-00, brainiac-01, brainiac-02)")
print(f"- **Default Replica Count:** 3 (data on all nodes)")
print(f"- **Storage Classes:**")
print(f"  - `longhorn`: Standard replication")
print(f"  - `longhorn-prod`: 3 replicas with `dataLocality: best-effort`")
print(f"- **High Availability:** Automatic pod failover on node failure")
print(f"- **Disk Requirements:** >= 1.5TB for Longhorn data disks")

# Notes
print(f"\n## Notes")
print(f"\n- This analysis excludes NFS-backed volumes (media-movies, media-tv, plex-zfstranscode, etc.)")
print(f"- All sizes reflect actual Longhorn volume allocations with 3-way replication")
print(f"- Total physical storage used = Used * 3 replicas = ~{(total_used * 3):,.0f} GiB across cluster")
print(f"- Longhorn auto-snapshots may increase actual disk usage beyond reported values")
EOF

# Cleanup temp files
rm -f /tmp/lh-volumes.json /tmp/lh-pvcs.json

echo ""
echo "✅ Report generated: ${OUTPUT_FILE}"
echo ""
echo "Summary:"
grep "^- \*\*Total" "${OUTPUT_FILE}" | sed 's/^- /  /'
