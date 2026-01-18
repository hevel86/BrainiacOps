# External-DNS + Technitium Clustering Plan

## Overview

Deploy External-DNS to automate DNS record creation for LoadBalancer services, and configure K8s Technitium as a cluster tertiary node.

**Scope:**
- External-DNS manages `*.torquasmvo.internal` records for LoadBalancer services only
- K8s Technitium (10.0.0.53) joins as **tertiary** node (dns1=Primary, dns2=Secondary already exist)
- No changes to CoreDNS or IngressRoute configurations

## Current Technitium State (from API)

| Setting | Value |
|---------|-------|
| Version | 14.3 |
| Clustering | Enabled |
| Primary | dns1.torquasmvo.internal (192.168.1.7) |
| Secondary | dns2.torquasmvo.internal (192.168.1.8) - Connected |
| TSIG Keys | `cluster-catalog.torquasmvo.internal` (cluster sync only) |
| Dynamic Updates | **Deny** - needs enabling |
| DNSSEC | SignedWithNSEC |
| Existing Records | ~64 A records (manually created) |

**K8s services with existing manual DNS records:**
- plex: 10.0.0.217, radarr: 10.0.0.225, sonarr: 10.0.0.228
- jellyfin: 10.0.0.218, audiobookshelf: 10.0.0.208, grafana: 10.0.0.232
- And 20+ more in the 10.0.0.x range

---

## Part 1: K8s Technitium Clustering (Tertiary Node)

**Note:** Technitium does NOT support clustering via environment variables. Clustering must be configured via Web UI after deployment.

### 1.1 Ensure K8s Technitium is Running

The existing deployment at `kubernetes/infrastructure/technitium-dns/` should be active:
- Web UI: http://10.0.0.238:5380
- DNS: 10.0.0.53

If not running, enable it via Argo CD or create the `app.yaml` if missing.

**Important:** The DNS service (`svc-dns.yaml`) must expose both port 53 (DNS) and port 53443 (HTTPS) on 10.0.0.53 for clustering to work properly. This is because Technitium clustering uses:
- Port 53 for NOTIFY and AXFR (zone transfers)
- Port 53443 for HTTPS API communication

### 1.2 Manual: Configure K8s Technitium to Join Cluster

Access http://10.0.0.238:5380 (K8s Technitium Web UI):

1. **Settings → Clustering**
2. Enable Clustering: **Yes**
3. Cluster Type: **Secondary**
4. Primary Server Address: `192.168.1.7` (or `dns1.torquasmvo.internal`)
5. **This Server Address: `10.0.0.53`** (NOT 10.0.0.238 - must use the DNS LoadBalancer IP)
6. Enter the **Cluster Secret** from the primary node
7. Click **Save Settings**

### 1.3 Verify on LXC Primary

Access http://192.168.1.7:5380 → Settings → Clustering:
- Should now show 3 nodes:
  - dns1.torquasmvo.internal (Primary, Self)
  - dns2.torquasmvo.internal (Secondary, Connected)
  - technitium-dns.torquasmvo.internal (Secondary, Connected) ← K8s node

### 1.4 Optional: Add DNS Record for K8s Technitium

Add A record in Technitium for the K8s node:
- `technitium-k8s.torquasmvo.internal` → `10.0.0.53`

---

## Part 2: External-DNS Deployment

### 2.1 Manual: Technitium TSIG & Dynamic Updates Setup

Access http://192.168.1.7:5380:

**Step 1: Create TSIG Key for External-DNS**
- Settings → TSIG → Add
- Key Name: `external-dns-key`
- Algorithm: `HMAC-SHA256`
- Click Save (auto-generates secret)
- Copy the generated **Shared Secret**

**Step 2: Enable Dynamic Updates on Zone** (Currently: Deny)
- Zones → `torquasmvo.internal` → click **Options** (gear icon)
- Go to **Zone Options** tab
- Set **Update**: `Allow` (currently Deny)
- Under **Update Security Policies**, click **Add**:
  - TSIG Key Name: `external-dns-key`
  - Domain: `*.torquasmvo.internal`
  - Allowed Types: `A, AAAA, TXT`
