# Testing ntfy Alertmanager Notifications

To verify that Prometheus alerts are correctly reaching your `ntfy` server, you can manually trigger a synthetic alert.

## Prerequisites
- Ensure your cluster has synced the latest changes from Argo CD.
- You must have network access to the Alertmanager service at `10.0.0.231`.

## 1. Trigger a Synthetic Alert
Run the following `curl` command to post a test alert to the Alertmanager API:

```bash
curl -H "Content-Type: application/json" -d '[
  {
    "labels": {
      "alertname": "NtfyTestAlert",
      "severity": "critical",
      "instance": "manual-test"
    },
    "annotations": {
      "summary": "This is a manual test alert to verify the ntfy receiver configuration."
    }
  }
]' http://10.0.0.231:9093/api/v2/alerts
```

## 2. Verify Delivery
- **Alertmanager UI**: Visit `http://alertmanager.torquasmvo.internal` (or `http://10.0.0.231:9093`) to see the active alert.
- **ntfy**: Check your topic at `https://ntfy.botty-mcbotface.com/prometheus`. Due to the `group_wait: 30s` setting in your configuration, the notification should arrive within about 30-45 seconds.

## 3. Troubleshooting
If the notification does not arrive, check the Alertmanager logs for authentication or connection errors:

```bash
kubectl logs -n monitoring -l app.kubernetes.io/name=alertmanager -c alertmanager
```

Common issues include:
- **Invalid Token**: Ensure the token in Bitwarden is correct and the `ntfy-token` secret is correctly injected.
- **Network Access**: Ensure the Alertmanager pods can reach the external `ntfy.botty-mcbotface.com` URL.
