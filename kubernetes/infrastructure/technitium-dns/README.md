# Technitium DNS Server

Centralized DNS server for BrainiacOps cluster, replacing Pi-hole instances with Kubernetes-native solution.

## Quick Access

- **DNS Server**: 10.0.0.53 (UDP/TCP 53)
- **Web UI**: http://10.0.0.238:5380
- **Admin Credentials**: Stored in Bitwarden (`technitium-admin` secret)
- **Documentation**: [docs/technitium-dns-deployment-plan.md](../../../docs/technitium-dns-deployment-plan.md)

## Features

- Ad-blocking with customizable blocklists (replaces Pi-hole)
- Split-horizon DNS for `*.torquasmvo.internal`
- Web UI for management
- High availability ready (clustering support in v14+)
- Cross-VLAN accessible (192.168.1.x ↔ 10.0.0.x via UDM Pro)

## Prerequisites

**BEFORE DEPLOYING**: Create Bitwarden secrets and update [bitwarden-secrets.yaml](bitwarden-secrets.yaml):

1. Create in Bitwarden vault:
   - `technitium-admin-username` → `admin`
   - `technitium-admin-password` → (generate strong password)

2. Replace placeholders in `bitwarden-secrets.yaml`:
   - `<BITWARDEN_USERNAME_SECRET_ID>` → actual secret ID
   - `<BITWARDEN_PASSWORD_SECRET_ID>` → actual secret ID

## Deployment

Argo CD auto-discovers and deploys this application via GitOps:

```bash
# Monitor deployment
kubectl get pods -n dns-system -w

# Check services
kubectl get svc -n dns-system

# Expected output:
# technitium-dns-lb       LoadBalancer   10.0.0.53    10.0.0.53     53:xxxxx/UDP,53:xxxxx/TCP
# technitium-dns-ui-lb    LoadBalancer   10.0.0.238   10.0.0.238    5380:xxxxx/TCP

# Check pod logs
kubectl logs -n dns-system deployment/technitium-dns
```

## Initial Configuration

After deployment, access Web UI at http://10.0.0.238:5380 and configure:

### 1. Upstream DNS (Settings → General)
- Forwarders: `1.1.1.1`, `8.8.8.8`
- Enable QNAME Minimization
- Enable DNSSEC

### 2. Ad-Blocking (Zones → Block Lists)
```
https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts
https://big.oisd.nl/
https://adaway.org/hosts.txt
https://v.firebog.net/hosts/AdguardDNS.txt
```

### 3. Local Zone (Zones → Add Zone)
- Zone: `torquasmvo.internal`
- Type: Primary Zone
- Add A records for cluster services:
  ```
  truenas1-nfs.torquasmvo.internal → <NFS_IP>
  plex.torquasmvo.internal → 10.0.0.217
  argocd.torquasmvo.internal → 10.0.0.209
  grafana.torquasmvo.internal → 10.0.0.232
  technitium-dns.torquasmvo.internal → 10.0.0.53
  ```

### 4. Logging (Settings → Logs)
- Query Logging: Enabled
- Max Log Days: 7
- Error Logging: Enabled

## Testing

```bash
# From cluster (test pod)
kubectl run -it --rm test --image=nicolaka/netshoot -- dig @10.0.0.53 google.com

# From local machine (if routable to 10.0.0.x)
dig @10.0.0.53 github.com
dig @10.0.0.53 plex.torquasmvo.internal

# Test ad-blocking
dig @10.0.0.53 doubleclick.net  # Should return 0.0.0.0
```

## UniFi DHCP Configuration

**After testing**, update UniFi Dream Machine Pro:

1. Navigate to: **Settings → Networks**
2. For each VLAN (Main LAN, Homelab, IoT):
   - Edit network
   - Expand DHCP section
   - Set DNS:
     - Auto: **Disabled**
     - DNS Server 1: `10.0.0.53`
     - DNS Server 2: `1.1.1.1` (fallback)
3. Save changes

## Monitoring

- **Health Check**: Gatus monitors Web UI at http://10.0.0.238:5380
- **Pod Status**: `kubectl get pods -n dns-system`
- **Service Endpoints**: `kubectl get endpoints -n dns-system`
- **Query Logs**: Web UI → Dashboard → Query Logs

## Troubleshooting

### Pod CrashLooping
```bash
kubectl logs -n dns-system deployment/technitium-dns
kubectl describe pod -n dns-system <pod-name>
```

### DNS Not Resolving
```bash
# Test from pod
kubectl run -it --rm test --image=nicolaka/netshoot -- dig @10.0.0.53 google.com

# Check service IP
kubectl get svc -n dns-system technitium-dns-lb

# Check MetalLB
kubectl logs -n metallb-system deployment/controller
```

### Web UI Inaccessible
```bash
# Check service
kubectl get svc -n dns-system technitium-dns-ui-lb

# Test connectivity
curl -v http://10.0.0.238:5380
```

### Bitwarden Secret Not Injected
```bash
kubectl get bitwardensecret -n dns-system
kubectl describe bitwardensecret technitium-admin -n dns-system
kubectl logs -n sm-operator-system deployment/sm-operator-controller-manager
```

## Backup & Recovery

### Manual Backup
- Web UI → Settings → Backup → **Create Backup**
- Download `backup.zip` for safekeeping

### Automatic Backup
- PVC: `technitium-dns-config` (5Gi)
- Backup: Longhorn automatic recurring jobs (longhorn-prod group)

