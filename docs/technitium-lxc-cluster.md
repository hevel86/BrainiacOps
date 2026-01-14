# Technitium DNS LXC Cluster Guide

**Status**: Operational
**Deployment Date**: 2026-01-14
**Type**: High-Availability Proxmox LXC Cluster (Primary/Secondary)

## Executive Summary

This cluster replaces legacy Pi-hole instances with a Kubernetes-native compatible DNS solution running in Proxmox LXCs. It features automated record migration, Quad9 upstream protection, and conditional forwarding for local hostname resolution across VLANs.

## Infrastructure

| Role | IP Address | Hostname | OS / Platform | Notes |
|------|------------|----------|---------------|-------|
| **Primary** | `192.168.1.7` | `dns1.torquasmvo.internal` | Proxmox LXC | Cluster Controller |
| **Secondary** | `192.168.1.8` | `dns2.torquasmvo.internal` | Proxmox LXC | Real-time Replication |
| **Gateway** | `192.168.1.1` | `udm-pro` | UDM Pro | DHCP & Reverse DNS Target |

## Configuration Details

### 1. Cluster Settings
- **Domain**: `torquasmvo.internal`
- **Sync Status**: Active. Blocklists, Settings, and Primary Zones replicate automatically from Primary to Secondary.
- **API Token**: Stored in Bitwarden. Use environment variable `TECHNITIUM_TOKEN` for script access.

### 2. Upstream & Security
- **Forwarders**: DNS-over-HTTPS (DoH) enabled via Quad9:
  - `https://9.9.9.9/dns-query`
  - `https://149.112.112.112/dns-query`
- **Blocklists**: 7 lists enabled (StevenBlack, OISD, AdAway, etc.).
- **Blocking Mode**: Set to `0.0.0.0` to prevent search domain suffixing and reduce log noise.
- **Features**: QNAME Minimization and DNSSEC validation enabled.

### 3. DNS Zones
- **Local Zone**: `torquasmvo.internal` (~68 records migrated from Pi-hole).
- **Reverse DNS (PTR)**: Conditional Forwarder zones configured on **both** nodes to resolve local hostnames via UDM Pro:
  - `1.168.192.in-addr.arpa` (Main LAN)
  - `0.0.10.in-addr.arpa` (Homelab VLAN)

## Tooling & Management

### Management Script
The unified `scripts/technitium/manage.py` tool handles all cluster operations.

| Command | Purpose |
|---------|---------|
| `python3 manage.py status` | Checks health and sync status of both nodes. |
| `python3 manage.py setup` | Configures Primary node (zones, settings, blocklists). |
| `python3 manage.py reverse-dns` | Configures PTR zones on **all** nodes (Manual sync). |
| `python3 manage.py forwarders` | Updates upstream DNS providers. |
| `python3 manage.py import --zip <file>` | Migrates records from Pi-hole Teleporter ZIP. |
| `python3 manage.py analyze` | Analyzes NXDOMAIN queries to identify blocked domains and sources. |

### Web UI Access
- **Primary**: [http://192.168.1.7:5380](http://192.168.1.7:5380)
- **Secondary**: [http://192.168.1.8:5380](http://192.168.1.8:5380)

## Maintenance & Operations

### Adding Records
Always add static records to the **Primary** node. They will replicate to the Secondary within seconds.

### Updating Reverse DNS
If you add a new VLAN (e.g., `10.20.20.0/24`), you must add the PTR zone to **both** nodes using the script:
```bash
python3 scripts/technitium/manage.py reverse-dns --target 192.168.1.1
```

### Verification
Test local resolution and reverse lookups:
```bash
# Forward lookup
dig @192.168.1.7 plex.torquasmvo.internal +short

# Reverse lookup (Dashboard hostname resolution)
dig @192.168.1.7 -x 192.168.1.163 +short
```

## API Quick Reference

| Action | Endpoint |
|--------|----------|
| Add Record | `/api/zones/records/add` |
| Create Zone | `/api/zones/create` |
| Set Settings | `/api/settings/set` |
| Get Settings | `/api/settings/get` |
| verify Token | `/api/user/verifyToken` |
