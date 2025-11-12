# Talos Kubernetes Cluster Configuration

This directory contains the configuration for the `talos-rao` Kubernetes cluster, managed using [talhelper](https://github.com/budimanjojo/talhelper) and [Talos Linux](https://www.talos.dev/).

## Overview

- **Cluster Name**: talos-rao
- **Kubernetes Version**: v1.34.1
- **Talos Version**: v1.11.3
- **Control Plane Endpoint**: https://10.0.0.34:6443
- **Node**: brainiac-00 (10.0.0.30) - Control Plane

## Prerequisites

### Required Tools

1. **talhelper** - Simplifies Talos configuration management
   ```bash
   brew install budimanjojo/tap/talhelper
   ```

2. **talosctl** - Talos CLI tool
   ```bash
   brew install siderolabs/tap/talosctl
   ```

3. **sops** - For managing encrypted secrets
   ```bash
   brew install sops
   ```

4. **age** - Encryption tool used with sops
   ```bash
   brew install age
   ```

5. **kubectl** - Kubernetes CLI tool
   ```bash
   brew install kubectl
   ```

### Age Key Setup

The cluster uses age encryption for secrets. Ensure your age private key is available at `~/.config/sops/age/keys.txt` that corresponds to the public key configured in `.sops.yaml`.

## Directory Structure

```
.
├── talconfig.yaml           # Main configuration file (source of truth)
├── talsecret.sops.yaml      # Encrypted secrets (cluster ID, tokens, certs)
├── .sops.yaml               # SOPS encryption configuration
├── machineconfig.yaml       # Generated machine config (do not edit)
└── README.md                # This file
```

## Configuration Files

### talconfig.yaml

This is your **source of truth** for cluster configuration. It defines:
- Cluster-wide settings (name, versions, networking)
- Node definitions (hostname, IP, role)
- Control plane configuration (system extensions, patches, volumes)

**Important**: Always edit this file for configuration changes, not the generated files.

### talsecret.sops.yaml

Contains encrypted sensitive data:
- Cluster ID and secret
- Bootstrap token
- Secrets bundle
- CA certificates

To view or edit secrets:
```bash
# View decrypted secrets
sops talsecret.sops.yaml

# Edit secrets (will decrypt, open editor, re-encrypt on save)
sops talsecret.sops.yaml
```

## Common Workflows

### 1. Generate Talos Configuration Files

After modifying `talconfig.yaml`, regenerate the machine configs:

```bash
# Generate all configuration files
talhelper genconfig

# This creates/updates:
# - controlplane.yaml
# - machineconfig.yaml
# - talosconfig (for talosctl)
```

### 2. Generate Installer Image URL with System Extensions

Your configuration includes system extensions (Intel drivers, NUT client, etc.). You need to generate the proper installer URL that includes these extensions:

```bash
# Generate the schematic and installer URL
talhelper genurl --config-file talconfig.yaml

# This will output:
# - The schematic ID
# - The full installer URL with extensions included
```

The generated URL will look like:
```
factory.talos.dev/installer/<schematic-id>:v1.11.3
```

**Important**: Use this generated URL (not the default `ghcr.io/siderolabs/installer`) when:
- Installing Talos for the first time
- Upgrading Talos versions
- The URL ensures all your system extensions are included in the image

You can also generate the URL and update your talconfig.yaml in one step:
```bash
# Generate URL and update config
talhelper genurl --config-file talconfig.yaml --patch

# Then regenerate configs
talhelper genconfig
```

### 3. Generate New Cluster Secrets

If setting up a new cluster or rotating secrets:

```bash
# Generate new secrets
talhelper gensecret > talsecret.sops.yaml

# Encrypt the secrets with age
sops -e -i talsecret.sops.yaml
```

### 4. Validate Configuration

Before applying changes, validate your configuration:

```bash
# Validate talconfig.yaml syntax
talhelper genconfig --validate

# Validate generated configs
talosctl validate --config controlplane.yaml --mode cloud
```

### 5. Apply Configuration to Nodes

#### Initial Bootstrap (First Time Setup)

```bash
# 1. Generate installer URL with system extensions (IMPORTANT!)
talhelper genurl --config-file talconfig.yaml
# Save the generated URL for use during installation

# 2. Generate configs
talhelper genconfig

# 3. Apply config to control plane node (insecure mode for initial setup)
# Note: Make sure to install Talos using the URL from step 1, not the default installer
talosctl apply-config --insecure \
  --nodes 10.0.0.30 \
  --file controlplane.yaml

# 4. Wait for node to be ready, then bootstrap the cluster
talosctl bootstrap --nodes 10.0.0.30 \
  --endpoints 10.0.0.30 \
  --talosconfig talosconfig

# 5. Retrieve kubeconfig
talosctl kubeconfig --nodes 10.0.0.30 \
  --endpoints 10.0.0.30 \
  --talosconfig talosconfig
```

#### Update Existing Node Configuration

```bash
# Generate updated configs
talhelper genconfig

# Apply to control plane (uses talosconfig for auth)
talosctl apply-config \
  --nodes 10.0.0.30 \
  --file controlplane.yaml \
  --talosconfig talosconfig
```

### 6. Upgrade Talos Version

```bash
# 1. Update versions in talconfig.yaml
vim talconfig.yaml
# Change talosVersion and kubernetesVersion

# 2. Generate new installer URL with extensions
talhelper genurl --config-file talconfig.yaml
# Note the generated URL (factory.talos.dev/installer/<schematic-id>:v1.11.3)

# 3. Regenerate configs
talhelper genconfig

# 4. Upgrade the node using the generated URL
talosctl upgrade \
  --nodes 10.0.0.30 \
  --image factory.talos.dev/installer/<schematic-id>:v1.11.3 \
  --talosconfig talosconfig

# 5. Wait for node to complete upgrade
talosctl health --talosconfig talosconfig

# 6. Verify Kubernetes version
kubectl get nodes
```

### 7. Upgrade Kubernetes Version

```bash
# 1. Update kubernetesVersion in talconfig.yaml
vim talconfig.yaml

# 2. Regenerate configs
talhelper genconfig

# 3. Apply updated config
talosctl apply-config \
  --nodes 10.0.0.30 \
  --file controlplane.yaml \
  --talosconfig talosconfig

# 4. Upgrade Kubernetes
talosctl upgrade-k8s \
  --nodes 10.0.0.30 \
  --to v1.34.1 \
  --talosconfig talosconfig
```

## Cluster-Specific Features

### System Extensions

The control plane includes Intel-specific hardware extensions:
- i915 GPU driver
- Intel ICE firmware
- Intel microcode updates
- iSCSI tools
- MEI driver
- NUT client (UPS monitoring)
- NVMe CLI tools
- Thunderbolt support
- Util-linux tools

### Storage Configuration

**Longhorn Volume**: Configured on `/dev/nvme0n1` with up to 2TB storage, mounted at `/var/mnt/longhorn`.

### UPS Integration

NUT client is configured to monitor UPS `ups1500@batterypi.torquasmvo.internal` for power management.

## Useful Commands

### Cluster Operations

```bash
# Get cluster health
talosctl health --talosconfig talosconfig

# Get node status
talosctl get members --talosconfig talosconfig

# View logs
talosctl logs --talosconfig talosconfig -n 10.0.0.30

# Access dashboard
talosctl dashboard --talosconfig talosconfig

# Get Kubernetes config
talosctl kubeconfig --talosconfig talosconfig
```

### Troubleshooting

```bash
# Check service status
talosctl services --talosconfig talosconfig -n 10.0.0.30

# Get detailed machine config
talosctl get machineconfig --talosconfig talosconfig -n 10.0.0.30

# Check disk usage
talosctl df --talosconfig talosconfig -n 10.0.0.30

# Interactive shell (for debugging)
talosctl shell --talosconfig talosconfig -n 10.0.0.30

# Reset a node (WARNING: destructive)
talosctl reset --nodes 10.0.0.30 --talosconfig talosconfig
```

## Best Practices

1. **Version Control**: Always commit changes to `talconfig.yaml` and encrypted `talsecret.sops.yaml`
2. **Never Edit Generated Files**: Only modify `talconfig.yaml`, then run `talhelper genconfig`
3. **Test Changes**: Validate configurations before applying them to production
4. **Backup Secrets**: Keep a secure backup of your age private key and `talsecret.sops.yaml`
5. **Document Changes**: Use git commit messages to document why configuration changes were made
6. **Use Dry-Run**: When possible, use `--dry-run` flags to preview changes

## Backup and Recovery

### Backup Important Files

```bash
# Backup configuration and secrets
tar -czf talos-backup-$(date +%Y%m%d).tar.gz \
  talconfig.yaml \
  talsecret.sops.yaml \
  .sops.yaml \
  talosconfig

# Backup age key
cp ~/.config/sops/age/keys.txt talos-age-key-backup.txt
```

### Generate Talosconfig from Secrets

If you lose your `talosconfig` but have the secrets:

```bash
# Decrypt secrets to get cluster info
sops -d talsecret.sops.yaml

# Regenerate configs
talhelper genconfig
```

## Additional Resources

- [Talos Documentation](https://www.talos.dev/)
- [talhelper Documentation](https://budimanjojo.github.io/talhelper/)
- [SOPS Documentation](https://github.com/getsops/sops)
- [Talos System Extensions](https://github.com/siderolabs/extensions)

## Support

For issues or questions:
- Talos: https://github.com/siderolabs/talos/issues
- talhelper: https://github.com/budimanjojo/talhelper/issues
