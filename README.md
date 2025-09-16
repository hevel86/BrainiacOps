# BrainiacOps

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Renovate](https://img.shields.io/badge/renovate-enabled-brightgreen.svg)](https://renovatebot.com)

Tagline: "BrainiacOps - I don't know what I'm doing (and this is why Krypton exploded)."

---

## Highlights

- Robust CI: Schema validation on every push/PR.
- Safer commits: pre-commit TruffleHog scan blocks secrets before they land.
- Argo CD bootstrap: declarative app-of-apps layout for infra and apps.
- Clear separation: infrastructure, apps, games, storage, and testing trees.
- Automated updates: Renovate configuration for dependency management.

## Repository Structure

- `kubernetes/` - all cluster manifests (apps, infra, storage, testing).
  - `kubernetes/bootstrap/` - Argo CD, initial app-of-apps wiring.
  - `kubernetes/infrastructure/` - platform services (e.g., tailscale, bitwarden, renovate).
  - `kubernetes/apps/` - workload apps (media stack, tools, etc.).
  - `kubernetes/games/` - game servers (e.g., minecraft).
  - `kubernetes/storage/` - storage classes, PVCs (e.g., Longhorn bindings).
  - `kubernetes/testing/` - validation and test fixtures.

## Getting Started

Prerequisites

- Git and Docker (for the pre-commit hook container scan).
- Optional: `kubeconform` binary for local schema checks.

Setup

1) Enable repo-provided Git hooks so secret scans run automatically:

```
git config core.hooksPath .githooks
```

2) Optionally run checks locally before pushing:

```
# Validate manifests (ignore missing schemas like CRDs)
kubeconform -strict -ignore-missing-schemas $(git ls-files 'kubernetes/**/*.yaml')
```

Notes

- The pre-commit hook uses Docker to run TruffleHog against staged YAML/ENV/JSON files.
- You can temporarily bypass the hook by setting `SKIP_TRUFFLEHOG=1` in your environment.

## CI Workflows

- `Kubeconform` - Validates changed Kubernetes manifests with `kubeconform`.

See the workflow files in `.github/workflows/` for exact behavior.

## Contributing

- Keep manifests minimal, declarative, and schema-valid.
- Prefer kustomize overlays and DRY patterns over duplication.
- Include README snippets in new app/infra folders where useful.

## License

MIT - see `LICENSE`.

