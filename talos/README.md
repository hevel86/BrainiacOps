# Talos Node Management

This document outlines the steps for managing the Talos nodes in this cluster, including adding a new node and performing upgrades.

## Adding a New Node

To prevent quorum loss when upgrading control plane nodes, it may be necessary to add a new control plane node to the cluster.

### 1. Prepare the Machine Configuration

Ensure you have a machine configuration file for the new node. In this example, we are adding `brainiac-02` (10.0.0.36) as a new control plane node. The configuration file is `talos/clusterconfig/talos-rao-brainiac-02.yaml`.

### 2. Apply the Configuration

Boot the new node with the Talos installer image. Then, apply the machine configuration using `talosctl`. For a new install, you may need to use the `--insecure` flag if the cluster's certificate authority is not yet trusted by the new node.

```bash
talosctl apply-config --insecure --nodes 10.0.0.36 --file talos/clusterconfig/talos-rao-brainiac-02.yaml
```

Wait for the node to join the cluster and for the cluster to become healthy.

## Upgrading a Node

Once the cluster is stable and has quorum, you can proceed with upgrading a node.

### 1. Run the Upgrade Command

Use the `talosctl upgrade` command, specifying the node to upgrade and the target installer image.

```bash
talosctl upgrade --nodes <NODE_IP> --image factory.talos.dev/metal-installer/284a1fe978ff4e6221a0e95fc1d01278bab28729adcb54bb53f7b0d3f2951dcc:v1.11.5
```

Replace `<NODE_IP>` with the IP address of the node you are upgrading (e.g., `10.0.0.35` for `brainiac-01`).

**Note:** If you are upgrading a node with certificate issues, you may need to use the `--insecure` flag.
