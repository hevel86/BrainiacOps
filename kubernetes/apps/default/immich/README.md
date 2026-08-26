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

The Longhorn volume replicas are not a substitute for an independent backup.
Configure an off-cluster backup for the library and a PostgreSQL logical backup
after initial setup.

The NFS PV's 2 TiB capacity is Kubernetes binding metadata; it does not impose
a quota on the TrueNAS dataset.
