# Technitium DNS Server Deployment Plan

**Status**: Planning Complete - Ready for Implementation
**Created**: 2026-01-13
**Author**: Claude Sonnet 4.5
**Purpose**: Replace two Pi-hole instances (192.168.1.x) with centralized Kubernetes-native DNS server

---

## Executive Summary

Deploy Technitium DNS Server in the BrainiacOps Kubernetes cluster to provide centralized DNS services accessible across VLANs (192.168.1.0/24 Main LAN and 10.0.0.0/24 Homelab) via UniFi Dream Machine Pro routing and MetalLB LoadBalancer.

**Key Features**:
- Ad-blocking with customizable blocklists (replaces Pi-hole)
- Split-horizon DNS for `*.torquasmvo.internal` local domain resolution
- Web UI for management
- High availability ready (clustering support in Phase 2)
- Cross-VLAN accessibility via UDM Pro routing

---

## Network Architecture

### Current Environment
- **Gateway**: UniFi Dream Machine Professional (UDM Pro) - firmware 4.4.6
- **Main VLAN**: 192.168.1.0/24 (existing Pi-hole instances at 192.168.1.x)
- **Homelab VLAN**: 10.0.0.0/24 (Kubernetes cluster - Talos v1.11.5, K8s v1.34.1)
- **IoT VLAN**: 10.10.10.0/24 (smart devices)
- **MetalLB**: L2Advertisement on 10.0.0.200-10.0.0.250 (existing)

### Target Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│ UniFi Dream Machine Pro (Gateway/Router)                            │
│ - Routes between VLANs (192.168.1.x ↔ 10.0.0.x)                    │
│ - DHCP hands out DNS: 10.0.0.53 (primary), 1.1.1.1 (fallback)     │
└─────────────────────────────────────────────────────────────────────┘
                              │
        ┌─────────────────────┼─────────────────────┐
        │                     │                     │
   Main VLAN           Homelab VLAN            IoT VLAN
  192.168.1.0/24       10.0.0.0/24          10.10.10.0/24
  (Pi-hole → DNS)   (Kubernetes Cluster)   (Smart Devices)
        │                     │                     │
        └─────────────────────┼─────────────────────┘
                              │
                ┌─────────────┴─────────────┐
                │ Technitium DNS Server     │
                │ IP: 10.0.0.53 (MetalLB)  │
                │ - Ad-blocking             │
                │ - Local zones             │
                │ - Web UI: 10.0.0.238     │
                └───────────────────────────┘
```

---

## IP Address Allocation

| IP Address | Purpose | MetalLB Pool | Status |
|------------|---------|--------------|--------|
| **10.0.0.53** | Technitium DNS (primary) | `dns-pool` (new) | Will be assigned |
| **10.0.0.54** | Reserved for HA secondary | `dns-pool` (new) | Reserved for Phase 2 |
| **10.0.0.238** | Technitium Web UI | `default` (existing) | Will be assigned |

### MetalLB Configuration Changes

**New IP Pool** (to be created):
```yaml
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: dns-pool
  namespace: metallb-system
spec:
  addresses:
    - 10.0.0.53-10.0.0.54
```

**Rationale**:
- Current MetalLB pool only covers 10.0.0.200-250
- IP 10.0.0.53 is outside this range (memorable DNS IP)
- Separate pool keeps existing infrastructure unchanged
- Reserves 10.0.0.54 for future HA clustering

---

## Technology Stack

| Component | Version/Details |
|-----------|-----------------|
| **DNS Server** | Technitium DNS Server 13.2.1+ (Renovate managed) |
| **Container Runtime** | Kubernetes v1.34.1 on Talos Linux v1.11.5 |
| **Storage** | Longhorn distributed storage (5Gi PVC, 3 replicas) |
| **Load Balancer** | MetalLB v0.15.3 (L2 Advertisement) |
| **Secrets** | Bitwarden Secrets Operator |
| **GitOps** | Argo CD (app-of-apps pattern) |
| **Namespace** | `dns-system` |

### Technitium Capabilities
- **Clustering**: v14+ supports primary/secondary replication with TLS
- **Protocols**: DNS (UDP/TCP 53), HTTP (5380), HTTPS (53443), DoT (853), DoH (443)
- **Storage**: `/etc/dns` directory (config, zones, blocklists, logs)
- **Features**: Ad-blocking, split-horizon DNS, DNSSEC, DNS-over-HTTPS/TLS

---

## Implementation Steps

### Phase 1: Prerequisites

#### 1.1 Bitwarden Secrets Setup
Create secrets in Bitwarden vault:
- `technitium-admin-username` → `admin`
- `technitium-admin-password` → (generate strong password)
- Document secret IDs for `bitwarden-secrets.yaml`

#### 1.2 Pre-Deployment Network Testing

**CRITICAL**: Test inter-VLAN routing BEFORE deployment.

```bash
# From any 192.168.1.x device
ping 10.0.0.200  # Traefik ingress (should already work)
ping 10.0.0.217  # Plex (should already work)
curl http://10.0.0.200  # Should get Traefik 404

# If these work, DNS at 10.0.0.53 will work too
```

**If pings fail**: Check UDM Pro firewall rules (see Section 5.2 below).

#### 1.3 IP Address Verification
```bash
kubectl get svc -A | grep "10.0.0.53"   # Must be empty
kubectl get svc -A | grep "10.0.0.238"  # Must be empty
```

---

### Phase 2: Create Kubernetes Manifests

**Directory Structure**:
```
kubernetes/infrastructure/technitium-dns/
├── app.yaml                    # Argo CD Application (sync-wave: 1)
├── kustomization.yaml          # Resource list
├── namespace.yaml              # Namespace: dns-system
├── metallb-ippool.yaml         # NEW: Dedicated IPAddressPool (10.0.0.53-54)
├── bitwarden-secrets.yaml      # BitwardenSecret resource
├── pvc.yaml                    # 5Gi Longhorn PVC
├── deploy.yaml                 # Deployment manifest
├── svc-dns.yaml               # LoadBalancer for DNS (10.0.0.53)
├── svc-ui.yaml                # LoadBalancer for Web UI (10.0.0.238)
└── README.md                  # Documentation
```

#### 2.1 Key Manifest: MetalLB IP Pool

**File**: `kubernetes/infrastructure/technitium-dns/metallb-ippool.yaml`

```yaml
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: dns-pool
  namespace: metallb-system