- Click **Save**

**Step 3: Store TSIG Secret in Bitwarden**
- Create secret: `external-dns-tsig-secret`
- Value: TSIG shared secret from Step 1
- Note the Bitwarden secret ID

### 2.2 Create External-DNS Infrastructure

**Directory:** `kubernetes/infrastructure/external-dns/`

```
external-dns/
├── app.yaml              # Argo CD Application (Helm)
└── manifests/
    ├── kustomization.yaml
    ├── namespace.yaml
    └── bitwarden-secrets.yaml
```

### 2.3 app.yaml (Argo CD Application)

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: external-dns-config
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "0"
spec:
  project: default
  source:
    repoURL: https://github.com/hevel86/BrainiacOps
    targetRevision: HEAD
    path: kubernetes/infrastructure/external-dns/manifests
  destination:
    server: https://kubernetes.default.svc
    namespace: dns-external
  syncPolicy:
    automated:
      prune: false
      selfHeal: true
---
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: external-dns
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "1"
spec:
  project: default
  destination:
    server: https://kubernetes.default.svc
    namespace: dns-external
  source:
    repoURL: https://kubernetes-sigs.github.io/external-dns/
    chart: external-dns
    targetRevision: 1.15.0
    helm:
      values: |
        provider:
          name: rfc2136

        extraArgs:
          - --rfc2136-host=192.168.1.7
          - --rfc2136-port=53
          - --rfc2136-zone=torquasmvo.internal
          - --rfc2136-tsig-keyname=external-dns-key
          - --rfc2136-tsig-secret-alg=hmac-sha256
          - --rfc2136-tsig-axfr
          - --source=service
          - --service-type-filter=LoadBalancer
          - --domain-filter=torquasmvo.internal
          - --registry=txt
          - --txt-owner-id=brainiacops-cluster
          - --txt-prefix=externaldns-
          - --policy=upsert-only
          - --log-level=info

        env:
          - name: EXTERNAL_DNS_RFC2136_TSIG_SECRET
            valueFrom:
              secretKeyRef:
                name: external-dns-tsig
                key: tsig-secret

        serviceAccount:
          create: true
          name: external-dns

        interval: 1m

        resources:
          requests:
            cpu: 50m
            memory: 64Mi
          limits:
            cpu: 200m
            memory: 128Mi
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
```

### 2.4 manifests/kustomization.yaml

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - namespace.yaml
  - bitwarden-secrets.yaml
```

### 2.5 manifests/namespace.yaml

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: dns-external
```

### 2.6 manifests/bitwarden-secrets.yaml

```yaml
apiVersion: k8s.bitwarden.com/v1
kind: BitwardenSecret
metadata:
  name: external-dns-tsig
  namespace: dns-external
spec:
  secretName: external-dns-tsig
  organizationId: "9f7b77c1-18f7-4dc8-b252-b274015d6c40"
  authToken:
    secretName: bw-auth-token
    secretKey: token
  map:
    - bwSecretId: "<TSIG_SECRET_ID>"
      secretKeyName: tsig-secret
```

---

## Part 3: Service Annotations

Add to LoadBalancer services that need DNS records.

**Example - Plex** (`kubernetes/apps/default/plex/svc.yaml`):
```yaml
metadata:
  name: plex
  annotations:
    external-dns.alpha.kubernetes.io/hostname: plex.torquasmvo.internal
