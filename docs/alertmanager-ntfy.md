# alertmanager-ntfy Integration

`alertmanager-ntfy` is a webhook bridge that receives alert payloads from Prometheus Alertmanager and forwards them as push notifications to an [ntfy](https://ntfy.sh) server.

## Architecture

```
Prometheus → Alertmanager → alertmanager-ntfy → ntfy server → mobile/desktop push
```

1. **Prometheus** scrapes metrics and evaluates alerting rules.
2. **Alertmanager** (part of `kube-prometheus-stack`) groups and routes firing alerts. Its config defines a single `ntfy` receiver that POSTs all `critical|warning` alerts to this service via webhook.
3. **alertmanager-ntfy** receives those webhook payloads, applies Go templates to format titles and descriptions, authenticates against ntfy using a bearer token, and publishes to the `prometheus` topic.
4. **ntfy** (`https://ntfy.botty-mcbotface.com`) delivers the notification to subscribed clients.

## Relevant Files

| File | Purpose |
|------|---------|
| `kubernetes/infrastructure/monitoring/alertmanager-ntfy/app.yaml` | Argo CD Application (sync wave 50) |
| `kubernetes/infrastructure/monitoring/alertmanager-ntfy/deployment.yaml` | Deployment with initContainer for token injection |
| `kubernetes/infrastructure/monitoring/alertmanager-ntfy/service.yaml` | ClusterIP Service (port 8080 → container 8000) |
| `kubernetes/infrastructure/monitoring/alertmanager-ntfy/configmap.yaml` | ntfy base URL, topic, and notification templates |
| `kubernetes/infrastructure/monitoring/kube-prometheus-stack/app.yaml` | Alertmanager webhook route and ntfy.tmpl template |
| `kubernetes/infrastructure/monitoring/kube-prometheus-stack/secrets/bitwarden-secrets.yaml` | `BitwardenSecret` that creates the `ntfy-token` Kubernetes Secret |

## Component Relationship

`kube-prometheus-stack` and `alertmanager-ntfy` are separate Argo CD Applications that share two coupling points: a Secret and a webhook URL. Neither has a hard Kubernetes dependency on the other — they are loosely coupled by convention.

### What each component owns

**`kube-prometheus-stack`** (Helm chart, managed by Argo CD):
- Prometheus — scrapes metrics and evaluates alerting rules
- Alertmanager — groups, deduplicates, and routes alerts; holds the webhook receiver config pointing at `alertmanager-ntfy`
- Grafana — dashboards and visualisation
- The `ntfy.tmpl` Go template — defines how Alertmanager formats the grouped alert body it sends in the webhook POST
- The `BitwardenSecret` resource (`kube-prometheus-stack/secrets/bitwarden-secrets.yaml`) — instructs the Bitwarden Secrets Operator to provision the `ntfy-token` Kubernetes Secret into the `monitoring` namespace

**`alertmanager-ntfy`** (plain manifests, managed by Argo CD):
- The bridge Deployment and Service — listens on `:8000/hook` for webhook POSTs from Alertmanager
- The ConfigMap — holds the ntfy server URL, topic name, and per-notification Go templates (title/description)
- The initContainer pattern — reads `ntfy-token` at pod startup and renders it into a config file so the token is never in the ConfigMap or environment

### Shared resources

| Resource | Produced by | Consumed by |
|----------|-------------|-------------|
| `ntfy-token` Kubernetes Secret | `kube-prometheus-stack-secrets` (Bitwarden Operator) | `alertmanager-ntfy` Deployment initContainer |

The `monitoring` namespace is shared; both components deploy into it. There are no Kubernetes `ownerReference` or cross-namespace bindings between them.

### Coupling points

1. **Webhook URL** — Alertmanager's receiver config in `kube-prometheus-stack/app.yaml` hardcodes the in-cluster DNS address of the `alertmanager-ntfy` Service:
   ```
   http://alertmanager-ntfy.monitoring.svc.cluster.local:8080/hook
   ```
   If the Service name, namespace, or port changes in `alertmanager-ntfy/service.yaml`, the webhook URL in `kube-prometheus-stack/app.yaml` must be updated to match.

2. **`ntfy-token` Secret name** — The `BitwardenSecret` in `kube-prometheus-stack/secrets/bitwarden-secrets.yaml` creates a Secret named `ntfy-token`. The `alertmanager-ntfy` Deployment mounts a volume referencing that exact name. Both must agree on this name.

3. **Alert annotation schema** — Both components consume the same Prometheus alert annotations:
   - `ntfy.tmpl` (in `kube-prometheus-stack`) uses `.Annotations.summary`, `.Annotations.description`, `.Labels.severity`
   - `alertmanager-ntfy` ConfigMap templates use `.Annotations.summary` and `.Annotations.description`

   Alert rules must populate these annotations or notifications will render with empty fields.

### What happens if one component is missing

| Missing component | Effect |
|-------------------|--------|
| `alertmanager-ntfy` not deployed | Alertmanager logs webhook delivery errors; alerts still fire and are visible in the Alertmanager UI, but no push notifications are sent |
| `kube-prometheus-stack` not deployed | `alertmanager-ntfy` runs but receives no traffic; it is idle and harmless |
| `ntfy-token` Secret not created | `alertmanager-ntfy` pod stuck in `Init:Error`; Alertmanager webhook calls return errors |

---

## Alertmanager Routing Config

Defined inline in `kube-prometheus-stack/app.yaml` under `alertmanager.config`:

```yaml
route:
  group_by: ["alertname", "job"]
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 12h
  receiver: "ntfy"
  routes:
    - receiver: "ntfy"
      matchers:
        - severity =~ "critical|warning"

receivers:
  - name: "ntfy"
    webhook_configs:
      - url: http://alertmanager-ntfy.monitoring.svc.cluster.local:8080/hook
        send_resolved: true
```

The webhook URL uses in-cluster DNS: Service port 8080 → container port 8000 → `/hook` endpoint.

## Notification Format

Alertmanager defines an `ntfy.tmpl` template (in `kube-prometheus-stack/app.yaml`) for grouped alert display:

```
🔥 Firing (N) / ✅ Resolved (N)
---
Summary: <.Annotations.summary>
Description: <.Annotations.description>
Severity: <.Labels.severity>
```

The `alertmanager-ntfy` ConfigMap applies its own per-alert Go templates for the ntfy push notification:

| Field       | Template |
|-------------|----------|
| Title       | `[Resolved: ]<.Annotations.summary>` |
| Description | `<.Annotations.description>` |

## Secret Handling

The ntfy bearer token is **never stored in Git**. The flow is:

1. `BitwardenSecret` resource (`kube-prometheus-stack/secrets/bitwarden-secrets.yaml`) instructs the Bitwarden Secrets Operator to create a Kubernetes Secret named `ntfy-token` in the `monitoring` namespace.
2. The Deployment's `initContainer` (`busybox`) reads the token from the mounted Secret and renders it into `auth.yml` on a shared `emptyDir` volume:
   ```yaml
   ntfy:
     auth:
       token: "<value from secret>"
   ```
3. The main `alertmanager-ntfy` container loads both `config.yml` (from ConfigMap) and `auth.yml` (from emptyDir) via `--configs` flags, keeping the token out of the ConfigMap and out of any image environment variable.

## Sync Wave Order

| Argo CD Application             | Wave | Purpose |
|---------------------------------|------|---------|
| `kube-prometheus-stack-secrets` | 40   | Creates `ntfy-token` and `grafana-admin` Secrets via Bitwarden Operator |
| `kube-prometheus-stack`         | 50   | Deploys Prometheus, Alertmanager (with ntfy webhook config), and Grafana |
| `alertmanager-ntfy`             | 50   | Deploys the ntfy bridge |

The secrets application at wave 40 ensures `ntfy-token` exists before the `alertmanager-ntfy` initContainer tries to read from it.

## Resource Summary

| Resource   | Details |
|------------|---------|
| Deployment | 1 replica, UID 65534 (nobody), all capabilities dropped, seccomp RuntimeDefault |
| Service    | ClusterIP, port 8080 → container 8000 |
| ConfigMap  | `alertmanager-ntfy-config` — ntfy base URL, topic, and notification templates |
| Secret     | `ntfy-token` — injected by Bitwarden Secrets Operator (not in Git) |
| Image      | `ghcr.io/alexbakker/alertmanager-ntfy:1.1.0` |
| Memory     | 32Mi request / 64Mi limit |
| CPU        | 10m request / 100m limit |

---

## Testing

### Prerequisites

- Both `kube-prometheus-stack` and `alertmanager-ntfy` are synced in Argo CD.
- The Alertmanager receiver webhook points to `http://alertmanager-ntfy.monitoring.svc.cluster.local:8080/hook`.

### Trigger a Synthetic Alert

#### Method A: Direct to Alertmanager LoadBalancer

```bash
curl -H "Content-Type: application/json" -d '[
  {
    "labels": {
      "alertname": "NtfyBridgeTest",
      "severity": "critical",
      "instance": "manual-test"
    },
    "annotations": {
      "summary": "Test alert",
      "description": "Validating Alertmanager -> alertmanager-ntfy -> ntfy delivery"
    }
  }
]' http://10.0.0.231:9093/api/v2/alerts
```

#### Method B: Port-forward (when LB is not reachable)

```bash
kubectl -n monitoring port-forward svc/kube-prometheus-stack-alertmanager 19093:9093
```

In another terminal:

```bash
curl -H "Content-Type: application/json" -d '[
  {
    "labels": {
      "alertname": "NtfyBridgeTest",
      "severity": "critical",
      "instance": "manual-test"
    },
    "annotations": {
      "summary": "Test alert",
      "description": "Validating Alertmanager -> alertmanager-ntfy -> ntfy delivery"
    }
  }
]' http://127.0.0.1:19093/api/v2/alerts
```

### Verify Delivery

- **Alertmanager UI**: `http://alertmanager.torquasmvo.internal` — confirm the alert is active.
- **ntfy topic**: `https://ntfy.botty-mcbotface.com/prometheus` — confirm the push notification arrived.

---

## Troubleshooting

### Check the Bridge Logs

```bash
kubectl logs -n monitoring -l app=alertmanager-ntfy
```

Expected success lines:
- `Handling webhook`
- `Successfully forwarded alert to ntfy`
- `"/hook" ... "status": 200`

### Check Alertmanager Logs

```bash
kubectl logs -n monitoring -l app.kubernetes.io/name=alertmanager -c alertmanager
```

### Common Issues

| Symptom | Cause | Fix |
|---------|-------|-----|
| Bridge pod in `Init:Error` or `Init:CrashLoopBackOff` | `ntfy-token` Secret missing | Verify Bitwarden Operator synced the Secret: `kubectl get secret ntfy-token -n monitoring` |
| 500 errors from bridge | Wrong template field names in ConfigMap | Ensure ConfigMap uses `ntfy.notification.templates.title` and `ntfy.notification.templates.description` (not `notification.title` / `notification.message`) |
| Alerts visible in Alertmanager UI but no ntfy push | Webhook URL wrong | Must be `http://alertmanager-ntfy.monitoring.svc.cluster.local:8080/hook` (note `/hook` path) |
| Notifications arrive but show no description | Alert rule missing `description` annotation | Add `annotations.description` to the PrometheusRule |
