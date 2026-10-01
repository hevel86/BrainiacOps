# Technitium third DNS node

This deployment is prepared for `dns3.torquasmvo.internal`, a secondary of
the existing Technitium cluster. It has not yet been joined or tested live.
The Argo CD application intentionally requires manual sync.

## Design

- One node, one retained `/etc/dns` PVC, and `Recreate` updates. Never scale
  this deployment above one replica: additional DNS nodes need independent
  identities, addresses, certificates, and storage.
- One MetalLB address, `10.0.0.246`, for UDP/TCP 53, HTTP 5380, and HTTPS
  53443. This address was unused in Kubernetes when prepared; recheck before
  deployment. It belongs to the existing infrastructure-owned MetalLB pool.
- `externalTrafficPolicy: Local` preserves client addresses. MetalLB must
  advertise from a node with a ready endpoint. Pod rescheduling and volume
  attachment cause an outage of this individual DNS node.
- DNS startup/readiness checks are independent of the admin web listener,
  primary availability, and upstream Internet connectivity. Readiness checks
  a local DNS answer; liveness checks the TCP listener conservatively.
  Neither proves cluster replication or upstream DNS health.
- Bootstrap uses the Talos host resolver (`dnsPolicy: Default`). Keep host
  DNS independent of dns3. Do not make dns3 the sole resolver for Talos,
  CoreDNS, or LAN clients. Existing external nodes provide continuity when
  Kubernetes or Longhorn is unavailable.
- No External-DNS hostname annotation: Technitium manages the node identity
  in its cluster zone. External-DNS continues targeting the existing primary.

## Before first sync

1. Confirm the versions on dns1 and dns2 under **About**. The candidate image
   is `15.5.1`; match the existing cluster's supported version before deploying.
   Coordinate upgrades across all three nodes; update secondaries before the
   primary. A Renovate change to this image still requires manual sync.
2. Provision `dns-system/bw-auth-token` using the existing
   [Bitwarden bootstrap procedure](../bitwarden/README.md). Verify that the
   historical password reference in `bitwarden-secrets.yaml` still exists
   and that the machine account can read it. Never put its value in Git.
3. Verify `10.0.0.246` is still free and reserved from other LAN allocations.
   Permit both directions between the existing DNS servers and this address:
   UDP/TCP 53 and TCP 53443. HTTP 5380 is for initial local administration.
   Pod outbound traffic may appear to peers as a Kubernetes node address;
   check actual source addresses if transfer ACLs reject it.
4. Inspect the existing cluster for stale entries from previous attempts.
   Do not reuse an identity that is still registered without resolving it.
   No retained Technitium PV/PVC or Longhorn volume was found during preparation.
   If one appears later, investigate it before creating a replacement.
5. Commit and push these manifests yourself, then explicitly sync
   `technitium-dns` in Argo CD. The parent discovers `app.yaml`; it must not
   be included in `kustomization.yaml`.

## Join once

Open `https://10.0.0.246:53443` and log in with the Bitwarden bootstrap
password. Verify the expected self-signed certificate locally.

Under **Administration > Cluster**, join the existing cluster as a secondary:

- Primary URL: `https://dns1.torquasmvo.internal:53443` (confirm its actual
  HTTPS port in the primary UI).
- Secondary/node IP: `10.0.0.246`, never the pod IP, ClusterIP, or a separate
  admin UI address.
- Authenticate using the primary's cluster administrator credentials in the
  UI. Do not store them in manifests or shell history. The bootstrap password
  is only for initialization; cluster authentication is synchronized on join.
- If the primary uses a self-signed certificate, verify that it is the
  expected primary before accepting the join-time certificate exception.

Joining copies cluster configuration and uses persisted identity and TLS
material. Do not automate rejoining on container startup. Leave service
listeners on container addresses, not bound to the MetalLB virtual IP.

Cluster communication uses HTTPS and DNS zone transfers. After joining,
certificate validation uses the cluster zone's TLSA records. Persistent TLS
errors can indicate a failed cluster-zone transfer; disabling validation at
join time does not fix ongoing replication.

## Acceptance before adding clients

```bash
kubectl -n dns-system rollout status deployment/technitium-dns
kubectl -n dns-system get pods,svc,pvc
dig @10.0.0.246 localhost A
dig @10.0.0.246 torquasmvo.internal SOA +norecurse
dig @10.0.0.246 torquasmvo.internal SOA +norecurse +tcp
dig @10.0.0.246 dns3.torquasmvo.internal A
dig @10.0.0.246 example.com A
```

Confirm in the primary UI that dns3 is connected and that cluster/catalog
zones, application zones, blocklists, and DNS apps are synchronized. Compare
SOA serials and representative answers against dns1 and dns2; check both UDP
and TCP. If optional DoH/DoT/DoQ listeners are synchronized and clients need
them, add the corresponding Service ports before advertising those protocols.

Before adding dns3 to DHCP, verify a planned restart and reschedule recover
the same node identity, configuration, volume, and LoadBalancer address. Use
a maintenance window and inspect events if volume attachment or MetalLB
advertisement stalls. Observe restart counts, DNS latency, and replication
for at least a day; initial readiness alone is insufficient acceptance.

## Removal and recovery

Remove dns3 from client resolver lists and the Technitium cluster before
decommissioning it. The PVC is retained on application deletion and pruning.
If a PVC is accidentally replaced, recover the retained volume before
starting the workload; an empty volume loses the node's identity and keys.
Retained storage contains credentials and certificates and must be protected.

## References

- [Technitium clustering](https://blog.technitium.com/2025/11/understanding-clustering-and-how-to.html)
- [Pinned container definition](https://github.com/TechnitiumSoftware/DnsServer/blob/v15.5.1/Dockerfile)
- [Official container configuration](https://github.com/TechnitiumSoftware/DnsServer/blob/v15.5.1/docker-compose.yml)