spec:
  addresses:
    - 10.0.0.53-10.0.0.54  # Primary DNS (53) + future HA secondary (54)
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: dns-pool
  namespace: metallb-system
spec:
  ipAddressPools:
    - dns-pool
```

**Why this is needed**:
- Current MetalLB pool only covers 10.0.0.200-250
- The IP 10.0.0.53 is outside this range
- Without this pool, LoadBalancer service will fail to assign IP
- Creates separate pool without modifying existing infrastructure

#### 2.2 Key Manifest: Deployment

**File**: `kubernetes/infrastructure/technitium-dns/deploy.yaml`

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: technitium-dns
  namespace: dns-system
  labels:
    app: technitium-dns
spec:
  replicas: 1
  strategy:
    type: Recreate  # Required for ReadWriteOnce volumes
  selector:
    matchLabels:
      app: technitium-dns
  template:
    metadata:
      labels:
        app: technitium-dns
    spec:
      containers:
        - name: technitium-dns
          image: technitium/dns-server:13.2.1  # Renovate will update
          imagePullPolicy: IfNotPresent
          ports:
            - name: dns-tcp
              containerPort: 53
              protocol: TCP
            - name: dns-udp
              containerPort: 53
              protocol: UDP
            - name: http
              containerPort: 5380
              protocol: TCP
            - name: https
              containerPort: 53443
              protocol: TCP
          env:
            - name: DNS_SERVER_DOMAIN
              value: "technitium-dns.torquasmvo.internal"
            - name: DNS_SERVER_ADMIN_USER
              valueFrom:
                secretKeyRef:
                  name: technitium-admin
                  key: admin-username
            - name: DNS_SERVER_ADMIN_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: technitium-admin
                  key: admin-password
          volumeMounts:
            - name: config
              mountPath: /etc/dns
          resources:
            requests:
              cpu: 500m
              memory: 512Mi
            limits:
              cpu: 2000m
              memory: 2Gi
          livenessProbe:
            httpGet:
              path: /
              port: 5380
            initialDelaySeconds: 30
            periodSeconds: 10
            timeoutSeconds: 5
            failureThreshold: 3
          readinessProbe:
            httpGet:
              path: /
              port: 5380
            initialDelaySeconds: 15
            periodSeconds: 5
            timeoutSeconds: 3
            failureThreshold: 3
      volumes:
        - name: config
          persistentVolumeClaim:
            claimName: technitium-dns-config
```

#### 2.3 Key Manifest: DNS LoadBalancer Service

**File**: `kubernetes/infrastructure/technitium-dns/svc-dns.yaml`

```yaml
apiVersion: v1
kind: Service
metadata:
  name: technitium-dns-lb
  namespace: dns-system
  annotations:
    metallb.universe.tf/allow-shared-ip: "technitium-dns"
spec:
  type: LoadBalancer
  loadBalancerIP: 10.0.0.53  # From dns-pool
  externalTrafficPolicy: Local  # Preserve source IP, reduce latency
  selector:
    app: technitium-dns
  ports:
    - name: dns-tcp
      port: 53
      targetPort: 53
      protocol: TCP
    - name: dns-udp
      port: 53
      targetPort: 53
      protocol: UDP
```

#### 2.4 Other Required Manifests

See full plan file for complete manifests:
- `namespace.yaml` - Creates `dns-system` namespace
- `bitwarden-secrets.yaml` - BitwardenSecret resource (requires secret IDs from Bitwarden)
- `pvc.yaml` - 5Gi Longhorn PVC with `longhorn-prod` StorageClass
- `svc-ui.yaml` - Web UI LoadBalancer (10.0.0.238:5380)
- `app.yaml` - Argo CD Application (sync-wave: 1)
- `kustomization.yaml` - Lists all resources
- `README.md` - Operational documentation

---

### Phase 3: Deployment

#### 3.1 Validation
```bash
cd /home/michael/gitstuff/BrainiacOps/kubernetes/infrastructure/technitium-dns

# Validate manifests
kustomize build . | kubeconform -strict -
yamllint .

# Verify no secrets in manifests
grep -r "password" . | grep -v "passwordKey"  # Only Bitwarden refs
```

#### 3.2 Git Commit
```bash
git add kubernetes/infrastructure/technitium-dns/
git commit -m "feat(dns): add Technitium DNS Server infrastructure

- Add Technitium DNS Server deployment to replace Pi-hole
- Configure MetalLB LoadBalancer for DNS (10.0.0.53) and Web UI (10.0.0.238)
- Use Longhorn for persistent storage (5Gi, longhorn-prod)
- Integrate Bitwarden Secrets Operator for admin credentials
- Document migration from Pi-hole and UniFi configuration

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

#### 3.3 Argo CD Auto-Discovery
```bash
# Argo CD will auto-discover the application
argocd app get technitium-dns

# Monitor deployment
kubectl get pods -n dns-system -w
kubectl get svc -n dns-system
```

#### 3.4 Verify Deployment
```bash
# Check pod status
kubectl get pods -n dns-system
kubectl describe pod -n dns-system <pod-name>

