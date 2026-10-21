# Gitea tailnet access

The desired configuration keeps the existing client addresses:

| Access | Address | Tailnet device |
| --- | --- | --- |
| Web, HTTPS Git, LFS and packages | `https://gitea.torquasmvo.com` | `gitea.tailca892.ts.net` |
| Git SSH | `gitea-ssh.torquasmvo.com:2222` | `gitea-ssh.tailca892.ts.net` |

Both names must resolve to their respective tailnet endpoints. Keep the existing
Gitea ROOT_URL, SSH_DOMAIN and SSH_PORT settings. Existing clone URLs continue to
work from authorized Tailscale clients after DNS is updated.

## Network path

HTTPS flows through the operator-managed `gitea` proxy to the
`gitea-web-tailnet` ClusterIP Service in `kube-system`, then Traefik's dedicated
`gitea-tailnet` listener on port 8444. Only that listener serves the Gitea host
rule. Port 8444 is deliberately excluded from Traefik's public MetalLB Service.
Traefik continues using the existing `traefik-dashboard-tls` wildcard certificate;
cert-manager renews it using DNS-01, which does not require public Gitea access.

SSH flows through the operator-managed `gitea-ssh` proxy to the
`gitea-ssh-tailnet` ClusterIP Service on port 2222, then Gitea's existing embedded
SSH server on port 2222. This is ordinary Git SSH over Tailscale, not Tailscale SSH.
Repository permissions and registered SSH keys still apply.

The backend `gitea` Service is ClusterIP-only. It has no MetalLB address or
NodePorts. These changes restrict external access paths; they do not add
isolation from other pods or administrators inside the Kubernetes cluster.

The HTTPS Service selects the existing Traefik release labels. Recheck that
selector if the Traefik release name or namespace changes. Its listener belongs
to the infrastructure `traefik` app; the Gitea app owns the two app-specific
Tailscale Services and the Gitea route. No resource has two Argo CD owners.

## Cutover

The configuration is not effective until committed, pushed and synced. Gitea
has automated sync disabled; Traefik has automated sync enabled.

1. Commit and push the desired configuration manually. Sync Traefik first if
   needed, and wait for its rollout:

   ```bash
   argocd app sync traefik
   kubectl rollout status -n kube-system deployment/traefik
   argocd app sync gitea
   ```

2. Wait for both Tailscale proxies to become Ready and confirm their DNS names
   in the Tailscale admin console. Tailnet grants/ACLs control which identities
   and devices can connect. Limit access to the intended users on HTTPS 443 and
   SSH 2222; the operator's shared default proxy tag alone is not a per-app rule.
   Do not enable Funnel for either endpoint.

3. Replace the public DNS records with **DNS-only** A records (disable Cloudflare
   proxying), using each proxy's assigned Tailscale IPv4 address from the admin
   console. Remove old public A/AAAA records and conflicting CNAMEs:

   ```text
   gitea.torquasmvo.com      A <Tailscale IPv4 of the gitea proxy>
   gitea-ssh.torquasmvo.com  A <Tailscale IPv4 of the gitea-ssh proxy>
   ```

   Update any split-DNS overrides in Technitium to the same addresses. Update
   these records if a proxy is deleted and recreated with a different tailnet
   address. Prefer direct A records over CNAMEs to MagicDNS names because some
   Windows and Android resolvers cannot follow those aliases reliably.
   Public DNS
   names can point at private tailnet endpoints without making them reachable
   from the internet. Resolvers with DNS rebinding protection may need an
   exception for these names. This repository's ExternalDNS only manages
   `torquasmvo.internal`, so it will not make these `.com` changes.

4. Remove the router's former Gitea SSH port-forward (the application advertises
   external port 2222), and any direct forwards for Gitea web access. Check IPv6
   firewall rules too. Keep shared Traefik 443 forwarding if other public apps
   use it; Gitea no longer has a route on that listener. Do not reuse the old
   `10.0.0.238` address until the stale forwarding rules have been removed.

5. Remove stale `gitea.torquasmvo.internal` DNS records pointing at the old
   MetalLB address. ExternalDNS uses upsert-only and will not delete them simply
   because the Service annotation was removed.

Plan a maintenance window: Gitea's public path is removed during sync, and DNS
caches may continue using the old destination until their TTL expires. Remote
Actions runners, mirrors, integrations and clients that need inbound access now
need a working tailnet path. Outbound webhooks are not inherently blocked by
this change. No repository data, secrets or storage manifests are changed.

## Verification

After sync, verify:

```bash
kubectl get svc -n default gitea gitea-ssh-tailnet
kubectl get svc -n kube-system traefik gitea-web-tailnet
kubectl get ingressroute -n kube-system gitea -o jsonpath='{.spec.entryPoints}'
kubectl get pods -n tailscale
```

The route should list only `gitea-tailnet`. The public Traefik Service must not
list port 8444. All three Gitea-related Services must be ClusterIP, with no
external IP or NodePort.

From an authorized Tailscale client, verify HTTPS with normal certificate
validation, sign in, then perform a read-only Git fetch using the existing SSH
URL. `ssh -T -p 2222 git@gitea-ssh.torquasmvo.com` should return Gitea's
authentication greeting for a registered key. Stored SSH host keys are unchanged.

From a device outside the tailnet, verify HTTPS and SSH do not reach Gitea. Also
test the original public Traefik destination with the Gitea hostname/SNI to prove
the old ingress is closed independently of DNS. A generic Traefik 404 is expected;
Gitea's login page or repository content is not. Verify any former router-forward
destination directly as well. DNS changes alone do not prove public access is
closed.

References: [Tailscale operator ingress](https://tailscale.com/docs/kubernetes-operator/ingress),
[Traefik entrypoints](https://doc.traefik.io/traefik/reference/install-configuration/entrypoints/),
[Tailscale Windows CNAME resolution issue](https://github.com/tailscale/tailscale/issues/19122).
