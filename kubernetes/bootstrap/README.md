# Bootstrap workflow

1. `kubectl apply -f kubernetes/bootstrap/argocd-namespace.yaml`
2. `kubectl apply --server-side -k kubernetes/bootstrap/argocd-install`
3. Once Argo CD pods are ready, `kubectl apply -f kubernetes/bootstrap/infrastructure-app.yaml`
4. (Optional) `kubectl apply -f kubernetes/bootstrap/apps-app.yaml`, `kubectl apply -f kubernetes/bootstrap/apps-external-app.yaml`, and `kubectl apply -f kubernetes/bootstrap/games-app.yaml`

**Note**: Step 2 requires the `--server-side` flag because the `ApplicationSets` CRD is too large for a standard client-side apply (it exceeds the 256KB annotation limit). If you are migrating from client-side apply, you may also need to add `--force-conflicts`.

The `argocd-install` overlay vendors the upstream Argo CD `install.yaml` so the whole bootstrap flow stays in Git.