# Check services (verify IPs assigned)
kubectl get svc -n dns-system
# Expected:
# technitium-dns-lb      LoadBalancer   10.0.0.53   10.0.0.53     53:xxxxx/UDP,53:xxxxx/TCP
# technitium-dns-ui-lb   LoadBalancer   10.0.0.238  10.0.0.238    5380:xxxxx/TCP

# Check PVC
kubectl get pvc -n dns-system
# Expected: technitium-dns-config  Bound  5Gi  longhorn-prod

# Check Bitwarden secret
kubectl get secret -n dns-system technitium-admin
kubectl describe bitwardensecret -n dns-system technitium-admin
```

---

### Phase 4: Initial Configuration (Web UI)

#### 4.1 Access Web UI
- URL: `http://10.0.0.238:5380`
- Login: Username and password from Bitwarden
- Complete setup wizard if prompted

#### 4.2 Configure Upstream DNS
**Web UI → Settings → General**
- **Forwarders**:
  - `1.1.1.1` (Cloudflare)
  - `8.8.8.8` (Google)
- **Prefer IPv6**: Disabled (unless needed)
- **Enable QNAME Minimization**: Enabled
- **Enable DNSSEC**: Enabled

#### 4.3 Configure Ad-Blocking
**Web UI → Zones → Block Lists**

Add blocklists (import from Pi-hole or use these):
```
https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts
https://big.oisd.nl/
https://adaway.org/hosts.txt
https://v.firebog.net/hosts/AdguardDNS.txt
```

Options:
- **Advanced Blocking**: Enabled
- **Block private IP addresses**: Optional (enable if desired)

#### 4.4 Create Local Zone for Internal Services
**Web UI → Zones → Add Zone**
- **Zone**: `torquasmvo.internal`
- **Type**: Primary Zone
- **DNSSEC**: Disabled (internal zone)

Add A records:
```
truenas1-nfs.torquasmvo.internal → <NFS_SERVER_IP>
plex.torquasmvo.internal → 10.0.0.217
argocd.torquasmvo.internal → 10.0.0.209
grafana.torquasmvo.internal → 10.0.0.232
technitium-dns.torquasmvo.internal → 10.0.0.53
portainer.torquasmvo.internal → 10.0.0.204
longhorn.torquasmvo.internal → 10.0.0.215
```

Optional wildcard (for Traefik ingress):
```
*.torquasmvo.internal → 10.0.0.200
```

#### 4.5 Configure Logging
**Web UI → Settings → Logs**
- **Enable Query Logging**: Yes
- **Max Log Days**: 7
- **Enable Error Logging**: Yes

---

### Phase 5: Testing

#### 5.1 DNS Resolution Tests
```bash
# From cluster (using test pod)
kubectl run -it --rm test --image=nicolaka/netshoot --restart=Never -- /bin/bash
# Inside pod:
dig @10.0.0.53 google.com
dig @10.0.0.53 plex.torquasmvo.internal
nslookup example.com 10.0.0.53

# From local machine (if routable to 10.0.0.x)
dig @10.0.0.53 github.com
nslookup plex.torquasmvo.internal 10.0.0.53
```

#### 5.2 Ad-Blocking Tests
```bash
# Test blocked domain
dig @10.0.0.53 doubleclick.net
# Expected: 0.0.0.0 or NX response

# Test allowed domain
dig @10.0.0.53 github.com
# Expected: valid IP address
```

#### 5.3 Performance Tests
```bash
# Test query latency (should be <50ms)
time dig @10.0.0.53 google.com

# Test concurrent queries
for i in {1..100}; do dig @10.0.0.53 test$i.com &; done
```

#### 5.4 Cross-VLAN Tests (from 192.168.1.x device)
```bash
# Test connectivity
ping 10.0.0.53

# Test DNS resolution
nslookup google.com 10.0.0.53
dig @10.0.0.53 github.com

# Test local zone
nslookup plex.torquasmvo.internal 10.0.0.53

# Test Web UI accessibility
curl http://10.0.0.238:5380
# Or open in browser: http://10.0.0.238:5380
```

---

### Phase 6: UniFi Network Configuration (UDM Pro)

#### 6.1 Verify Inter-VLAN Routing

The UDM Pro should route between VLANs by default. Test connectivity BEFORE changing DHCP:

```bash
# From a 192.168.1.x device
ping 10.0.0.53

# If ping fails, proceed to create firewall rule
```

#### 6.2 Create Firewall Rule (if needed)

If ping fails, create firewall rule to allow DNS traffic:

1. Navigate to: **Settings → Security → Firewall → Rules**
2. Create new rule: **LAN In** (192.168.1.x → 10.0.0.x)
3. Configure:
   - **Name**: Allow DNS to Technitium
   - **Type**: Internet In → LAN
   - **Action**: Accept
   - **Protocol**: TCP and UDP
   - **Source**: Network `Main LAN` (192.168.1.0/24) or `Any`
   - **Destination**: Single IP `10.0.0.53`
   - **Port**: 53
   - **Logging**: Enable (for debugging)
4. Save and apply

**Note**: UDM Pro typically allows inter-VLAN traffic by default unless you have explicit deny rules.

#### 6.3 UDM Pro DNS Forwarding Options

The UDM Pro has a built-in DNS forwarder (dnsmasq). Choose one approach:

**Option A: Direct to Technitium** (Recommended)
- Clients point directly to Technitium (10.0.0.53)
- Simpler architecture, fewer hops, better performance
- DHCP hands out 10.0.0.53 directly

**Option B: UDM Pro as DNS Proxy**
- UDM Pro forwards to Technitium (10.0.0.53)
- Clients point to UDM Pro (192.168.1.1)
- Adds extra hop, but provides UDM Pro as failover
- Requires configuring UDM Pro to forward to 10.0.0.53

