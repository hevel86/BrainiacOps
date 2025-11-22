# Cluster Deployment

This document outlines the steps to deploy the workloads in this repository.

## 1. Bootstrap Argo CD

The first step is to bootstrap Argo CD, which is the GitOps controller for the cluster.

### 1.1. Create Argo CD Namespace

```bash
kubectl apply -f kubernetes/bootstrap/argocd-namespace.yaml
```

### 1.2. Install Argo CD

This step installs the core Argo CD components.

```bash
kubectl apply -k kubernetes/bootstrap/argocd-install
```

<h2>2. Deploy Infrastructure (Skipping App-of-Apps for now)</h2>

For now, we will focus on deploying the core infrastructure components managed by Argo CD.
The deployment of user-facing applications (the "app of apps" pattern) will be deferred to a later stage.

<h3>2.1. Wait for Argo CD Pods to be Ready</h3>

Before proceeding, ensure all Argo CD pods are in a `Running` or `Completed` state.

```bash
kubectl get pods -n argocd
```

<h3>2.2. Deploy Infrastructure Applications</h3>

This will deploy the core infrastructure applications managed by Argo CD.

```bash
kubectl apply -f kubernetes/bootstrap/infrastructure-app.yaml
```
