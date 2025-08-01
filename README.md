# BrainiacOps

**Description:** Intelligent orchestration framework for the Rao Kubernetes cluster.  
**Tagline:** BrainiacOps – I don’t know what I’m doing (and this is why Krypton exploded).

## Contents

- `kubernetes/` – your Kubernetes YAML files go here

## Git Hooks

This repo uses a custom pre-commit Git hook with [TruffleHog](https://github.com/trufflesecurity/trufflehog) to scan for secrets before commits are finalized.