**Recommendation**: Use Option A (direct to Technitium) for best performance.

#### 6.4 DHCP Configuration

Update DNS servers for each VLAN:

1. Navigate to: **Settings → Networks**
2. For **Main LAN** (192.168.1.0/24):
   - Click Edit
   - Expand **DHCP** section
   - Set **DHCP Name Server**:
     - Auto: **Disabled**
     - DNS Server 1: `10.0.0.53` (Technitium)
     - DNS Server 2: `1.1.1.1` (fallback during testing)
   - Save
3. Repeat for **Homelab VLAN** (10.0.0.0/24):
   - DNS Server 1: `10.0.0.53`
   - DNS Server 2: `1.1.1.1`
4. Repeat for **IoT VLAN** (10.10.10.0/24) and any other VLANs

**Note**: After migration stability (1-2 weeks), change Secondary DNS from `1.1.1.1` to `10.0.0.54` (when HA clustering is implemented in Phase 2).

#### 6.5 Force DHCP Renewal (Critical Clients)

DHCP changes take effect on lease renewal. For immediate testing:

**Windows**:
```powershell
ipconfig /release
ipconfig /renew
ipconfig /all  # Verify DNS servers changed to 10.0.0.53
```

**Linux/Mac**:
```bash
sudo dhclient -r && sudo dhclient
# Or
sudo systemctl restart NetworkManager
```

**Verify**:
```bash
# Check DNS server in use
cat /etc/resolv.conf  # Linux/Mac (should show nameserver 10.0.0.53)
ipconfig /all         # Windows (should show DNS Servers: 10.0.0.53, 1.1.1.1)

# Test DNS resolution
nslookup google.com  # Should use 10.0.0.53
nslookup plex.torquasmvo.internal  # Should resolve to 10.0.0.217
```

---

### Phase 7: Migration from Pi-hole

#### 7.1 Export Pi-hole Configuration

**Blocklists**:
1. Access Pi-hole admin UI (192.168.1.x)
2. Navigate to: **Group Management → Adlists**
3. Copy all blocklist URLs

**Custom DNS Records**:
1. Navigate to: **Local DNS → DNS Records**
2. Export all custom A/CNAME records
3. Document for import to Technitium

**Whitelist/Blacklist**:
1. Navigate to: **Settings → Teleporter**
2. Create backup (download backup file)
3. Extract whitelist/blacklist entries if needed

#### 7.2 Import to Technitium

**Blocklists**:
1. Web UI → Zones → Block Lists
2. Add each blocklist URL from Pi-hole
3. Click "Update Now" to download lists

**Custom DNS Records**:
1. Web UI → Zones → Select `torquasmvo.internal`
2. Add A records for each custom Pi-hole entry
3. Test resolution: `dig @10.0.0.53 <custom-record>`

**Whitelist/Blacklist**:
1. Web UI → Zones → Allowed/Blocked Zones
2. Manually add entries as needed

#### 7.3 Parallel Testing (1-2 weeks recommended)

**Strategy**: Run Technitium and Pi-hole in parallel before full cutover.

1. **Keep Pi-hole operational** (do not power off yet)
2. **Update UniFi DHCP** (test VLAN only, or all VLANs if confident):
   - Primary DNS: `10.0.0.53` (Technitium)
   - Secondary DNS: `192.168.1.x` (Pi-hole) - fallback during testing
3. **Monitor both systems**:
   - Check Technitium query logs (Web UI → Dashboard)
   - Check Pi-hole query logs (should see reduced traffic)
   - Verify no DNS resolution errors reported by users
4. **Test all critical services**:
   - Internal services (Plex, Nextcloud, etc.)
   - External sites (Google, GitHub, etc.)
   - Ad-blocking effectiveness
5. **Collect feedback** from users (family, team)
6. **After 1-2 weeks of stable operation**, proceed to full cutover

#### 7.4 Full Cutover

**Prerequisites**:
- Technitium stable for 1+ week
- No DNS resolution errors
- Ad-blocking working correctly
- All local zones resolving
- User feedback positive

**Steps**:
1. **Update UniFi DHCP** for all VLANs:
   - Navigate to Settings → Networks → [Each Network]
   - Primary DNS: `10.0.0.53`
   - Secondary DNS: `1.1.1.1` (external fallback, not Pi-hole)
   - Save changes
2. **Force DHCP renewal** on critical clients (see Phase 6.5)
3. **Monitor for issues** (24-48 hours)
4. **If stable, decommission Pi-hole**:
   - Power off Pi-hole instances (do not delete yet)
   - Wait 1 week with no issues
   - Remove from network permanently
   - Update documentation (no longer Pi-hole at 192.168.1.x)

---

### Phase 8: Monitoring

#### 8.1 Add Gatus Health Check

**File**: `kubernetes/infrastructure/monitoring/gatus/config/config.yaml`

Add endpoint:
```yaml
- name: Technitium DNS
  group: Infrastructure
  url: "http://10.0.0.238:5380"
  interval: 60s
  conditions:
    - "[STATUS] == 200"
  alerts:
    - type: discord  # Or your configured alert type
      description: "Technitium DNS web UI is down"
```

#### 8.2 DNS Query Test (Optional CronJob)

Create CronJob to test DNS resolution periodically:

**File**: `kubernetes/infrastructure/technitium-dns/monitoring/dns-test-cronjob.yaml`
```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: technitium-dns-test
  namespace: dns-system
spec:
  schedule: "*/5 * * * *"  # Every 5 minutes
  jobTemplate:
    spec:
      template:
        spec:
          containers:
            - name: dns-test
              image: nicolaka/netshoot:latest
              command:
                - /bin/sh
                - -c
                - |
                  dig @10.0.0.53 google.com +short || exit 1
                  dig @10.0.0.53 plex.torquasmvo.internal +short || exit 1
          restartPolicy: OnFailure
```

