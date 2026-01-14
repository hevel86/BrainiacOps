#!/usr/bin/env python3
"""
Technitium DNS Manager

A unified tool to manage the Proxmox LXC Technitium DNS Cluster.
Combines setup, status checks, updates, and migration utilities.

Features:
- Status: Check clustering, blocklists, and sync status.
- Setup: Configure Primary/Secondary nodes, zones, and settings.
- Reverse DNS: Configure conditional forwarder zones on all nodes.
- Forwarders: Update upstream DNS providers.
- Import: Migrate records from Pi-hole Teleporter ZIPs.

Usage:
  python3 manage.py <command> [options]

Commands:
  status             Check cluster status
  setup              Run initial setup (zones, settings)
  reverse-dns        Configure reverse DNS zones
  forwarders         Update upstream forwarders
  import             Import Pi-hole records
"""

import argparse
import os
import sys
import json
import urllib.request
import urllib.parse
import zipfile
import shutil
import subprocess
import random
import getpass

try:
    import tomllib
except ModuleNotFoundError:
    try:
        import tomli as tomllib
    except ImportError:
        tomllib = None

# Default Configuration
DEFAULT_PRIMARY = "192.168.1.7"
DEFAULT_SECONDARY = "192.168.1.8"
DEFAULT_PORT = 5380
DEFAULT_ZONE = "torquasmvo.internal"
ENV_TOKEN = os.environ.get("TECHNITIUM_TOKEN")


# --- Shared Utilities ---

def make_request(host, endpoint, params=None, token=None):
    """Make an API request to a Technitium instance."""
    if not token:
        token = ENV_TOKEN
    
    if not token:
        print(f"Error: No API token provided for {host}{endpoint}. Set TECHNITIUM_TOKEN env var.", file=sys.stderr)
        return None

    base_url = f"http://{host}:{DEFAULT_PORT}/api"
    url = f"{base_url}{endpoint}?token={token}"
    
    if params:
        for k, v in params.items():
            url += f"&{k}={urllib.parse.quote(str(v))}"
    
    try:
        req = urllib.request.Request(url)
        with urllib.request.urlopen(req, timeout=10) as response:
            return json.loads(response.read().decode('utf-8'))
    except Exception as e:
        print(f"Error accessing {host}{endpoint}: {e}", file=sys.stderr)
        return None


# --- Commands ---

def cmd_status(args):
    """Check status of the cluster."""
    print(f"--- Checking Primary ({args.primary}) ---")
    
    # Check Clustering
    resp = make_request(args.primary, "/settings/get", token=args.token)
    if resp and resp.get('status') == 'ok':
        nodes = resp.get('response', {}).get('clusterNodes', [])
        print(f"Cluster Nodes: {len(nodes)}")
        for node in nodes:
            print(f"- {node['name']} ({node['ipAddresses'][0]}): {node['state']}")
    else:
        print("Failed to get Primary settings.")

    print(f"\n--- Checking Secondary ({args.secondary}) ---")
    
    # Check Zones
    resp = make_request(args.secondary, "/zones/list", {"pageNumber": 1, "recordsPerPage": 10}, token=args.token)
    if resp and resp.get('status') == 'ok':
        total = resp.get('response', {}).get('totalRecords', 0)
        print(f"Zones: {total}")
        for zone in resp.get('response', {}).get('data', []):
            print(f"- {zone['name']} ({zone['type']})")
    else:
        print("Failed to get Secondary zones.")

    # Check Blocklists
    resp = make_request(args.secondary, "/settings/get", token=args.token)
    if resp and resp.get('status') == 'ok':
        urls = resp.get('response', {}).get('blockListUrls', [])
        print(f"Blocklists: {len(urls)}")
        for u in urls:
            print(f"- {u}")
    else:
        print("Failed to get Secondary settings.")


