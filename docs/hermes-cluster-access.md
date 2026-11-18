# Hermes Cluster & GitOps Access

Hermes ([kubernetes/apps/ai/hermes](file:///home/pi/gitstuff/BrainiacOps/kubernetes/apps/ai/hermes)) runs with a dedicated `default/hermes` ServiceAccount, SHA-256 verified SRE/GitOps CLI tools on its persistent volume (`/opt/data/.local/bin`), and non-interactive GitHub authentication (`GIT_ASKPASS`).

## Installed CLI Tooling (`/opt/data/.local/bin`)

Installed and SHA-256 verified by the `setup` init container ([scripts/setup.sh](file:///home/pi/gitstuff/BrainiacOps/kubernetes/apps/ai/hermes/scripts/setup.sh)):
- `kubectl` (`v1.37.2`)
- `talosctl` (`v1.14.6`)
- `gh` (`v2.104.0`)
- `kustomize` (`v5.8.0`)
- `kubeconform` (`v0.8.0`)
- `helm` (`v4.3.2`)
- `jq` (`1.7.1`)
- `yq` (`v4.45.1`)
- `stern` (`1.35.0`)
- `tirith` (`v0.5.0`)

## Kubernetes RBAC Scope ([rbac.yaml](file:///home/pi/gitstuff/BrainiacOps/kubernetes/apps/ai/hermes/rbac.yaml))

1. **Cluster-Wide Read Diagnostics (`ClusterRole/hermes-cluster-reader`)**:
   - Read-only (`get`, `list`, `watch`) across all namespaces on workloads, pods, pod logs, events, services, PVCs, PVs, nodes, ingresses, Traefik `IngressRoute`s, Argo CD `Application`s, Longhorn CRDs, Cert-Manager certificates, MetalLB pools, BitwardenSecret CR metadata, and Tuppr upgrades.
   - **No Secret Access**: Kubernetes `Secret` objects are excluded across all namespaces.
2. **Live Workload Testing & Repair (`ClusterRole/hermes-workload-operator` bound in `default` and `games`)**:
   - Full write (`create`, `update`, `patch`, `delete`) on `Deployments`, `StatefulSets`, `DaemonSets`, `ReplicaSets`, `Jobs`, `CronJobs`, `Services`, `ConfigMaps`, `Ingresses`, and Traefik `IngressRoute`/`Middleware` resources.
   - `delete` on `Pods` (for clearing stuck pods) without `pods/exec` or `PersistentVolumeClaim` deletion.
3. **Argo CD Sync & Live-Test Control (`Role/hermes-argocd-operator` in `argocd`)**:
   - `get`, `list`, `watch`, `patch`, `update` on `applications.argoproj.io` (for triggering manual syncs, hard refreshes, or temporarily pausing `syncPolicy` during live testing of auto-synced apps).
4. **Longhorn Operational Recovery (`Role/hermes-longhorn-operator` in `longhorn-system`)**:
   - `patch`, `update` on `settings.longhorn.io`, `delete` on `replicas.longhorn.io` (for purging `stopped` ghost replicas), and `delete` on `pods` in `longhorn-system` (for restarting manager/instance-manager pods).

## Standard Operational Workflow

1. **Diagnose**:
   - Inspect live state with `kubectl`, `stern`, and `jq`/`yq`, and inspect manifests in `/opt/data/repos/BrainiacOps`.
2. **Test Live in the Cluster**:
   - **Manual-Sync Apps** (most apps in `default` and `games`): Apply/patch the workload directly in-cluster (`kubectl patch`, `kubectl set image`, `kubectl rollout restart`, etc.) and verify pod readiness and logs.
   - **Auto-Sync Apps** (`infrastructure/*`, `gotenberg`, `hytale`): If live testing requires pausing `selfHeal`, temporarily patch the Argo CD Application (`kubectl patch application -n argocd <app> --type=merge -p '{"spec":{"syncPolicy":null}}'`), test the fix, and restore via Git PR.
3. **Validate & Open a Git PR**:
   - In `/opt/data/repos/BrainiacOps`, fetch latest `origin/master` and create a clean branch (`git checkout -b fix/<app>-<issue> origin/master`).
   - Make the permanent manifest changes.
   - Validate before committing:
     ```bash
     kustomize build <path> | kubeconform -strict -ignore-missing-schemas -summary -
     kubeconform -strict -ignore-missing-schemas -summary <changed_yaml_files>
     ```
   - Commit, push (`git push -u origin HEAD`), and create a PR (`gh pr create`).
4. **Argo CD Sync**:
   - Once the PR is merged, auto-synced apps reconcile automatically.
   - For manual-sync apps, trigger an Argo CD refresh/sync via `kubectl patch application -n argocd <app>`.