#### 8.3 Prometheus Metrics (Future - Phase 2)

Technitium v14+ supports metrics export:
- Add ServiceMonitor for Prometheus scraping
- Create Grafana dashboard for DNS statistics
- Monitor query rate, cache hit ratio, latency

---

### Phase 9: Documentation Updates

#### 9.1 Update IP Address Registry

**File**: `docs/ip_addresses.md`

Add entries:
```markdown
| technitium-dns-lb | dns-system | 10.0.0.53 |
| technitium-dns-secondary-lb (Phase 2) | dns-system | 10.0.0.54 |
| technitium-dns-ui-lb | dns-system | 10.0.0.238 |
```

Update totals:
```
MetalLB IPs:
- dns-pool: total=2 used=1 free=1 (10.0.0.53-54)
- default: total=51 used=37 free=14 (10.0.0.200-250)
```

**Note**:
- 10.0.0.53 is from new `dns-pool` (not default MetalLB pool)
- 10.0.0.54 is reserved for future HA secondary
- 10.0.0.238 is from existing `default` pool

#### 9.2 Update CLAUDE.md

**File**: `CLAUDE.md`

Add to "Current Cluster Details" section:
```markdown
**DNS Services**:
- Technitium DNS: 10.0.0.53 (replaces Pi-hole)
- Web UI: 10.0.0.238:5380
- Features: Ad-blocking, split-horizon DNS for *.torquasmvo.internal, HA-ready
```

#### 9.3 Create Migration Notes

**File**: `docs/technitium-dns-migration.md`

Document:
- Migration date
- Pi-hole instances decommissioned (192.168.1.x IPs freed)
- Blocklists migrated (list URLs)
- Custom DNS records migrated (list records)
- UniFi configuration changes (DHCP DNS settings)
- Rollback procedure (see Section 10 below)
- Lessons learned / issues encountered

---

## Rollback Plan

### Scenario 1: Deployment Fails

**Symptoms**: Pod CrashLooping, PVC not binding, Service no external IP

**Actions**:
```bash
# Check pod logs
kubectl logs -n dns-system deployment/technitium-dns

# Check Argo CD status
argocd app get technitium-dns

# Delete and retry
kubectl delete -n dns-system deployment technitium-dns
argocd app sync technitium-dns

# If persistent issues, remove application
kubectl delete application technitium-dns -n argocd
```

### Scenario 2: DNS Not Resolving After Migration

**Symptoms**: Clients cannot resolve DNS, websites not loading

**Actions**:
1. **Revert UniFi DHCP immediately**:
   - Navigate to Settings → Networks → [Each Network]
   - Primary DNS: `<Pi-hole IP>` (192.168.1.x)
   - Secondary DNS: `1.1.1.1`
   - Save changes
2. **Force DHCP renewal** on affected clients (see Phase 6.5)
3. **Debug Technitium**:
   ```bash
   kubectl logs -n dns-system deployment/technitium-dns
   dig @10.0.0.53 google.com  # Test directly
   kubectl get endpoints -n dns-system  # Verify service endpoints
   ```
4. **Check service endpoints**:
   ```bash
   kubectl describe svc -n dns-system technitium-dns-lb
   ```
5. **Verify MetalLB** assigned IP:
   ```bash
   kubectl get svc -n dns-system
   # Should show EXTERNAL-IP: 10.0.0.53
   ```

### Scenario 3: Ad-Blocking Not Working

**Symptoms**: Ads showing, blocked domains resolving

**Actions**:
1. Verify blocklists loaded: Web UI → Zones → Block Lists
2. Check blocklist URLs are accessible (test in browser)
3. Force blocklist update: Web UI → Zones → Block Lists → **Update Now**
4. Test specific blocked domain: `dig @10.0.0.53 doubleclick.net`
5. Check logs for errors: `kubectl logs -n dns-system deployment/technitium-dns`
6. If still failing, temporarily revert to Pi-hole (see Scenario 2)

### Scenario 4: Local Zones Not Resolving

**Symptoms**: `*.torquasmvo.internal` domains not resolving

**Actions**:
1. Verify zone exists: Web UI → Zones → Primary Zones
2. Check A records in `torquasmvo.internal` zone
3. Test directly: `dig @10.0.0.53 plex.torquasmvo.internal`
4. Check zone file: Web UI → Zones → Select zone → View Records
5. Re-create zone if corrupted (delete and recreate with records)

### Complete Rollback Procedure

If Technitium must be completely removed:

```bash
# 1. Revert UniFi DHCP to Pi-hole or public DNS
# (via UniFi UI - see Phase 6.4)

# 2. Delete Argo CD application
kubectl delete application technitium-dns -n argocd

# 3. Delete namespace (removes all resources)
kubectl delete namespace dns-system

# 4. Delete MetalLB IP pool (if desired)
kubectl delete ipaddresspool dns-pool -n metallb-system
kubectl delete l2advertisement dns-pool -n metallb-system

# 5. Verify cleanup
kubectl get ns dns-system  # Should not exist
kubectl get svc -A | grep "10.0.0.53"  # Should be empty
kubectl get svc -A | grep "10.0.0.238"  # Should be empty

# 6. Clean up Git repository
git rm -r kubernetes/infrastructure/technitium-dns/
git commit -m "revert: remove Technitium DNS deployment"
git push
```

---

## Future Enhancements (Phase 2+)

### 1. High Availability Clustering

**Implementation**:
1. Create `kubernetes/infrastructure/technitium-dns-secondary/`
2. Deploy second instance with:
   - LoadBalancer IP: `10.0.0.54` (already in `dns-pool`)
   - Separate PVC: `technitium-dns-config-secondary`
   - Same Bitwarden credentials
