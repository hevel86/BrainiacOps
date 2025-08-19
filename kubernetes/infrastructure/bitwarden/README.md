# Bitwarden Secrets Manager Operator

This folder contains the Argo CD application to deploy the Bitwarden Secrets Manager Operator.

## Authentication Setup

The operator requires a Kubernetes secret named `bw-auth-token` to be present in any namespace where you intend to sync secrets. This secret contains the access token for your Bitwarden machine account.

### 1. Generate an Access Token

1.  Log in to the Bitwarden web vault and navigate to the **Secrets Manager** section.
2.  Go to **Machine accounts** and create or select an existing machine account.
3.  Generate a new **Access Token** and copy it.

### 2. Create the Kubernetes Secret

Run the following command to create the required secret. Replace `<YOUR_NAMESPACE>` with the target namespace (e.g., `default`) and `<TOKEN_HERE>` with the access token you just copied.

```bash
kubectl create secret generic bw-auth-token \
  -n <YOUR_NAMESPACE> \
  --from-literal=token="<TOKEN_HERE>"
```
Once you save and apply that change, the operator should be able to authenticate correctly and sync your secret.