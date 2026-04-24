# Tailscale Kubernetes Operator

This app installs the Tailscale Kubernetes Operator into the `tailscale`
namespace using the official Helm chart.

## Dependencies

This app assumes the following infrastructure is already present:

- [tailscale base app](/home/michael/gitstuff/BrainiacOps/kubernetes/infrastructure/tailscale/app.yaml)
  for the namespace and Bitwarden-backed OAuth secret
- [tailscale-dns](/home/michael/gitstuff/BrainiacOps/kubernetes/infrastructure/tailscale-dns/app.yaml)
  when cluster workloads need to resolve `*.ts.net`
- [tailscale-egress](/home/michael/gitstuff/BrainiacOps/kubernetes/infrastructure/tailscale-egress/app.yaml)
  when shared tailnet targets should be reachable from multiple apps

## Credentials

The chart relies on a pre-created Kubernetes secret named `operator-oauth` in
the `tailscale` namespace. In this repo that secret is materialized from
Bitwarden by:

- [tailscale app](/home/michael/gitstuff/BrainiacOps/kubernetes/infrastructure/tailscale/app.yaml)
- [operator-bitwarden-secrets.yaml](/home/michael/gitstuff/BrainiacOps/kubernetes/infrastructure/tailscale/operator-bitwarden-secrets.yaml)

The secret must contain:

- `client_id`
- `client_secret`

If `operator-oauth` is missing, the operator will not start correctly.

## What The Operator Owns

The operator is used for two distinct patterns in this repo:

1. Ingress

Expose a Kubernetes `Service` to the tailnet by annotating that `Service` with:

- `tailscale.com/expose: "true"`
- `tailscale.com/hostname: <name>`

2. Egress

Reach a tailnet host from cluster workloads by creating an `ExternalName`
`Service` annotated with:

- `tailscale.com/tailnet-fqdn: <magicdns-name>`

Operator-managed egress services rewrite `spec.externalName` to a generated
proxy service in the `tailscale` namespace. If Git owns those `ExternalName`
services, the owning Argo CD `Application` must ignore `/spec/externalName` and
enable `RespectIgnoreDifferences=true`.

## Ownership Rules

- App-local ingress annotations belong with the app `Service`.
- Shared egress targets belong in
  [kubernetes/infrastructure/tailscale-egress/](/home/michael/gitstuff/BrainiacOps/kubernetes/infrastructure/tailscale-egress/),
  not in app directories.
- Do not allow multiple Argo CD apps to own the same egress `Service`.
