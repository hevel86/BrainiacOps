# Gemini Code Assistant Context

This document provides context for the Gemini Code Assistant to understand the `BrainiacOps` project.

## Critical Rules

**This is a GitOps repository. All changes are automatically deployed to a live Kubernetes cluster.**

- **NEVER commit secrets, passwords, API keys, or tokens** - Use Bitwarden Secrets Operator references instead
- **NEVER hardcode sensitive values** in manifests - Reference `BitwardenSecret` resources
- **Talos secrets** must only exist in `talsecret.sops.yaml` (encrypted with SOPS+age)
- **NEVER auto-stage (git add) or auto-commit changes** - The user will perform all Git operations manually. Reading git logs for context is permitted.
- When in doubt, ask before committing anything that could contain sensitive data

## Executive Summary

**BrainiacOps** is a GitOps-managed home lab Kubernetes cluster using Argo CD as the single source of truth. It follows a declarative, infrastructure-as-code approach with heavy emphasis on automation, security, and maintainability.

**Key Characteristics**:
- GitOps controller: Argo CD (declarative, automated sync)
- Operating system: Talos Linux (immutable, minimal, secure)
- Container orchestration: Kubernetes v1.34.1
- Storage backend: Longhorn distributed storage
- Networking: Traefik + MetalLB + Tailscale
- Secrets: Bitwarden Secrets Operator (no secrets in Git)
- Dependency automation: Renovate with custom regex managers
- CI/CD validation: GitHub Actions + kubeconform
- Tool version management: mise + aqua

## Repository Structure

```
BrainiacOps/
├── kubernetes/
│   ├── bootstrap/              # Argo CD installation & app-of-apps seed
│   ├── infrastructure/         # Platform services (sync-wave 0-1)
│   │   ├── metallb/           # Load balancer (IPs: 10.0.0.200-10.0.0.250)
│   │   ├── traefik/           # Ingress controller
│   │   ├── cert-manager/      # TLS certificates (Cloudflare)
│   │   ├── longhorn/          # Distributed block storage
│   │   ├── bitwarden/         # Bitwarden Secrets Operator
│   │   ├── monitoring/        # Prometheus + Grafana + Gatus
│   │   └── [other infra]
│   ├── apps/                   # User-facing applications
│   │   ├── default/           # Primary namespace (30+ apps)
│   │   │   ├── plex/          # Media server
│   │   │   ├── radarr/        # Movie management
│   │   │   ├── sonarr/        # TV management
│   │   │   └── [other apps]
│   │   └── external/          # Externally-managed apps
│   └── testing/               # Experiments and benchmarks
├── talos/                      # Talos Linux cluster configuration
│   ├── talconfig.yaml         # Source of truth (talhelper input)
│   ├── talsecret.sops.yaml    # Encrypted secrets (age+SOPS)
│   ├── clusterconfig/         # Generated configs (gitignored)
│   └── README.md              # Comprehensive management guide
├── .mise.toml                  # Tool version management
├── renovate.json5              # Dependency automation config
└── .github/workflows/          # CI/CD validation
```

## Core Concepts

### App-of-Apps Pattern

Argo CD Applications act as parent controllers that discover child Applications via `directory.recurse` and `include: "**/app.yaml"`. This enables declarative, hierarchical deployment without hardcoding app lists.

**Deployment Order (Sync Waves)**:
- Wave -2: PersistentVolumes
- Wave 0: Infrastructure core (MetalLB, Longhorn, cert-manager secrets)
- Wave 1: Infrastructure dependencies (cert-manager config)
- Wave 30: User applications

### Configuration Workflow

```
talconfig.yaml + talsecret.sops.yaml
         ↓
   talhelper genconfig
         ↓
clusterconfig/*.yaml (machine configs)
         ↓
   talosctl apply-config
         ↓
   Talos Node Configuration
```

### Talos Factory Installer Pattern

**Critical**: The `talosImageURL` in `talconfig.yaml` must point to the factory installer with schematic ID:

```yaml
talosImageURL: factory.talos.dev/installer/284a1fe978ff4e6221a0e95fc1d01278bab28729adcb54bb53f7b0d3f2951dcc
```

This ensures system extensions (Intel GPU, iSCSI, NUT, etc.) persist through installation. If using the base installer (`ghcr.io/siderolabs/installer`), extensions will disappear after reboot.

## Key Architecture Patterns

### GitOps Bootstrap Process

1. `kubectl apply` creates Argo CD namespace and resources
2. Argo CD starts and initializes
3. `infrastructure-app.yaml` is applied (parent Application)
4. Argo CD syncs all `app.yaml` files in `kubernetes/infrastructure/` recursively
5. Infrastructure deploys with sync-wave ordering (0 → 1)
6. User apps deploy with wave 30 (after infrastructure ready)

Adding new components is as simple as creating an `app.yaml` file—the parent Application discovers it automatically.

### Dependency Management via Renovate

Renovate creates PRs automatically for:
- Docker image tags in manifests (custom regex manager)
- Helm chart versions (complex multiline regex)
- CLI tool versions in `.mise.toml` (aqua/pipx managers)

All PRs are validated by kubeconform CI before merge.

### Storage Architecture

- **PersistentVolumes** define Longhorn-backed storage
- **PersistentVolumeClaims** are claimed by apps
- Longhorn auto-configures disks >= 1.5TB on each node
- System disks use disk selectors (NVMe <= 600GB)

**High Availability Configuration**:
- `longhorn-prod` StorageClass: 3 replicas, `dataLocality: best-effort`
- `node-down-pod-deletion-policy`: `delete-both-statefulset-and-deployment-pod` (enables automatic pod failover)
- Default replica count: 3 (data on all nodes)
- On node failure: Longhorn deletes stuck pods, Kubernetes reschedules to healthy node, volume attaches using remaining replicas

