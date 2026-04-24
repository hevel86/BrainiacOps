# Tailscale Integration

This folder owns the base namespace and secrets used by the Tailscale Kubernetes
Operator.

## Current Layout

- `namespace.yaml`
  Creates the dedicated `tailscale` namespace.
- `operator-bitwarden-secrets.yaml`
  Materializes `Secret/tailscale/operator-oauth` from Bitwarden.
- `bitwarden-secrets.yaml`
  Preserves the older sidecar auth secret pattern where still needed.

Related infrastructure apps live nearby:

- [tailscale-operator](/home/michael/gitstuff/BrainiacOps/kubernetes/infrastructure/tailscale-operator/)
  Installs the operator itself.
- [tailscale-dns](/home/michael/gitstuff/BrainiacOps/kubernetes/infrastructure/tailscale-dns/)
  Adds cluster DNS support for `*.ts.net` via `DNSConfig` and a CoreDNS stub.
- [tailscale-egress](/home/michael/gitstuff/BrainiacOps/kubernetes/infrastructure/tailscale-egress/)
  Owns shared `ExternalName` services for reusable tailnet egress targets.

## Operator Credentials

The operator does not use a single reusable auth key. It expects a Kubernetes
secret named `operator-oauth` in the `tailscale` namespace with:

- `client_id`
- `client_secret`

That secret is created by
[operator-bitwarden-secrets.yaml](/home/michael/gitstuff/BrainiacOps/kubernetes/infrastructure/tailscale/operator-bitwarden-secrets.yaml)
from two separate Bitwarden items.

## OAuth Client Guidance

Create a dedicated OAuth client in the Tailscale admin console for the operator.
Use the raw client ID and client secret, not a generated `tskey-client-...`
string.

Recommended scopes:

- `Devices: Read & Write`
- `Keys: Read & Write`

Recommended tags:

- `tag:k8s-operator` for the operator itself
- `tag:k8s` for operator-created proxies

Those tags must also exist in the tailnet policy.

## Operator-First Pattern

This repo now treats the Kubernetes operator as the default integration path.

Use operator ingress when:

- a tailnet client needs to reach a Kubernetes `Service`

Use shared operator egress when:

- a Kubernetes workload needs to reach a tailnet host
- more than one app may need the same host

Do not create duplicate app-local egress services for the same tailnet host. Put
shared targets in
[kubernetes/infrastructure/tailscale-egress/](/home/michael/gitstuff/BrainiacOps/kubernetes/infrastructure/tailscale-egress/)
instead.

## Sidecar Status

Per-app Tailscale sidecars are no longer the preferred pattern in this repo.
Keep them only where the operator cannot yet replace the exact behavior you need.