```

**Services to annotate:**
| Service | IP | Hostname |
|---------|-----|----------|
| plex | 10.0.0.217 | plex.torquasmvo.internal |
| radarr | 10.0.0.225 | radarr.torquasmvo.internal |
| sonarr | 10.0.0.228 | sonarr.torquasmvo.internal |
| audiobookshelf | 10.0.0.208 | audiobookshelf.torquasmvo.internal |
| jellyfin | (check IP) | jellyfin.torquasmvo.internal |

---

## Implementation Order

1. **Manual: Technitium TSIG & Dynamic Updates** (on LXC Primary)
   - Create TSIG key `external-dns-key`
   - Enable dynamic updates on `torquasmvo.internal` zone
   - Store TSIG secret in Bitwarden

2. **Manual: Bitwarden secret**
   - Create `external-dns-tsig-secret` with the TSIG shared secret
   - Note the Bitwarden secret ID

3. **Git: External-DNS deployment**
   - Create `kubernetes/infrastructure/external-dns/` structure
   - Update Bitwarden secret ID in `bitwarden-secrets.yaml`
   - Commit and push → Argo CD discovers and deploys

4. **Manual: K8s Technitium clustering** (via Web UI)
   - Access http://10.0.0.238:5380
   - Configure as Secondary, point to 192.168.1.7
   - Enter cluster secret from primary
   - Verify 3 nodes visible on primary

5. **Git: Service annotations**
   - Add annotations to LoadBalancer services one at a time
   - Delete corresponding manual record in Technitium first
   - Verify External-DNS creates new record with TXT ownership

---

## Verification

```bash
# 1. External-DNS deployment
kubectl get pods -n dns-external
kubectl logs -n dns-external -l app.kubernetes.io/name=external-dns

# 2. Check BitwardenSecret synced
kubectl get secret external-dns-tsig -n dns-external

# 3. K8s Technitium clustering (check via Web UI)
# http://192.168.1.7:5380 → Settings → Clustering
# Should show 3 nodes connected

# 4. Test DNS after annotating a service
dig @192.168.1.7 plex.torquasmvo.internal +short
# Should return: 10.0.0.217

# 5. Verify TXT ownership record exists
dig @192.168.1.7 TXT externaldns-plex.torquasmvo.internal +short
# Should return: "heritage=external-dns,external-dns/owner=brainiacops-cluster..."

# 6. Test from K8s Technitium (replication working)
dig @10.0.0.53 plex.torquasmvo.internal +short
# Should also return: 10.0.0.217
```

---

## Files to Create/Modify

**Create:**
- `kubernetes/infrastructure/external-dns/app.yaml`
- `kubernetes/infrastructure/external-dns/manifests/kustomization.yaml`
- `kubernetes/infrastructure/external-dns/manifests/namespace.yaml`
- `kubernetes/infrastructure/external-dns/manifests/bitwarden-secrets.yaml`

**Modify:**
- `kubernetes/apps/default/plex/svc.yaml` (add annotation)
- `kubernetes/apps/default/radarr/svc.yaml` (add annotation)
- `kubernetes/apps/default/sonarr/svc.yaml` (add annotation)
- (other LoadBalancer services as needed)

**No changes needed:**
- K8s Technitium clustering is configured via Web UI, not manifests

---

## Migration Strategy for Existing Records

~64 A records already exist in Technitium (manually created). Strategy:

1. **Initial deployment**: Use `policy: upsert-only` (won't delete anything)
2. **Add annotations** to services one at a time
3. **External-DNS creates TXT ownership records** (`externaldns-plex.torquasmvo.internal`)
4. **Verify** each record updates correctly
5. **Delete manual records** in Technitium after External-DNS takes over
6. **Later**: Switch to `policy: sync` for full automation (auto-delete orphans)

**Important**: External-DNS will NOT overwrite existing records without TXT ownership markers. You must delete the manual record first, then External-DNS will create and manage it.

---

## Notes

- DNSSEC is enabled on the zone (SignedWithNSEC) - External-DNS works fine with this
- External-DNS uses `policy: upsert-only` initially to avoid deleting existing manual records
- TXT ownership records (`externaldns-*.torquasmvo.internal`) track which records External-DNS manages
- Version: External-DNS chart 1.15.0, Technitium 14.3.0
- Clustering uses separate TSIG key (`cluster-catalog.torquasmvo.internal`) - don't confuse with External-DNS key
