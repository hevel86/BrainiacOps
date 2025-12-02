# Pi-hole DNS Status (2025-11-26)

## Current state
- Service `pihole-service` is `LoadBalancer` with VIP `10.0.0.213`.
- `externalTrafficPolicy: Cluster` (preserves availability, source IPs are SNAT to cluster IPs).
- Pod `pihole-55f4599b8c-289zc` running on `brainiac-01`, endpoint `10.244.1.99`.
- PVC `pihole-pvc` (2Gi, `longhorn-prod`, RWO) mounted at `/etc/pihole`.
- Queries resolve from LAN: `Test-NetConnection 10.0.0.213 -Port 53` succeeds; `Resolve-DnsName example.com -Server 10.0.0.213` works.
- Pi-hole logging works: `/var/log/pihole/pihole.log` shows queries; however client IPs appear as `10.244.1.1` due to SNAT.
- pihole-FTL DB currently has 0 rows; logging is enabled (`queryLogging = true`).

## Options to preserve real client IPs
1) Keep current (Cluster): simplest, stable, but client IPs are SNAT’d.
2) Switch to `externalTrafficPolicy: Local` **and** run one pod per node (3 replicas) so MetalLB always has a local endpoint:
   - Storage changes needed because current PVC is RWO:
     - Option A: move to RWX storage (e.g., Longhorn RWX) and share one RWX PVC across replicas.
     - Option B: convert to StatefulSet with one RWO PVC per pod (per-node data); ensure any config/state that must be shared is replicated appropriately.
   - Add topology spread or anti-affinity to land pods on distinct nodes.

## Next steps (choose one)
- If keeping Cluster: no manifest changes needed; accept SNAT’d client IPs.
- If preserving client IPs:
  - Decide on storage approach (RWX vs per-pod PVC).
  - Update Service back to `externalTrafficPolicy: Local`.
  - Scale Deployment/convert to StatefulSet to 3 replicas with per-node placement and storage changes above.

## Useful commands
- Tail queries: `kubectl -n default exec deploy/pihole -- tail -n 20 /var/log/pihole/pihole.log`
- Check Service: `kubectl -n default describe svc pihole-service`
- Pod status: `kubectl -n default get pods -l app=pihole -o wide`
- PVC: `kubectl -n default describe pvc pihole-pvc`
