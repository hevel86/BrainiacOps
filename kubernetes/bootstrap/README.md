# Bootstrap workflow

1. `kubectl apply -f kubernetes/bootstrap/argocd-namespace.yaml`
2. `kubectl apply -k kubernetes/bootstrap/argocd-install`
3. Once Argo CD pods are ready, `kubectl apply -f kubernetes/bootstrap/infrastructure-app.yaml`
4. (Optional) `kubectl apply -f kubernetes/bootstrap/apps-app.yaml` and `kubectl apply -f kubernetes/bootstrap/apps-external-app.yaml`

The `argocd-install` overlay vendors the upstream Argo CD `install.yaml` so the whole bootstrap flow stays in Git.