def cmd_setup(args):
    """Run initial setup on Primary."""
    print(f"--- Setting up Primary ({args.primary}) ---")

    # 1. Get Current Settings
    print("Fetching current settings...")
    settings = make_request(args.primary, "/settings/get", token=args.token)
    if not settings or settings.get('status') != 'ok':
        print("Failed to get settings.")
        return

    current_config = settings.get('response', {})
    
    # 2. Prepare Blocklists
    new_blocklists = [
        "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts",
        "https://big.oisd.nl/",
        "https://adaway.org/hosts.txt",
        "https://v.firebog.net/hosts/AdguardDNS.txt"
    ]
    
    existing_urls = current_config.get('blockListUrls', [])
    if isinstance(existing_urls, str):
        existing_urls = [u.strip() for u in existing_urls.split(',')]
    
    final_urls = list(existing_urls)
    for url in new_blocklists:
        if url not in final_urls:
            final_urls.append(url)
            
    final_urls_str = ",".join(final_urls)

    # 3. Apply Settings
    update_params = {
        "forwarders": "9.9.9.9,149.112.112.112", # Quad9 Default
        "enableBlocking": "true",
        "blockListUrls": final_urls_str,
        "enableQNameMinimization": "true",
        "enableDnsSec": "true"
    }

    print(f"Applying settings (Blocklists: {len(final_urls)})...")
    resp = make_request(args.primary, "/settings/set", update_params, token=args.token)
    if resp and resp.get('status') == 'ok':
        print("Settings configured successfully.")
    else:
        print(f"Failed to apply settings: {resp}")

    # 4. Create Zone
    print(f"Ensuring zone exists: {args.zone}")
    resp = make_request(args.primary, "/zones/create", {"zone": args.zone, "type": "Primary"}, token=args.token)
    if resp and resp.get('status') == 'ok':
        print("Zone created.")
    elif resp and "Zone already exists" in resp.get('errorMessage', ''):
        print("Zone already exists (OK).")
    else:
        print(f"Failed to create zone: {resp}")


def cmd_reverse_dns(args):
    """Configure Reverse DNS (PTR) zones on ALL nodes."""
    ptr_zones = ["1.168.192.in-addr.arpa", "0.0.10.in-addr.arpa"]
    hosts = [args.primary, args.secondary]

    for host in hosts:
        print(f"\n--- Configuring {host} ---")
        for zone in ptr_zones:
            print(f"Ensuring zone: {zone}")
            
            # Create as Forwarder
            resp = make_request(host, "/zones/create", {
                "zone": zone, 
                "type": "Forwarder",
                "forwarder": args.target  # e.g., 192.168.1.1
            }, token=args.token)
            
            if resp and resp.get('status') == 'ok':
                print(f"  OK: Zone {zone} created.")
            elif resp and "Zone already exists" in resp.get('errorMessage', ''):
                print(f"  Exists: Resetting {zone}...")
                make_request(host, "/zones/delete", {"zone": zone}, token=args.token)
                make_request(host, "/zones/create", {
                    "zone": zone, 
                    "type": "Forwarder",
                    "forwarder": args.target
                }, token=args.token)
                print(f"  OK: Zone {zone} reset.")
            else:
                print(f"  FAILED: {resp}")


def cmd_forwarders(args):
    """Update upstream forwarders."""
    print(f"--- Updating Forwarders on Primary ({args.primary}) ---")
    print(f"New Forwarders: {args.forwarders}")

    resp = make_request(args.primary, "/settings/set", {"forwarders": args.forwarders}, token=args.token)
    if resp and resp.get('status') == 'ok':
        print("Forwarders updated successfully.")
    else:
        print(f"Failed to update forwarders: {resp}")


# --- Import Logic (Pi-hole) ---

def parse_custom_list(text):
    records = []
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith("#"): continue
        parts = line.split()
        if len(parts) < 2: continue
        ip, name = parts[0], parts[1]
        if ":" in ip: continue
        records.append(("A", name, ip))
    return records

def parse_custom_cname(text):
    records = []
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith("#"): continue
        if line.startswith("cname="): line = line[len("cname="):]
        if "," not in line: continue
        alias, target = [part.strip() for part in line.split(",", 1)]
        if not alias or not target: continue
        records.append(("CNAME", alias, target))
    return records

def parse_pihole_toml(text):
    records = []
    if not tomllib: return records
    try:
        payload = tomllib.loads(text)
    except Exception:
        return records
    dns = payload.get("dns", {})
    for entry in dns.get("hosts", []) or []:
        parts = str(entry).split()
        if len(parts) < 2: continue
        ip, name = parts[0], parts[1]
        if ":" in ip: continue
        records.append(("A", name, ip))
    for entry in dns.get("cnameRecords", []) or []:
        if "," not in str(entry): continue
        alias, target = [part.strip() for part in str(entry).split(",", 1)]
        if not alias or not target: continue
        records.append(("CNAME", alias, target))
    return records

def normalize_name(name, zone):
    name = name.rstrip(".")
    zone = zone.rstrip(".")
    if "." not in name: return f"{name}.{zone}"
    return name