### Secret Management

**Runtime secrets**: Bitwarden Secrets Operator injects from Bitwarden vault into Kubernetes Secrets (never in Git)

**Talos secrets**: `talsecret.sops.yaml` encrypted with SOPS+age (contains cluster certificates, tokens, etcd crypto)

### Pre-commit Security

On `git commit`:
1. YAML files checked for trailing newlines
2. Commit fails if YAML invalid

## Development Workflows

### Adding New Applications

1. Create directory: `kubernetes/apps/default/myapp/`
2. Create `app.yaml` (Argo CD Application resource)
3. Create `kustomization.yaml` and manifests
4. Set sync wave: `argocd.argoproj.io/sync-wave: "30"`
5. Enable auto-sync in Application spec
6. Parent Application discovers it automatically

### Adding New Infrastructure

Same as apps but:
- Place in `kubernetes/infrastructure/mycomponent/`
- Use sync wave 0 or 1
- Infrastructure parent Application discovers automatically

### Adding Nodes to Talos Cluster

See `talos/README.md` for detailed guide. Summary:

1. Edit `talos/talconfig.yaml`:
   - Add node to `nodes` list
   - Add IP to `additionalApiServerCertSans`

2. Generate configs:
   ```bash
   cd talos && talhelper genconfig
   ```

3. Check disks on new node:
   ```bash
   talosctl get disks --nodes 10.0.0.36 --insecure
   ```

4. Apply config:
   ```bash
   talosctl apply-config --insecure --nodes 10.0.0.36 --file clusterconfig/talos-rao-brainiac-02.yaml
   ```

5. Verify extensions:
   ```bash
   talosctl -n 10.0.0.36 get extensions
   ```

### Updating Dependencies

1. Renovate creates PR automatically
2. GitHub Actions runs kubeconform validation
3. Review and merge PR
4. If Talos tools changed: run `talhelper genconfig`
5. **If Argo CD version changed**: Manually run `kubectl apply -k kubernetes/bootstrap/argocd-install`

## Common Commands

### Tool Setup

```bash
# Install all pinned tools
mise install

# Trust repo config for first-time use
mise trust .mise.toml
```

### Kubernetes Operations

```bash
# View cluster state
kubectl get nodes -o wide
kubectl get pods -A
kubectl get applications -n argocd

# Sync an Argo CD app
argocd app sync <app-name>

# Validate manifests
kustomize build kubernetes/apps/default/plex | kubeconform -strict -
yamllint kubernetes/apps/default/plex/
```

### Talos Cluster Management

```bash
# View node status
talosctl -n 10.0.0.34 services
talosctl -n 10.0.0.34 etcd members

# Check disks before installation
talosctl get disks --nodes 10.0.0.36 --insecure

# Generate machine configs from talconfig.yaml
cd talos && talhelper genconfig

# Apply config to new node
talosctl apply-config \
  --insecure \
  --nodes 10.0.0.36 \
  --file clusterconfig/talos-rao-brainiac-02.yaml

# Verify extensions after boot
talosctl -n 10.0.0.36 get extensions

# Upgrade Talos
talosctl upgrade \
  --nodes 10.0.0.35 \
  --image factory.talos.dev/metal-installer/284a...dcc:v1.11.5
```

### Secret Management

```bash
# Decrypt Talos secrets
sops -d talos/talsecret.sops.yaml

# Edit encrypted secrets
sops talos/talsecret.sops.yaml
```

## Common Issues

### Extensions Missing After Node Boot

**Cause**: `talconfig.yaml` uses base installer instead of factory installer

**Fix**: Update `talosImageURL` to factory URL with schematic, regenerate configs, reapply

### Argo CD App Won't Sync

**Diagnosis**:
```bash
kubectl describe application -n argocd myapp
kubectl logs -n argocd deployment/argocd-app-controller
```

**Common causes**: Missing namespace, secret not injected, resource conflict

### Renovate PR Fails CI

**Fix**: Test locally before approving:
```bash
kustomize build kubernetes/apps/default/myapp | kubeconform -strict -
```

## Current Cluster Details & Status

**Cluster Name**: talos-rao

**Control Plane Nodes**:
- brainiac-00 (10.0.0.34)
- brainiac-01 (10.0.0.35)
- brainiac-02 (10.0.0.36)

**DNS Infrastructure**:
- Primary: dns1.torquasmvo.internal (192.168.1.7)
- Secondary: dns2.torquasmvo.internal (192.168.1.8)
- Optimization: DoH + 0.0.0.0 Blocking mode

**Configuration**:
- Talos v1.12.1, Kubernetes v1.35.0
- VIP: 10.0.0.30 (HA endpoint)
- Pod CIDR: 10.244.0.0/16
- Service CIDR: 10.96.0.0/12
- MetalLB pool: 10.0.0.200-10.0.0.250

**System Extensions** (all nodes):
- siderolabs/i915 (Intel GPU for transcoding)
- siderolabs/intel-ice-firmware
- siderolabs/intel-ucode
- siderolabs/iscsi-tools
- siderolabs/mei
- siderolabs/nut-client (UPS monitoring)
- siderolabs/nvme-cli
- siderolabs/thunderbolt
- siderolabs/util-linux-tools

### Status (as of 2026-01-14)

The cluster is fully operational, healthy, and up-to-date. The HA control plane is established across three nodes. DNS services have been migrated from Pi-hole to a High-Availability Technitium DNS cluster with DoH and optimized blocking modes.


---
*This document was last updated by Gemini by merging context from `CLAUDE.md`.*