3. Configure clustering via Web UI:
   - Primary: `10.0.0.53`
   - Secondary: `10.0.0.54`
   - Enable auto-sync (Technitium v14+ clustering feature)
4. Update UniFi DHCP:
   - Primary DNS: `10.0.0.53`
   - Secondary DNS: `10.0.0.54` (instead of 1.1.1.1)

**Benefits**:
- Automatic failover if primary fails
- Zero-downtime updates (rolling restart)
- Load distribution (clients round-robin between IPs)
- Config sync across instances (blocklists, zones, settings)

### 2. HTTPS for Web UI (Traefik + cert-manager)

**Implementation**:
```yaml
# File: kubernetes/infrastructure/technitium-dns/ingressroute.yaml
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: technitium-dns-ui
  namespace: dns-system
spec:
  entryPoints:
    - websecure
  routes:
    - match: Host(`dns.torquasmvo.com`)
      kind: Rule
      services:
        - name: technitium-dns-ui-lb
          port: 5380
  tls:
    certResolver: cloudflare  # Use existing wildcard cert
```

**Benefits**:
- Secure access over HTTPS
- Access via friendly domain name (`dns.torquasmvo.com`)
- Leverages existing cert-manager infrastructure

### 3. Prometheus Metrics & Grafana Dashboard

**Implementation**:
1. Enable metrics in Technitium (when available in v14+)
2. Create ServiceMonitor:
   ```yaml
   apiVersion: monitoring.coreos.com/v1
   kind: ServiceMonitor
   metadata:
     name: technitium-dns
     namespace: dns-system
   spec:
     selector:
       matchLabels:
         app: technitium-dns
     endpoints:
       - port: metrics
         interval: 30s
   ```
3. Import/create Grafana dashboard for DNS statistics

**Metrics to Track**:
- Query rate (queries/sec)
- Cache hit ratio (%)
- Query latency (ms)
- Top queried domains
- Blocked query count
- Error rate

### 4. External-DNS Integration

**Use Case**: Automatically sync Kubernetes Ingress/Service records to Technitium

**Implementation**:
- Deploy external-dns with RFC2136 provider
- Configure Technitium to accept dynamic updates
- Auto-create DNS records for new services (e.g., `plex.torquasmvo.internal` automatically created when Plex service is deployed)

### 5. DNS-over-HTTPS/TLS (DoH/DoT)

**Implementation**:
1. Enable DoH in Technitium: Settings → General → Enable HTTPS
2. Configure cert-manager certificate for DNS service
3. Expose ports via LoadBalancer:
   - 443 (DoH): `https://10.0.0.53/dns-query`
   - 853 (DoT): `tls://10.0.0.53`
4. Configure clients to use DoH/DoT (browsers, OS settings)

**Benefits**:
- Encrypted DNS queries (privacy)
- Prevents DNS snooping/tampering
- Bypasses ISP DNS blocking

### 6. Geographic DNS (Split-Brain)

**Use Case**: Different responses based on client location/network

**Implementation**:
- Configure Allow/Deny lists based on IP ranges
- Create separate zones for internal vs external clients
- Useful for public-facing services (respond with public IP externally, private IP internally)

---

## Maintenance Procedures

### Regular Maintenance (Weekly)

1. **Check DNS Query Logs**:
   - Web UI → Dashboard → Query Logs
   - Look for anomalies, high error rates, unusual query patterns

2. **Update Blocklists**:
   - Web UI → Zones → Block Lists → **Update Now**
   - Verify update success (check last updated timestamp)

3. **Review Performance Metrics**:
   - Web UI → Dashboard → Statistics
   - Query rate, cache hit ratio, response time
   - Compare week-over-week trends

### Monthly Maintenance

1. **Review and Prune Logs**:
   - Web UI → Settings → Logs
   - Adjust retention if needed (default: 7 days)
   - Download logs for archival if required

2. **Update DNS Records**:
   - Add/remove services in `torquasmvo.internal` zone
   - Verify all cluster services have DNS entries
   - Remove decommissioned services

3. **Backup Configuration**:
   - Web UI → Settings → Backup → **Create Backup**
   - Download `backup.zip` and store securely (off-cluster)
   - Test restore procedure (optional, in dev environment)

### Quarterly Maintenance

1. **Software Updates**:
   - Renovate will create PRs for Technitium image updates
   - Review changelog before merging (check breaking changes)
   - Test in staging or during low-traffic period
   - Monitor for issues after update

2. **Security Audit**:
   - Review access logs for unauthorized attempts
   - Rotate admin password (update Bitwarden secret)
   - Check for CVEs in Technitium version (subscribe to security mailing list)
   - Update firewall rules if needed

3. **Capacity Planning**:
   - Review PVC usage: `kubectl get pvc -n dns-system`
   - Expand PVC if >70% full (resize Longhorn volume)
   - Review query volume trends (plan for HA if needed)
   - Check resource usage: `kubectl top pod -n dns-system`

### Emergency Procedures

**DNS Service Down**:
```bash
# 1. Check pod status
kubectl get pods -n dns-system
kubectl describe pod -n dns-system <pod-name>

# 2. Check logs
kubectl logs -n dns-system deployment/technitium-dns --tail=100

# 3. Restart deployment
kubectl rollout restart deployment/technitium-dns -n dns-system

# 4. If persistent, revert UniFi DHCP to 1.1.1.1 or Pi-hole
```

**High Query Latency**:
```bash
# 1. Check resource usage
kubectl top pod -n dns-system

# 2. Increase resources if needed (edit deploy.yaml)
kubectl edit deployment technitium-dns -n dns-system

# 3. Check upstream DNS performance
# Web UI → Dashboard → Forwarders (check response times)

# 4. Clear cache if stale
# Web UI → Dashboard → Clear Cache
```

