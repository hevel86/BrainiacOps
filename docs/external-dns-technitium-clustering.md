# External-DNS + Technitium Setup

## Overview

Deploy External-DNS to automate DNS record creation for LoadBalancer services by communicating with the primary LXC Technitium node (`192.168.1.7`).

**Status**: Operational (January 2026)

**Scope:**
- External-DNS manages `*.torquasmvo.internal` records for LoadBalancer services only.
- External-DNS communicates directly with the primary LXC node (`192.168.1.7`).
- In-cluster Technitium node was evaluated but removed to simplify the architecture.

## Technitium Configuration (Primary: 192.168.1.7)

| Setting | Value |
|---------|-------|
| TSIG Key | `external-dns-key` (hmac-sha256) |
| Dynamic Updates | **Allow** (restricted to `external-dns-key`) |
| Zone Transfer (AXFR) | **Allow** (restricted to `external-dns-key`) |
| DNSSEC | SignedWithNSEC |

---

## Part 1: Automation Tooling

Configuration can be maintained using the `scripts/technitium/manage.py` tool.

### 1.1 Enable External-DNS Support
To automatically create the TSIG key and configure zone options (Update/Transfer policies) on the primary node:

```bash
export TECHNITIUM_TOKEN="your_api_token"
python3 scripts/technitium/manage.py external-dns --secret "your_tsig_shared_secret"
```

---

## Part 2: External-DNS Deployment

### 2.1 Infrastructure Structure

**Directory:** `kubernetes/infrastructure/external-dns/`

```
external-dns/
├── app.yaml              # Argo CD Application (Helm)
└── manifests/
    ├── kustomization.yaml
    ├── namespace.yaml
    └── bitwarden-secrets.yaml
```

### 2.2 app.yaml (Refactored for Helm Values)

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: external-dns
  namespace: argocd
spec:
  # ... (metadata omitted for brevity)
  source:
    repoURL: https://kubernetes-sigs.github.io/external-dns/
    chart: external-dns
    targetRevision: 1.15.0
    helm:
      values: |
        provider:
          name: rfc2136

        registry: txt
        txtOwnerId: brainiacops-cluster
        txtPrefix: externaldns-
        policy: upsert-only
        
        domainFilters:
          - torquasmvo.internal

        sources:
          - service

        extraArgs:
          - --rfc2136-host=192.168.1.7
          - --rfc2136-port=53
          - --rfc2136-zone=torquasmvo.internal
          - --rfc2136-tsig-keyname=external-dns-key
          - --rfc2136-tsig-secret-alg=hmac-sha256
          - --service-type-filter=LoadBalancer

        logLevel: info

        env:
          - name: EXTERNAL_DNS_RFC2136_TSIG_SECRET
            valueFrom:
              secretKeyRef:
                name: external-dns-tsig
                key: tsig-secret
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
| jellyfin | 10.0.0.218 | jellyfin.torquasmvo.internal |

---

## Verification

```bash
# 1. External-DNS deployment
kubectl get pods -n dns-external
kubectl logs -n dns-external -l app.kubernetes.io/name=external-dns

# 2. Test DNS
dig @192.168.1.7 plex.torquasmvo.internal +short
# Should return: 10.0.0.217

# 3. Verify TXT ownership record exists
dig @192.168.1.7 TXT externaldns-plex.torquasmvo.internal +short
```

---

## Notes & Troubleshooting

### RCODE 5 (Refused) on AXFR
If External-DNS logs `AXFR error: dns: bad xfr rcode: 5`, it means the server refused a zone transfer. 
- **Current Fix**: AXFR is disabled in `app.yaml` (`--rfc2136-tsig-axfr` flag removed). External-DNS works fine without AXFR for most use cases.
- **Root Cause**: Likely a Technitium ACL or policy issue that persists even when `zoneTransfer` is set to `Allow`.

### Duplicate Flag Errors
Avoid placing standard flags like `--registry` or `--log-level` in `extraArgs`. Use the native Helm values (`registry: txt`, `logLevel: info`) instead, as the chart adds defaults that cause "flag cannot be repeated" crashes.