def cmd_import(args):
    """Import Pi-hole Teleporter ZIP."""
    if not args.zip or not zipfile.is_zipfile(args.zip):
        print(f"Error: Invalid zip file: {args.zip}", file=sys.stderr)
        return

    print(f"--- Importing from {args.zip} to {args.primary} ---")
    records = []
    
    with zipfile.ZipFile(args.zip) as zf:
        # Check files
        for name in zf.namelist():
            if name.endswith("custom.list"):
                records.extend(parse_custom_list(zf.read(name).decode("utf-8", errors="replace")))
            elif "custom-cname" in name:
                records.extend(parse_custom_cname(zf.read(name).decode("utf-8", errors="replace")))
            elif name.endswith("pihole.toml") and tomllib:
                records.extend(parse_pihole_toml(zf.read(name).decode("utf-8", errors="replace")))

    if not records:
        print("No records found in zip.")
        return

    print(f"Found {len(records)} records. Importing to zone: {args.zone}...")
    
    created = 0
    skipped = 0
    
    for rtype, name, value in records:
        fqdn = normalize_name(name, args.zone)
        # Check if inside zone (basic check)
        if not fqdn.endswith(args.zone) and not args.force:
             # Basic filter
             pass

        params = {
            "zone": args.zone,
            "domain": fqdn,
            "type": rtype,
            "ttl": 3600
        }
        
        if rtype == "A": params["ipAddress"] = value
        elif rtype == "CNAME": params["cname"] = value.rstrip(".")
        
        if args.dry_run:
            print(f"Dry Run: {rtype} {fqdn} -> {value}")
            created += 1
            continue

        resp = make_request(args.primary, "/zones/records/add", params, token=args.token)
        
        if resp and resp.get('status') == 'ok':
            print(f"Created: {rtype} {fqdn} -> {value}")
            created += 1
        elif resp and "already exists" in str(resp.get('errorMessage', '')).lower():
            if args.skip_existing:
                print(f"Exists: {rtype} {fqdn}")
            else:
                print(f"Error: {rtype} {fqdn} exists.")
            skipped += 1
        else:
            print(f"Error: {rtype} {fqdn} -> {resp}")
            skipped += 1

    print(f"Done. Created: {created}, Skipped: {skipped}")


# --- Main ---

def main():
    parser = argparse.ArgumentParser(description="Technitium DNS Manager")
    parser.add_argument("--token", default=ENV_TOKEN, help="API Token (default: env TECHNITIUM_TOKEN)")
    parser.add_argument("--primary", default=DEFAULT_PRIMARY, help=f"Primary IP (default: {DEFAULT_PRIMARY})")
    parser.add_argument("--secondary", default=DEFAULT_SECONDARY, help=f"Secondary IP (default: {DEFAULT_SECONDARY})")
    
    subparsers = parser.add_subparsers(dest="command", required=True)

    # Status
    subparsers.add_parser("status", help="Check cluster status")

    # Setup
    setup_parser = subparsers.add_parser("setup", help="Run initial setup")
    setup_parser.add_argument("--zone", default=DEFAULT_ZONE, help="Primary Zone Name")

    # Reverse DNS
    rev_parser = subparsers.add_parser("reverse-dns", help="Configure Reverse DNS zones")
    rev_parser.add_argument("--target", default="192.168.1.1", help="Target DNS for forwarding (UDM Pro)")

    # Forwarders
    fwd_parser = subparsers.add_parser("forwarders", help="Update upstream forwarders")
    fwd_parser.add_argument("forwarders", help="Comma-separated IPs (e.g., 9.9.9.9,1.1.1.1)")

    # Import
    imp_parser = subparsers.add_parser("import", help="Import Pi-hole Teleporter")
    imp_parser.add_argument("--zip", required=True, help="Path to zip file")
    imp_parser.add_argument("--zone", default=DEFAULT_ZONE, help="Target zone")
    imp_parser.add_argument("--dry-run", action="store_true", help="Don't apply changes")
    imp_parser.add_argument("--skip-existing", action="store_true", help="Skip existing records")
    imp_parser.add_argument("--force", action="store_true", help="Allow records outside zone")

    args = parser.parse_args()

    if not args.token:
        print("Error: API Token is required. Set TECHNITIUM_TOKEN env var or use --token.", file=sys.stderr)
        sys.exit(1)

    if args.command == "status":
        cmd_status(args)
    elif args.command == "setup":
        cmd_setup(args)
    elif args.command == "reverse-dns":
        cmd_reverse_dns(args)
    elif args.command == "forwarders":
        cmd_forwarders(args)
    elif args.command == "import":
        cmd_import(args)

if __name__ == "__main__":
    main()