**PVC Corruption**:
```bash
# 1. Restore from Longhorn backup
# Navigate to Longhorn UI (http://10.0.0.215)
# Volumes → technitium-dns-config → Backup → Restore

# 2. Restart pod
kubectl delete pod -n dns-system -l app=technitium-dns
```

---

## Performance Tuning

### Resource Adjustments

Based on query volume, adjust in `deploy.yaml`:

**Low traffic (<1000 queries/hour)**:
```yaml
resources:
  requests:
    cpu: 250m
    memory: 256Mi
  limits:
    cpu: 1000m
    memory: 1Gi
```

**Medium traffic (1000-10000 queries/hour)** - **Current Configuration**:
```yaml
resources:
  requests:
    cpu: 500m
    memory: 512Mi
  limits:
    cpu: 2000m
    memory: 2Gi
```

**High traffic (>10000 queries/hour)**:
```yaml
resources:
  requests:
    cpu: 1000m
    memory: 1Gi
  limits:
    cpu: 4000m
    memory: 4Gi
```

### Cache Tuning

**Web UI → Settings → General**:
- **Cache Maximum Entries**: Increase for high traffic (default: 10000)
- **Cache Minimum TTL**: Set to 60s for faster responses
- **Cache Maximum TTL**: Set to 86400s (1 day) for stability
- **Cache Negative TTL**: Set to 300s to avoid repeated failures

### Upstream DNS Optimization

**Web UI → Settings → General → Forwarders**:

Use multiple upstream providers for redundancy:
```
1.1.1.1 (Cloudflare - fast, privacy-focused)
1.0.0.1 (Cloudflare backup)
8.8.8.8 (Google - reliable)
8.8.4.4 (Google backup)
```

Or use DNS-over-HTTPS for privacy:
```
https://cloudflare-dns.com/dns-query
https://dns.google/dns-query
```

---

## Security Considerations

### Access Control

1. **Web UI Authentication**:
   - Strong password stored in Bitwarden (rotate quarterly)
   - Enable 2FA when available (Technitium v14+)
   - Restrict Web UI access via firewall (UniFi rules)

2. **Network Segmentation**:
   - DNS service (10.0.0.53) accessible from all VLANs
   - Web UI (10.0.0.238) restricted to admin VLAN only (optional)
   - Use UDM Pro firewall rules to enforce

3. **Kubernetes RBAC**:
   - `dns-system` namespace isolated
   - Only Argo CD can modify resources
   - No direct kubectl access needed in production

### Threat Mitigation

**DNS Amplification Attacks**:
- Configure rate limiting: Web UI → Settings → General → Rate Limiting
- Block recursive queries from external IPs (should not be exposed to internet)
- Monitor query logs for unusual patterns

**DNS Poisoning**:
- Enable DNSSEC validation (already enabled in config)
- Use secure upstream DNS (DoH/DoT)
- Monitor for unexpected responses

**Malware Domains**:
- Use malware blocklists (OISD, URLhaus)
- Monitor query logs for suspicious patterns (cryptomining, C2 servers)
- Alert on high blocked query rates

**DDoS Protection**:
- MetalLB + externalTrafficPolicy: Local reduces load
- Kubernetes automatic pod restart on failure
- Future: Add secondary instance for redundancy (Phase 2)

### Compliance Considerations

**Data Privacy**:
- Query logs contain PII (client IPs, domains accessed)
- Retain logs only as needed (7 days recommended)
- Document data retention policy
- Consider anonymizing logs: Web UI → Settings → Logs → Enable Log Anonymization

**Audit Trail**:
- Enable audit logging: Web UI → Settings → Logs → Enable Audit Logs
- Log admin actions (zone changes, config updates, user access)
- Integrate with SIEM if needed (syslog export)
- Retain audit logs for compliance period (e.g., 90 days)

---

## Verification Checklist

### Deployment Success
- [ ] Pod running and healthy in `dns-system` namespace
- [ ] LoadBalancer IPs assigned (10.0.0.53, 10.0.0.238)
- [ ] Web UI accessible at `http://10.0.0.238:5380`
- [ ] DNS queries resolving: `dig @10.0.0.53 google.com`
- [ ] Ad-blocking functional: `dig @10.0.0.53 doubleclick.net` returns 0.0.0.0
- [ ] Local zone resolving: `dig @10.0.0.53 plex.torquasmvo.internal`

### Migration Complete
- [ ] All Pi-hole blocklists migrated
- [ ] All custom DNS records migrated
- [ ] UniFi DHCP updated for all VLANs
- [ ] Clients receiving Technitium DNS via DHCP
- [ ] No DNS resolution errors reported
- [ ] Monitoring configured (Gatus health check)
- [ ] Documentation updated (`docs/ip_addresses.md`, `CLAUDE.md`)

### Stable Operation (1+ week)
- [ ] No DNS outages
- [ ] Query latency <50ms average
- [ ] Cache hit ratio >80%
- [ ] No blocked domains leaking (ads not showing)
- [ ] Pi-hole decommissioned
- [ ] Team trained on Technitium Web UI

### Long-term Success (Ongoing)
- [ ] Monthly maintenance performed
- [ ] Automatic updates via Renovate
- [ ] Backup tested and verified
- [ ] Clustering implemented (Phase 2+)
- [ ] Zero DNS outages for 6+ months

---