### Recovery
```bash
# If pod fails, Kubernetes auto-restarts
kubectl rollout restart deployment/technitium-dns -n dns-system

# If PVC corrupted, restore from Longhorn backup
# Navigate to Longhorn UI (http://10.0.0.215)
# Volumes → technitium-dns-config → Backup → Restore
```

## Maintenance

**Weekly**:
- Check query logs for anomalies
- Update blocklists (Web UI → Zones → Block Lists → Update Now)

**Monthly**:
- Review performance metrics (Web UI → Dashboard → Statistics)
- Backup configuration (Web UI → Settings → Backup)
- Update DNS records as needed

**Quarterly**:
- Review Renovate PRs for software updates
- Rotate admin password (update Bitwarden)
- Review capacity: `kubectl get pvc -n dns-system`

## Architecture

```
UniFi Dream Machine Pro (Gateway/Router)
├── Routes between VLANs (192.168.1.x ↔ 10.0.0.x)
└── DHCP hands out DNS: 10.0.0.53

Technitium DNS Server (10.0.0.53)
├── Deployment: 1 replica, Recreate strategy
├── Storage: 5Gi Longhorn PVC (longhorn-prod, 3 replicas)
├── DNS Service: LoadBalancer at 10.0.0.53 (UDP/TCP 53)
├── Web UI Service: LoadBalancer at 10.0.0.238 (HTTP 5380)
└── Secrets: Bitwarden Secrets Operator

MetalLB IP Pools:
├── dns-pool: 10.0.0.53-10.0.0.54 (DNS services)
└── default: 10.0.0.200-250 (other services)
```

## Future Enhancements (Phase 2): Proxmox LXC Satellite

### Architecture: K8s Primary + Proxmox LXC Secondary

Deploy Technitium secondary in Proxmox LXC container to create multi-site HA architecture:

```
K8s Cluster (Homelab VLAN - 10.0.0.x)          Proxmox Cluster (Main VLAN - 192.168.1.x)
├── Technitium Primary (10.0.0.53)       ←TLS→  ├── Technitium Secondary (192.168.1.53)
│   - GitOps managed                      Sync  │   - LXC container (helper script)
│   - Master configuration                      │   - Receives config from primary
└── Serves Homelab VLAN locally                 └── Serves Main VLAN locally
```

**Benefits**:
- VLAN-local DNS (lower latency per VLAN)
- Geographic diversity (K8s or Proxmox can fail independently)
- Lightweight LXC satellite (minimal resources)
- Reuse existing Proxmox infrastructure

### Implementation Steps (After K8s Primary Stable + Technitium v14+)

**Prerequisites**:
- K8s primary operational for 1-2 weeks
- Renovate updates Technitium to v14+ (clustering support)
- Pi-hole migration complete

**Step 1: Deploy LXC via Community Script**

SSH into Proxmox host:
```bash
bash -c "$(wget -qLO - https://github.com/community-scripts/ProxmoxVE/raw/main/ct/technitiumdns.sh)"
```

Script prompts:
- Container ID: `200` (or next available)
- Hostname: `technitium-dns-secondary`
- Disk: 2GB (default)
- CPU: 1-2 cores
- RAM: 512MB-1GB
- Bridge: vmbr0 (or Main VLAN bridge)
- IP: `192.168.1.53/24`
- Gateway: `192.168.1.1` (UDM Pro)

**Step 2: Configure Clustering**

LXC Secondary (http://192.168.1.53:5380):
- Settings → Clustering
- Enable Clustering: Yes
- Server Type: **Secondary**
- Primary Server: `10.0.0.53`
- Save and restart

K8s Primary (http://10.0.0.238:5380):
- Settings → Clustering
- Enable Clustering: Yes
- Server Type: **Primary**
- Add Secondary: `192.168.1.53`
- Save and apply

**Step 3: Update UniFi DHCP (VLAN-Local DNS)**

Main VLAN (192.168.1.0/24):
- Primary DNS: `192.168.1.53` (LXC - local, fast)
- Secondary DNS: `10.0.0.53` (K8s - backup)

Homelab VLAN (10.0.0.0/24):
- Primary DNS: `10.0.0.53` (K8s - local, fast)
- Secondary DNS: `192.168.1.53` (LXC - backup)

**Step 4: Verify Replication**

```bash
# Make config change on K8s primary
# Add DNS record via Web UI: test.torquasmvo.internal → 10.0.0.1

# Query both instances
dig @10.0.0.53 test.torquasmvo.internal    # K8s primary
dig @192.168.1.53 test.torquasmvo.internal # LXC secondary

# Both should return same result
```

### Additional Enhancements

#### HTTPS for Web UI
- Add Traefik IngressRoute for `dns.torquasmvo.com`
- Use cert-manager wildcard certificate

#### Prometheus Metrics
- Enable metrics in Technitium v14+
- Create ServiceMonitor for Prometheus
- Import Grafana dashboard

## References

- [Technitium DNS Server Documentation](https://technitium.com/dns/)
- [Deployment Plan](../../../docs/technitium-dns-deployment-plan.md)
- [Docker Hub: technitium/dns-server](https://hub.docker.com/r/technitium/dns-server)
- [Clustering Guide](https://blog.technitium.com/2025/11/understanding-clustering-and-how-to.html)

---

**Last Updated**: 2026-01-13
**Cluster**: talos-rao (Talos v1.11.5, Kubernetes v1.34.1)
**Namespace**: dns-system
