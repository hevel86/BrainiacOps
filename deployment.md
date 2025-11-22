# BrainiacOps Deployment Guide

This guide provides comprehensive instructions for deploying and managing the BrainiacOps Kubernetes cluster using GitOps principles with Argo CD.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Deployment Architecture Overview](#deployment-architecture-overview)
  - [GitOps with Argo CD](#gitops-with-argo-cd)
  - [App-of-Apps Pattern](#app-of-apps-pattern)
  - [Sync Wave Orchestration](#sync-wave-orchestration)
- [Complete Bootstrap Process](#complete-bootstrap-process)
  - [Step 1: Tool Setup](#step-1-tool-setup)
  - [Step 2: Deploy Argo CD](#step-2-deploy-argo-cd)
  - [Step 3: Deploy Infrastructure](#step-3-deploy-infrastructure)
  - [Step 4: Deploy Applications](#step-4-deploy-applications)
  - [Step 5: Access Argo CD UI](#step-5-access-argo-cd-ui)
- [Infrastructure Deployment](#infrastructure-deployment)
  - [Deployment Sequence](#deployment-sequence)
  - [Key Components](#key-components)
- [Application Deployment](#application-deployment)
- [Verification and Health Checks](#verification-and-health-checks)
  - [Argo CD Application Status](#argo-cd-application-status)
  - [Pod Health](#pod-health)
  - [Storage Verification](#storage-verification)
  - [Network and Ingress](#network-and-ingress)
- [Troubleshooting](#troubleshooting)
  - [Argo CD Sync Failures](#argo-cd-sync-failures)
  - [Application Won't Deploy](#application-wont-deploy)
  - [Secret Injection Issues](#secret-injection-issues)
  - [Storage Provisioning Problems](#storage-provisioning-problems)
  - [Network and Ingress Issues](#network-and-ingress-issues)
- [Common Operations](#common-operations)
  - [Manual Sync](#manual-sync)
  - [Viewing Application Logs](#viewing-application-logs)
  - [Checking Resource Status](#checking-resource-status)
  - [Debugging Failed Deployments](#debugging-failed-deployments)
- [Adding New Components](#adding-new-components)
  - [Adding Applications](#adding-applications)
  - [Adding Infrastructure](#adding-infrastructure)
- [Best Practices](#best-practices)
  - [Git Workflow](#git-workflow)
  - [Testing Changes](#testing-changes)
  - [Secret Management](#secret-management)
  - [Documentation](#documentation)

---

## Prerequisites

Before deploying BrainiacOps, ensure you have:

1. **Running Talos Cluster**
   - 3-node control plane (brainiac-00, brainiac-01, brainiac-02)
   - Kubernetes v1.34.1
   - Talos v1.11.5
   - See [talos/README.md](talos/README.md) for cluster setup

2. **Network Configuration**
   - Cluster VIP: 10.0.0.30
   - MetalLB pool: 10.0.0.200-10.0.0.250
   - DNS resolution for *.torquasmvo.internal (optional for ingress)

3. **Required Tools**
   - kubectl (configured with cluster access)
   - mise (tool version manager)
   - All tools will be installed via mise in Step 1

4. **Access Requirements**
   - kubeconfig configured for cluster access
   - Git repository cloned locally
   - Bitwarden vault access (for secret injection)

5. **SOPS Configuration**
   - age key configured for decrypting secrets
   - Required if you need to modify encrypted secrets

---

## Deployment Architecture Overview

### GitOps with Argo CD

BrainiacOps follows a strict GitOps pattern where:

- **Git is the single source of truth** - All cluster state is declared in this repository
- **Argo CD continuously reconciles** - Cluster state automatically syncs with Git
- **Changes flow: Git → Argo CD → Kubernetes** - No manual kubectl apply for production resources
- **Declarative everything** - Infrastructure, applications, and configurations are all declarative YAML

### App-of-Apps Pattern

The deployment uses a hierarchical "app-of-apps" pattern:

```
bootstrap/infrastructure-app.yaml (Parent)
    ↓ discovers
kubernetes/infrastructure/**/app.yaml (Children)
    ↓ deploys
Actual infrastructure resources
```

**How it works:**
1. Parent Applications are configured with `directory.recurse: true`
2. They scan subdirectories for any file matching `**/app.yaml`
3. Each `app.yaml` is treated as an Argo CD Application
4. No need to maintain hardcoded lists of applications
5. Adding new components is as simple as creating an `app.yaml` file

**Three main parent applications:**
- `infrastructure-app.yaml` - Discovers all platform services in `kubernetes/infrastructure/`
- `apps-app.yaml` - Discovers all user applications in `kubernetes/apps/default/`
- `apps-external-app.yaml` - Tracks externally managed applications

### Sync Wave Orchestration

Applications deploy in a specific order using sync waves (controlled by annotation `argocd.argoproj.io/sync-wave`):

```
Wave -3: PersistentVolumes
Wave -2: PersistentVolumeClaims
Wave -1: Longhorn node configurations
Wave  0: Core infrastructure (MetalLB, Longhorn, cert-manager secrets, Traefik)
Wave  1: Infrastructure configuration (MetalLB pools, cert-manager issuers, Longhorn config)
Wave  9: Renovate secrets
Wave 10: Renovate bot
Wave 30: User applications (Plex, Radarr, Sonarr, etc.)
Wave 40: Management tools (Portainer, metrics-server)
Wave 50: Monitoring (Prometheus, Grafana, Gatus)
```

**Why sync waves matter:**
- Storage must exist before applications claim it
- Load balancer (MetalLB) must exist before ingress controller (Traefik)
- cert-manager must exist before applications request certificates
- Infrastructure must be ready before user applications deploy

---

## Complete Bootstrap Process

This section covers deploying Argo CD and all applications to a fresh Talos cluster.

### Step 1: Tool Setup

Install all required tools using mise:

```bash
# Trust the mise configuration
mise trust .mise.toml

# Install all pinned tools
mise install
```

This installs:
- kubectl
- argocd CLI
- talhelper
- talosctl
- helm
- kustomize
- kubeconform
- yamllint
- And all other pinned tools

**Verify installation:**
```bash
mise list
kubectl version --client
argocd version --client
```

### Step 2: Deploy Argo CD

Deploy Argo CD to the `argocd` namespace:

```bash
# Create namespace
kubectl apply -f kubernetes/bootstrap/argocd-namespace.yaml

# Deploy Argo CD (pulls from upstream via Kustomize)
kubectl apply -k kubernetes/bootstrap/argocd-install
```

**What happens:**
- Creates `argocd` namespace
- Deploys Argo CD v3.1.9 from upstream (github.com/argoproj/argo-cd)
- Starts Argo CD server, application controller, repo server, and other components

**Wait for Argo CD to be ready:**
```bash
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=300s
```

**Verify Argo CD is running:**
```bash
kubectl get pods -n argocd
```

Expected output: All Argo CD pods in `Running` state.

### Step 3: Deploy Infrastructure

Deploy the infrastructure parent application:

```bash
kubectl apply -f kubernetes/bootstrap/infrastructure-app.yaml
```

**What happens:**
1. Argo CD scans `kubernetes/infrastructure/` recursively for `**/app.yaml` files
2. Creates an Application for each discovered `app.yaml`
3. Deploys applications in sync-wave order (waves -3 through 50)
4. Infrastructure components auto-sync every 3 minutes

**Components deployed** (in order):
- **Wave -3 to -1**: Storage (PVs, PVCs, Longhorn configs)
- **Wave 0**: Core platform (MetalLB, Longhorn, cert-manager secrets, Traefik, Intel GPU, Bitwarden)
- **Wave 1**: Platform configuration (MetalLB pools, cert-manager issuers, Longhorn settings)
- **Wave 9-10**: Automation (Renovate)
- **Wave 40-50**: Monitoring (Prometheus, Grafana, Gatus)

**Monitor deployment progress:**
```bash
# Watch all infrastructure applications
kubectl get applications -n argocd -l argocd.argoproj.io/instance=infrastructure-app -w

# Or use Argo CD CLI
argocd app list -l argocd.argoproj.io/instance=infrastructure-app
```

**Deployment timeline:**
- Wave -3 to 0: ~2-5 minutes (storage and core infrastructure)
- Wave 1: ~1-2 minutes (configuration)
- Wave 9-10: ~1 minute (Renovate)
- Wave 40-50: ~2-3 minutes (monitoring stack)
- **Total: ~10-15 minutes** for complete infrastructure deployment

### Step 4: Deploy Applications

Deploy the applications parent application:

```bash
kubectl apply -f kubernetes/bootstrap/apps-app.yaml
```

**What happens:**
1. Argo CD scans `kubernetes/apps/default/` recursively for `**/app.yaml` files
2. Creates an Application for each discovered `app.yaml`
3. Deploys all applications at sync-wave 30 (after infrastructure ready)
4. Applications auto-sync every 3 minutes

**Applications deployed** (30+ apps):
- Media: Plex, Jellyfin, Tautulli
- Media management: Radarr, Sonarr, Prowlarr, Bazarr
- Downloads: qBittorrent, SABnzbd
- Automation: Home Assistant, Frigate
- Self-hosted services: Paperless-ngx, Immich, Nextcloud
- And many more...

**Monitor deployment progress:**
```bash
# Watch all applications
kubectl get applications -n argocd -l argocd.argoproj.io/instance=apps-app -w

# Check pod status
kubectl get pods -n default -w
```

**Deployment timeline:**
- All apps deploy in parallel at wave 30
- Most apps ready in ~5-10 minutes
- Some apps with large containers may take longer
- **Total: ~10-20 minutes** for all applications

**Optional: Deploy external app tracking:**
```bash
kubectl apply -f kubernetes/bootstrap/apps-external-app.yaml
```

This tracks externally managed applications (outside Argo CD control).

### Step 5: Access Argo CD UI

Get the initial admin password:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

**Access options:**

**Option 1: Port forward (quick access)**
```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
```
Then open: https://localhost:8080
- Username: `admin`
- Password: (from command above)

**Option 2: Ingress (if configured)**
Access via configured ingress hostname (e.g., https://argocd.torquasmvo.internal)

**First login steps:**
1. Login with admin credentials
2. Change the admin password (Settings → Accounts → admin → Update Password)
3. Explore the application tree
4. Verify all applications are Healthy and Synced

---

## Infrastructure Deployment

### Deployment Sequence

Infrastructure deploys in waves to handle dependencies:

#### Wave -3: Storage Foundations
- **media-pv** - PersistentVolume definitions for media storage

#### Wave -2: Storage Claims
- **media-pvc** - PersistentVolumeClaims for applications

#### Wave -1: Storage Configuration
- **longhorn-nodes** - Node-specific Longhorn configurations

#### Wave 0: Core Infrastructure
- **metallb** - Load balancer (IP pool 10.0.0.200-250)
- **longhorn** - Distributed block storage system
- **cert-manager-cloudflare-secret** - Cloudflare API token for DNS-01 challenges
- **traefik** - Ingress controller
- **intel-gpu-device-plugin** - Intel GPU access for transcoding
- **bitwarden** - Bitwarden Secrets Operator for secret injection
- **tailscale** - Tailscale operator for VPN access

#### Wave 1: Infrastructure Configuration
- **metallb-config** - IPAddressPool and L2Advertisement
- **cert-manager-config** - ClusterIssuer for Let's Encrypt certificates
- **longhorn-config** - StorageClasses, recurring jobs, Longhorn UI
- **cloudflare-ddns** - Dynamic DNS updates

#### Wave 9-10: Automation
- **renovate-secret** - GitHub token for Renovate
- **renovate** - Automated dependency updates

#### Wave 40: Management
- **portainer** - Kubernetes management UI
- **metrics-server** - Resource metrics
- **kube-prometheus-stack-secret** - Grafana secrets

#### Wave 50: Monitoring
- **kube-prometheus-stack** - Prometheus + Grafana
- **gatus** - Health dashboard
- **nut-exporter** - UPS monitoring metrics

### Key Components

#### MetalLB (Load Balancer)
**Purpose:** Provides LoadBalancer service type on bare metal
**Configuration:** IP pool 10.0.0.200-10.0.0.250
**Why it matters:** Applications can request external IPs for services

#### Longhorn (Distributed Storage)
**Purpose:** Distributed block storage across cluster nodes
**Configuration:**
- Auto-discovers disks >= 1.5TB on each node
- Provides RWO storage for applications
**Why it matters:** Applications can request persistent storage

#### cert-manager (TLS Certificates)
**Purpose:** Automated certificate management
**Configuration:**
- Cloudflare DNS-01 challenge
- Let's Encrypt production issuer
**Why it matters:** Automatic HTTPS for ingress

#### Traefik (Ingress Controller)
**Purpose:** HTTP/HTTPS routing to services
**Configuration:**
- LoadBalancer service (gets IP from MetalLB)
- Automatic cert-manager integration
**Why it matters:** External access to applications via HTTPS

#### Bitwarden Secrets Operator
**Purpose:** Inject secrets from Bitwarden vault into Kubernetes
**Configuration:**
- Authenticated with organization credentials
- Syncs secrets automatically
**Why it matters:** No secrets stored in Git, runtime secret injection

---

## Application Deployment

All user applications deploy at sync-wave 30, after infrastructure is ready.

### Application Discovery

Applications are discovered automatically:
1. Argo CD scans `kubernetes/apps/default/` recursively
2. Finds any file named `app.yaml`
3. Creates an Argo CD Application for each one
4. Applications auto-sync every 3 minutes

### Application Structure

Each application follows this structure:
```
kubernetes/apps/default/myapp/
├── app.yaml             # Argo CD Application definition
├── kustomization.yaml   # Kustomize configuration
├── deployment.yaml      # Kubernetes Deployment
├── service.yaml         # Kubernetes Service
├── ingress.yaml         # Traefik Ingress (optional)
└── pvc.yaml            # PersistentVolumeClaim (optional)
```

### Secret Injection

Applications use Bitwarden Secrets Operator for sensitive data:

```yaml
apiVersion: k8s.bitwarden.com/v1
kind: BitwardenSecret
metadata:
  name: myapp-secret
spec:
  organizationId: "org-id"
  secretName: myapp-secret
  map:
    - bwSecretId: "secret-id-in-bitwarden"
      secretKeyName: API_KEY
```

Secrets are injected at runtime and never stored in Git.

### Storage Provisioning

Applications request storage via PersistentVolumeClaims:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: myapp-data
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: longhorn
  resources:
    requests:
      storage: 10Gi
```

Longhorn automatically provisions storage on the cluster.

---

## Verification and Health Checks

### Argo CD Application Status

Check all applications:
```bash
kubectl get applications -n argocd
```

**Expected status:**
- HEALTH: Healthy
- SYNC: Synced

**Check specific application:**
```bash
kubectl describe application plex -n argocd
```

**View sync status:**
```bash
argocd app get plex
```

### Pod Health

**Check all pods:**
```bash
kubectl get pods -A
```

**Check specific namespace:**
```bash
kubectl get pods -n default
```

**Expected status:**
- STATUS: Running
- READY: All containers ready (e.g., 1/1, 2/2)

**Describe a pod:**
```bash
kubectl describe pod <pod-name> -n <namespace>
```

**View pod logs:**
```bash
kubectl logs <pod-name> -n <namespace>
```

### Storage Verification

**Check PersistentVolumes:**
```bash
kubectl get pv
```

**Expected status:**
- STATUS: Bound (if claimed)
- STATUS: Available (if unclaimed)

**Check PersistentVolumeClaims:**
```bash
kubectl get pvc -A
```

**Expected status:**
- STATUS: Bound

**Check Longhorn volumes:**
```bash
kubectl get volumes -n longhorn-system
```

### Network and Ingress

**Check LoadBalancer services:**
```bash
kubectl get svc -A --field-selector spec.type=LoadBalancer
```

**Expected:** External IP from MetalLB pool (10.0.0.200-250)

**Check Ingress resources:**
```bash
kubectl get ingress -A
```

**Expected:** ADDRESS column populated with Traefik service IP

**Test ingress:**
```bash
curl -k https://<ingress-hostname>
```

---

## Troubleshooting

### Argo CD Sync Failures

**Symptom:** Application shows "OutOfSync" or "Unknown" health status

**Diagnosis:**
```bash
# Check application status
kubectl describe application <app-name> -n argocd

# View Argo CD logs
kubectl logs -n argocd deployment/argocd-application-controller

# Check for events
kubectl get events -n argocd --sort-by='.lastTimestamp'
```

**Common causes:**
1. **Invalid YAML** - Syntax errors in manifests
   - Fix: Validate locally with `yamllint` and `kubeconform`
2. **Missing resources** - Dependencies not met (e.g., namespace doesn't exist)
   - Fix: Ensure dependencies are created first or adjust sync-wave
3. **Resource conflicts** - Resource already exists with different owner
   - Fix: Delete conflicting resource or adjust Application configuration
4. **Git sync issues** - Repository not accessible
   - Fix: Check Argo CD repository credentials

**Manual sync:**
```bash
argocd app sync <app-name>
```

**Force sync (ignore differences):**
```bash
argocd app sync <app-name> --force
```

### Application Won't Deploy

**Symptom:** Application synced but pods not running

**Diagnosis:**
```bash
# Check pod status
kubectl get pods -n <namespace>

# Describe pod for events
kubectl describe pod <pod-name> -n <namespace>

# Check logs
kubectl logs <pod-name> -n <namespace>

# Check events
kubectl get events -n <namespace> --sort-by='.lastTimestamp'
```

**Common causes:**
1. **Image pull errors** - Container image not found or inaccessible
   - Fix: Verify image name and tag, check image registry access
2. **Resource constraints** - Insufficient CPU/memory
   - Fix: Check node resources with `kubectl top nodes`, adjust resource requests
3. **Storage issues** - PVC not bound
   - Fix: Check PVC status, verify StorageClass exists, check Longhorn health
4. **Configuration errors** - Invalid environment variables or config
   - Fix: Review application logs, verify ConfigMaps and Secrets exist

**Check resource usage:**
```bash
kubectl top nodes
kubectl top pods -n <namespace>
```

### Secret Injection Issues

**Symptom:** Application fails with missing secrets

**Diagnosis:**
```bash
# Check BitwardenSecret status
kubectl get bitwardensecret -n <namespace>
kubectl describe bitwardensecret <secret-name> -n <namespace>

# Check if Secret was created
kubectl get secret <secret-name> -n <namespace>

# Check Bitwarden operator logs
kubectl logs -n bitwarden deployment/bitwarden-secrets-operator
```

**Common causes:**
1. **Bitwarden not authenticated** - Operator can't access vault
   - Fix: Check operator credentials, re-sync secret with proper authentication
2. **Secret ID incorrect** - bwSecretId doesn't exist in vault
   - Fix: Verify secret exists in Bitwarden vault, check organization ID
3. **Operator not running** - Bitwarden operator pod failed
   - Fix: Check operator pod status and logs

**Manual secret verification:**
```bash
# View secret (careful - exposes sensitive data)
kubectl get secret <secret-name> -n <namespace> -o yaml
```

### Storage Provisioning Problems

**Symptom:** PVC stuck in Pending state

**Diagnosis:**
```bash
# Check PVC status
kubectl describe pvc <pvc-name> -n <namespace>

# Check StorageClass
kubectl get storageclass

# Check Longhorn health
kubectl get pods -n longhorn-system
kubectl logs -n longhorn-system -l app=longhorn-manager
```

**Common causes:**
1. **StorageClass missing** - Requested StorageClass doesn't exist
   - Fix: Create StorageClass or use existing one (e.g., `longhorn`)
2. **Insufficient storage** - No node has enough free space
   - Fix: Check Longhorn dashboard, add more storage to nodes
3. **Longhorn not ready** - Longhorn system not fully deployed
   - Fix: Wait for Longhorn pods to be ready, check sync-wave timing
4. **Node selector mismatch** - PVC requires node that doesn't exist
   - Fix: Adjust node selector or ensure node exists

**Check Longhorn volumes:**
```bash
kubectl get volumes -n longhorn-system
kubectl get nodes -n longhorn-system
```

### Network and Ingress Issues

**Symptom:** Can't access application via ingress

**Diagnosis:**
```bash
# Check Ingress resource
kubectl describe ingress <ingress-name> -n <namespace>

# Check Traefik service
kubectl get svc -n traefik

# Check Traefik pods
kubectl get pods -n traefik

# Check Traefik logs
kubectl logs -n traefik -l app.kubernetes.io/name=traefik

# Check MetalLB
kubectl get ipaddresspool -n metallb-system
kubectl get l2advertisement -n metallb-system
kubectl logs -n metallb-system -l app=metallb
```

**Common causes:**
1. **Traefik not ready** - Ingress controller not running
   - Fix: Check Traefik pod status, review logs
2. **No LoadBalancer IP** - MetalLB not assigning IP
   - Fix: Check MetalLB configuration, verify IP pool available
3. **DNS not resolving** - Hostname doesn't resolve to Traefik IP
   - Fix: Add DNS entry or use /etc/hosts for testing
4. **Certificate issues** - TLS certificate not issued
   - Fix: Check cert-manager Certificate resource, review cert-manager logs
5. **Service missing** - Ingress points to non-existent service
   - Fix: Verify Service exists and has correct selector

**Test service directly:**
```bash
# Port forward to bypass ingress
kubectl port-forward -n <namespace> svc/<service-name> 8080:80

# Then test locally
curl http://localhost:8080
```

---

## Common Operations

### Manual Sync

Force an application to sync immediately:

```bash
# Sync a specific app
argocd app sync <app-name>

# Sync with prune (delete extra resources)
argocd app sync <app-name> --prune

# Sync and wait for completion
argocd app sync <app-name> --timeout 300
```

**Using kubectl:**
```bash
# Trigger sync via annotation
kubectl patch application <app-name> -n argocd --type merge -p '{"operation":{"initiatedBy":{"username":"kubectl"},"sync":{"revision":"HEAD"}}}'
```

### Viewing Application Logs

**View pod logs:**
```bash
# Current logs
kubectl logs <pod-name> -n <namespace>

# Follow logs
kubectl logs -f <pod-name> -n <namespace>

# Previous container logs (if crashed)
kubectl logs <pod-name> -n <namespace> --previous

# Specific container in multi-container pod
kubectl logs <pod-name> -c <container-name> -n <namespace>
```

**View Argo CD application controller logs:**
```bash
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller
```

### Checking Resource Status

**Get all resources in namespace:**
```bash
kubectl get all -n <namespace>
```

**Check specific resource type:**
```bash
kubectl get deployments -n <namespace>
kubectl get services -n <namespace>
kubectl get ingress -n <namespace>
kubectl get pvc -n <namespace>
```

**Watch resources update:**
```bash
kubectl get pods -n <namespace> -w
```

**Get resource YAML:**
```bash
kubectl get <resource-type> <resource-name> -n <namespace> -o yaml
```

### Debugging Failed Deployments

**Check deployment status:**
```bash
kubectl describe deployment <deployment-name> -n <namespace>
```

**Check replica set:**
```bash
kubectl get rs -n <namespace>
kubectl describe rs <replicaset-name> -n <namespace>
```

**Check pod events:**
```bash
kubectl describe pod <pod-name> -n <namespace>
kubectl get events -n <namespace> --sort-by='.lastTimestamp'
```

**Execute commands in pod:**
```bash
# Interactive shell
kubectl exec -it <pod-name> -n <namespace> -- /bin/sh

# Run single command
kubectl exec <pod-name> -n <namespace> -- ls -la /app
```

**Check resource limits:**
```bash
kubectl top pod <pod-name> -n <namespace>
kubectl describe node <node-name> | grep -A 10 "Allocated resources"
```

---

## Adding New Components

### Adding Applications

To add a new application to the cluster:

1. **Create application directory:**
   ```bash
   mkdir -p kubernetes/apps/default/myapp
   cd kubernetes/apps/default/myapp
   ```

2. **Create `app.yaml` (Argo CD Application):**
   ```yaml
   apiVersion: argoproj.io/v1alpha1
   kind: Application
   metadata:
     name: myapp
     namespace: argocd
     annotations:
       argocd.argoproj.io/sync-wave: "30"
   spec:
     project: default
     source:
       repoURL: https://github.com/yourusername/BrainiacOps
       targetRevision: HEAD
       path: kubernetes/apps/default/myapp
     destination:
       server: https://kubernetes.default.svc
       namespace: default
     syncPolicy:
       automated:
         prune: true
         selfHeal: true
       syncOptions:
         - CreateNamespace=true
   ```

3. **Create `kustomization.yaml`:**
   ```yaml
   apiVersion: kustomize.config.k8s.io/v1beta1
   kind: Kustomization
   resources:
     - deployment.yaml
     - service.yaml
     - ingress.yaml  # optional
     - pvc.yaml      # optional
   ```

4. **Create Kubernetes manifests:**
   - `deployment.yaml` - Deployment resource
   - `service.yaml` - Service resource
   - `ingress.yaml` - Ingress for external access (optional)
   - `pvc.yaml` - PersistentVolumeClaim for storage (optional)

5. **Validate manifests locally:**
   ```bash
   # Validate YAML syntax
   yamllint .

   # Validate Kubernetes resources
   kustomize build . | kubeconform -strict -
   ```

6. **Commit and push:**
   ```bash
   git add kubernetes/apps/default/myapp
   git commit -m "feat(myapp): add new application"
   git push
   ```

7. **Verify deployment:**
   - Argo CD will automatically discover the new `app.yaml`
   - Application will sync within 3 minutes (or manually sync with `argocd app sync myapp`)
   - Check status: `kubectl get application myapp -n argocd`

**The parent Application (`apps-app.yaml`) automatically discovers the new `app.yaml` - no additional configuration needed!**

### Adding Infrastructure

To add infrastructure components (similar to apps but with different considerations):

1. **Create infrastructure directory:**
   ```bash
   mkdir -p kubernetes/infrastructure/mycomponent
   cd kubernetes/infrastructure/mycomponent
   ```

2. **Create `app.yaml` with appropriate sync-wave:**
   ```yaml
   apiVersion: argoproj.io/v1alpha1
   kind: Application
   metadata:
     name: mycomponent
     namespace: argocd
     annotations:
       argocd.argoproj.io/sync-wave: "1"  # Adjust based on dependencies
   spec:
     # ... same as apps
   ```

3. **Choose sync-wave based on dependencies:**
   - Wave 0: Core infrastructure (must exist before other components)
   - Wave 1: Configuration (depends on wave 0 components)
   - Wave 9-10: Automation tools
   - Wave 40+: Monitoring and management

4. **Follow same validation and commit process as apps**

**The parent Application (`infrastructure-app.yaml`) automatically discovers the new `app.yaml` - no additional configuration needed!**

---

## Best Practices

### Git Workflow

1. **Always work on a branch:**
   ```bash
   git checkout -b feature/add-myapp
   ```

2. **Validate changes locally before committing:**
   ```bash
   yamllint kubernetes/apps/default/myapp/
   kustomize build kubernetes/apps/default/myapp | kubeconform -strict -
   ```

3. **Use conventional commits:**
   ```
   feat(myapp): add new application
   fix(plex): resolve PVC binding issue
   chore(renovate): update dependency
   ```

4. **Create pull request:**
   - GitHub Actions will run kubeconform validation
   - All PRs must pass validation before merge

5. **Merge to main:**
   - Argo CD automatically syncs changes within 3 minutes
   - Monitor deployment in Argo CD UI

### Testing Changes

**Test locally before deploying:**
```bash
# Validate YAML syntax
yamllint kubernetes/apps/default/myapp/

# Validate Kubernetes resources
kustomize build kubernetes/apps/default/myapp | kubeconform -strict -

# Preview what will be deployed
kubectl diff -k kubernetes/apps/default/myapp
```

**Test in staging first (if available):**
- Use a separate Argo CD Application pointing to a staging namespace
- Verify functionality before promoting to production

**Use Argo CD sync preview:**
```bash
# Preview what will change
argocd app diff myapp

# Sync with dry-run
argocd app sync myapp --dry-run
```

### Secret Management

**Never commit secrets to Git:**
- All runtime secrets use Bitwarden Secrets Operator
- Talos secrets encrypted with SOPS + age

**Encrypted secrets (SOPS):**
```bash
# Edit encrypted secret
sops talos/talsecret.sops.yaml

# Decrypt for viewing only
sops -d talos/talsecret.sops.yaml
```

**Runtime secrets (Bitwarden):**
- Store secrets in Bitwarden vault
- Reference in BitwardenSecret resources
- Secrets automatically injected at runtime

### Documentation

**Document all changes:**
1. Update relevant README files
2. Add comments to complex configurations
3. Document non-obvious design decisions in CLAUDE.md
4. Keep deployment.md updated with new processes

**Document new applications:**
- Add README.md in application directory if complex
- Explain configuration choices
- Document any external dependencies

---

## Summary

BrainiacOps follows a strict GitOps pattern where:

1. **Git is the source of truth** - All cluster state declared in Git
2. **Argo CD manages everything** - Continuous reconciliation with Git
3. **App-of-apps enables discovery** - New components auto-discovered via `app.yaml`
4. **Sync waves handle dependencies** - Ordered deployment prevents conflicts
5. **Automation is everywhere** - Renovate updates, GitHub Actions validation, auto-sync

**Common deployment workflow:**
1. Make changes in Git branch
2. Validate locally (yamllint, kubeconform)
3. Create PR → GitHub Actions validates
4. Merge to main
5. Argo CD auto-syncs within 3 minutes
6. Verify in Argo CD UI and with kubectl

For cluster management operations, see [talos/README.md](talos/README.md).

For repository context and architecture patterns, see [CLAUDE.md](CLAUDE.md).

---

**Last Updated:** 2025-11-21