## Risk Assessment & Mitigation

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| DNS outage during migration | Medium | High | Parallel testing with Pi-hole as secondary DNS (1-2 weeks), gradual rollout |
| Network routing issues (192.168.1.x → 10.0.0.53) | Medium | High | Pre-deployment connectivity tests, UDM Pro firewall rule documentation |
| Incompatible blocklists | Low | Medium | Test blocklists before full migration, use well-known Technitium-compatible lists |
| Missing local DNS records | Medium | Medium | Comprehensive audit of Pi-hole custom DNS, test critical services before cutover |
| Performance issues | Low | Medium | Appropriate resource limits (2 CPU, 2Gi RAM), Longhorn fast storage (NVMe) |
| Longhorn PVC failure | Very Low | High | longhorn-prod StorageClass (3 replicas), recurring backups, manual config export |

---

## Success Criteria

**Phase 1 Success (Initial Deployment)**:
- Centralized DNS accessible from all VLANs (192.168.1.x → 10.0.0.53)
- Ad-blocking functional (replaces Pi-hole)
- Local domain resolution (*.torquasmvo.internal)
- Web UI management available
- No DNS outages during deployment

**Phase 2 Success (Migration Complete)**:
- Pi-hole instances decommissioned
- All VLANs using Technitium DNS
- 1+ week stable operation
- No user complaints about DNS issues
- Documentation complete

**Long-term Success**:
- Zero DNS outages for 6+ months
- HA clustering implemented (Phase 2)
- Monitoring and alerting operational
- Automated maintenance (Renovate updates)
- Positive user feedback (fast, reliable DNS)

---

## Critical Files Reference

### Kubernetes Manifests (to be created)
- `kubernetes/infrastructure/technitium-dns/app.yaml` - Argo CD Application
- `kubernetes/infrastructure/technitium-dns/metallb-ippool.yaml` - **NEW** MetalLB IP pool for DNS (10.0.0.53-54)
- `kubernetes/infrastructure/technitium-dns/deploy.yaml` - Deployment manifest
- `kubernetes/infrastructure/technitium-dns/svc-dns.yaml` - DNS LoadBalancer (10.0.0.53)
- `kubernetes/infrastructure/technitium-dns/svc-ui.yaml` - Web UI LoadBalancer (10.0.0.238)
- `kubernetes/infrastructure/technitium-dns/pvc.yaml` - Longhorn storage (5Gi)
- `kubernetes/infrastructure/technitium-dns/namespace.yaml` - Namespace: dns-system
- `kubernetes/infrastructure/technitium-dns/bitwarden-secrets.yaml` - BitwardenSecret resource
- `kubernetes/infrastructure/technitium-dns/kustomization.yaml` - Resource list
- `kubernetes/infrastructure/technitium-dns/README.md` - Operational documentation

### Reference Patterns (existing files)
- `kubernetes/infrastructure/portainer/deploy.yaml` - Stateful service with Bitwarden secrets pattern
- `kubernetes/infrastructure/longhorn/storageclasses/longhorn-prod.yaml` - Storage class configuration
- `kubernetes/infrastructure/metallb/overlays/default/metallb.yaml` - Existing MetalLB pool reference

### Documentation (to be updated)
- `docs/ip_addresses.md` - IP address registry (add 10.0.0.53, 10.0.0.54, 10.0.0.238)
- `CLAUDE.md` - Project instructions (add DNS services section)
- `docs/technitium-dns-migration.md` - Migration notes (to be created)
- `docs/technitium-dns-deployment-plan.md` - This document (for future reference)

---

## Resources & References

### Technitium DNS Server
- [Official Documentation](https://technitium.com/dns/)
- [Docker Hub: technitium/dns-server](https://hub.docker.com/r/technitium/dns-server)
- [Helm Chart](https://artifacthub.io/packages/helm/obeone/technitium-dnsserver)
- [Technitium DNS Server v14 Released](https://blog.technitium.com/2025/11/technitium-dns-server-v14-released.html)
- [Understanding Clustering And How To Configure It](https://blog.technitium.com/2025/11/understanding-clustering-and-how-to.html)

### Kubernetes & GitOps
- [MetalLB Documentation](https://metallb.universe.tf/)
- [Argo CD Documentation](https://argo-cd.readthedocs.io/)
- [Longhorn Documentation](https://longhorn.io/docs/)
- [Bitwarden Secrets Operator](https://bitwarden.com/help/secrets-manager-kubernetes-operator/)

### UniFi
- [UniFi Dream Machine Pro Documentation](https://ui.com/consoles)
- [UniFi Network Application Guide](https://help.ui.com/hc/en-us/categories/200320654-UniFi-Network-Application)

---

## Summary

This deployment plan provides a comprehensive, production-ready approach to deploying Technitium DNS Server in the BrainiacOps Kubernetes cluster. The phased implementation minimizes risk through parallel testing with existing Pi-hole instances, while the separate MetalLB IP pool preserves existing infrastructure.

**Key Takeaways**:
1. **MetalLB IP pool** (`dns-pool`) must be created before deployment for 10.0.0.53
2. **UDM Pro routing** handles inter-VLAN access (192.168.1.x ↔ 10.0.0.x)
3. **Parallel testing** (1-2 weeks) ensures smooth migration from Pi-hole
4. **GitOps workflow** (Argo CD) provides declarative, auditable deployments
5. **Future-proof** architecture supports HA clustering (Phase 2)

**Next Steps**:
1. Create Bitwarden secrets (admin credentials)
2. Create Kubernetes manifests (follow Phase 2 steps)
3. Test inter-VLAN connectivity (ping 10.0.0.x from 192.168.1.x)
4. Deploy via Git commit (Argo CD auto-sync)
5. Configure via Web UI (blocklists, local zones, logging)
6. Update UniFi DHCP (parallel testing, then full cutover)
7. Monitor and iterate (Gatus, logs, user feedback)

---

**Document Version**: 1.0
**Last Updated**: 2026-01-13
**Maintained By**: BrainiacOps Team
**Review Schedule**: Quarterly (or after major changes)
