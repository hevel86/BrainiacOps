# Immich

Immich is deployed from the official OCI Helm chart. PostgreSQL, its Longhorn
storage, the Bitwarden secret mapping, and the Traefik route are owned by the
companion `immich-resources` Argo CD application. The photo library is shared
infrastructure owned by the existing `media-pv` and `media-pvc` applications.

## Before the first sync

1. Confirm that the mapped `IMMICH_DB_PASSWORD` value in Bitwarden Secrets
   Manager contains only `A-Za-z0-9` characters, as required by Immich's
   supported deployment example.
2. Confirm that TrueNAS exports `/mnt/fast/pictures/immich` over NFS to the
   Kubernetes nodes. The existing `media-pv` and `media-pvc` infrastructure
   applications will create and bind `immich-library-pv` and
   `immich-library-pvc` automatically.
3. Commit and push the manifests.
4. Sync `immich-resources` and wait for `immich-secrets`, PostgreSQL, and the
   two Longhorn PVCs to become ready.
5. Sync `immich`, then open <https://immich.torquasmvo.com> to create the first
   administrator account.

Both Argo CD applications intentionally require an explicit first sync. This
prevents Immich or PostgreSQL from starting before the Bitwarden mapping has
been configured.

## Storage and acceleration

- Library: the TrueNAS NFS export `/mnt/fast/pictures/immich`, statically bound
  as a 2 TiB RWX PV/PVC and retained independently of the Immich application.
- PostgreSQL: 20 GiB on `longhorn-prod`, expandable and retained by Argo CD.
- Machine-learning model cache: 10 GiB on `longhorn-prod`, retained by Argo CD.
- Video transcoding: Intel Quick Sync through `gpu.intel.com/i915`.
- Machine learning: Intel OpenVINO through `gpu.intel.com/i915`.

The Intel device plugin exposes each physical GPU as four shared i915
allocations. The Immich server and machine-learning pods each request one
allocation. CPU remains available as a machine-learning fallback for models
that OpenVINO cannot run, but supported workloads prefer the Intel GPU.

## Verify hardware acceleration

Repeat these checks after the first deployment and after Immich, its Helm
chart, or the Intel GPU device plugin is upgraded. The commands inspect only
non-sensitive resource metadata, device visibility, and filtered logs.

Confirm that every node advertises i915 capacity and that both Immich
deployments request and limit one allocation:

```bash
kubectl get nodes \
  -o custom-columns='NAME:.metadata.name,I915_ALLOCATABLE:.status.allocatable.gpu\.intel\.com/i915,I915_CAPACITY:.status.capacity.gpu\.intel\.com/i915'

kubectl get deployments -n default immich-server immich-machine-learning \
  -o custom-columns='NAME:.metadata.name,I915_REQUEST:.spec.template.spec.containers[0].resources.requests.gpu\.intel\.com/i915,I915_LIMIT:.spec.template.spec.containers[0].resources.limits.gpu\.intel\.com/i915'
```

The expected node capacity is `4`, and both deployments should report a
request and limit of `1`. Verify that Kubernetes injected the render device
into both workloads:

```bash
kubectl exec -n default deployment/immich-server -- \
  ls -l /dev/dri/renderD128

kubectl exec -n default deployment/immich-machine-learning -- \
  ls -l /dev/dri/renderD128
```

To exercise video acceleration, transcode a video from the Immich admin jobs
page, then check for successful QSV use:

```bash
kubectl logs -n default deployment/immich-server --since=1h | \
  rg 'QSV-accelerated encoding and decoding'
```

To exercise machine-learning acceleration, run Smart Search, face detection,
or a text search, then confirm that OpenVINO was selected without GPU errors:

```bash
kubectl logs -n default deployment/immich-machine-learning --since=1h | \
  rg -i 'OpenVINOExecutionProvider|Available OpenVINO devices|GPU.*(error|failed|out of)'
```

Successful machine-learning logs include `OpenVINOExecutionProvider`. Treat a
missing render device, an absent i915 allocation, repeated worker restarts, or
GPU initialization/resource errors as an acceleration failure. Finish by
confirming the Argo CD application and pods are healthy:

```bash
kubectl get application -n argocd immich \
  -o custom-columns='NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status'

kubectl get pods -n default | rg '^immich-'
```

The Longhorn volume replicas are not a substitute for an independent backup.
Configure an off-cluster backup for the library and a PostgreSQL logical backup
after initial setup.

The NFS PV's 2 TiB capacity is Kubernetes binding metadata; it does not impose
a quota on the TrueNAS dataset.
