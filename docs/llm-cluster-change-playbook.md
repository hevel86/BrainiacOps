# LLM Cluster Change Playbook (GitOps)

Use this file as the single source of truth when asking an LLM to make changes.
Paste the GitHub repo URL and say: "Reference docs/llm-cluster-change-playbook.md".

## Recipe (LLM-facing)

1) Read and follow `AGENTS.md` critical rules:
   - No secrets, passwords, API keys, or tokens in Git.
   - Use Bitwarden Secrets Operator references for sensitive values.
   - Talos secrets only in `talsecret.sops.yaml` (encrypted).

2) Refresh the LoadBalancer IP list before making changes:
   - Run: `scripts/update-ip-addresses.sh`
   - Confirm `docs/ip_addresses.md` shows:
     - MetalLB pool range
     - total/used/free count
     - sorted IPs (alphanumeric)

3) When adding a new app:
   - Create `kubernetes/apps/default/<app>/` with:
     - `app.yaml`
     - `kustomization.yaml`
     - manifests (Deployment/Service/Ingress/etc.)
   - Set Argo CD sync wave to `30`.
   - Use BitwardenSecret references for any credentials.

4) When adding infrastructure:
   - Create under `kubernetes/infrastructure/<name>/`.
   - Use sync wave `0` or `1` as appropriate.

5) Validate before final changes:
   - Prefer `kustomize build <path> | kubeconform -strict -`
   - Run `yamllint <path>/`

6) Update docs:
   - Ensure `docs/ip_addresses.md` is current (run the script again if services changed).
   - Add any new required documentation in `docs/`.

## Handoff prompt template (paste to LLM)

```
Let's add this to the cluster. Use the repo at <GITHUB_URL>.
Reference docs/llm-cluster-change-playbook.md and follow it exactly.
```
