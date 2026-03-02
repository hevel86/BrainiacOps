# Testing ntfy Alertmanager Notifications

To verify that Prometheus alerts are correctly reaching your `ntfy` server via the `alertmanager-ntfy` bridge.

## Architecture
`Alertmanager` -> `alertmanager-ntfy` (internal bridge) -> `ntfy.botty-mcbotface.com`

## Prerequisites
- Ensure your cluster has synced both `kube-prometheus-stack` and `alertmanager-ntfy` from Argo CD.
- You must have network access to the Alertmanager service at `10.0.0.231`.

## 1. Trigger a Synthetic Alert
Run the following `curl` command to post a test alert to the Alertmanager API:

```bash
curl -H "Content-Type: application/json" -d '[
  {
    "labels": {
      "alertname": "NtfyBridgeTest",
      "severity": "critical",
      "instance": "manual-test"
    },
    "annotations": {
      "summary": "This test verifies the ntfy-bridge (alertmanager-ntfy) formatting and delivery."
    }
  }
]' http://10.0.0.231:9093/api/v2/alerts
```

## 2. Verify Delivery
- **Alertmanager UI**: Visit `http://alertmanager.torquasmvo.internal` to see the active alert.
- **ntfy**: Check your topic at `https://ntfy.botty-mcbotface.com/prometheus`. The bridge will format the alert with tags and priority based on severity.

## 3. Troubleshooting
If the notification does not arrive:

### Check the Bridge Logs
The `alertmanager-ntfy` bridge will log any errors it encounters when forwarding to ntfy:
```bash
kubectl logs -n monitoring -l app=alertmanager-ntfy
```

### Check Alertmanager Logs
Verify that Alertmanager is successfully sending the webhook to the bridge:
```bash
kubectl logs -n monitoring -l app.kubernetes.io/name=alertmanager -c alertmanager
```

Common issues:
- **ntfy-token missing**: Ensure the secret is correctly injected into the `monitoring` namespace.
- **Bridge URL**: Alertmanager must be able to resolve `http://alertmanager-ntfy.monitoring.svc.cluster.local:8080/`.
