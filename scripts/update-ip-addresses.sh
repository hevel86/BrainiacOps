#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output_file="${repo_root}/docs/ip_addresses.md"
pool_file="${repo_root}/kubernetes/infrastructure/metallb/overlays/default/metallb.yaml"

timestamp_utc="$(date -u +"%Y-%m-%d")"

temp_file="$(mktemp)"
trap 'rm -f "$temp_file"' EXIT

ranges=()
if [[ -f "${pool_file}" ]]; then
  in_addresses=0
  while IFS= read -r line; do
    if [[ "${line}" =~ ^[[:space:]]*addresses:[[:space:]]*$ ]]; then
      in_addresses=1
      continue
    fi
    if [[ "${in_addresses}" -eq 1 ]]; then
      if [[ "${line}" =~ ^[[:space:]]*-[[:space:]]*([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(-[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)?) ]]; then
        ranges+=("${BASH_REMATCH[1]}")
      elif [[ ! "${line}" =~ ^[[:space:]]*-[[:space:]]* ]]; then
        in_addresses=0
      fi
    fi
  done < "${pool_file}"
fi

range_text="Unknown"
pool_total="Unknown"
pool_used="Unknown"
pool_free="Unknown"

{
  echo "# Kubernetes Service IP Addresses"
  echo
  echo "Last updated: ${timestamp_utc} UTC"
  if [[ ${#ranges[@]} -gt 0 ]]; then
    range_text="$(printf "%s" "${ranges[0]}")"
    if [[ ${#ranges[@]} -gt 1 ]]; then
      for ((i=1; i<${#ranges[@]}; i++)); do
        range_text+=", ${ranges[$i]}"
      done
    fi
  fi
  echo "MetalLB pool: ${range_text}"
  used_ips=()
  while read -r name namespace ip; do
    if [[ -n "${ip}" && "${ip}" != "<none>" ]]; then
      used_ips+=("${ip}")
    fi
  done < <(
    kubectl get svc -A --field-selector spec.type=LoadBalancer \
      -o custom-columns=NAME:.metadata.name,NAMESPACE:.metadata.namespace,EXTERNAL-IP:.status.loadBalancer.ingress[0].ip \
      --no-headers
  )
  if [[ ${#ranges[@]} -gt 0 ]]; then
    pool_counts="$(RANGES="${ranges[*]}" USED_IPS="${used_ips[*]}" python3 - <<'PY'
import ipaddress
import os

ranges = os.environ.get("RANGES", "").split()
used = set(os.environ.get("USED_IPS", "").split())

total = 0
for r in ranges:
    if "-" in r:
        start, end = r.split("-", 1)
        start_ip = ipaddress.ip_address(start)
        end_ip = ipaddress.ip_address(end)
        total += int(end_ip) - int(start_ip) + 1
    else:
        total += 1

used_in_pool = 0
for ip in used:
    if not ip:
        continue
    try:
        ip_obj = ipaddress.ip_address(ip)
    except ValueError:
        continue
    for r in ranges:
        if "-" in r:
            start, end = r.split("-", 1)
            if ipaddress.ip_address(start) <= ip_obj <= ipaddress.ip_address(end):
                used_in_pool += 1
                break
        else:
            if ip == r:
                used_in_pool += 1
                break

free = max(total - used_in_pool, 0)
print(f"{total} {used_in_pool} {free}")
PY
)"
    pool_total="$(cut -d' ' -f1 <<< "${pool_counts}")"
    pool_used="$(cut -d' ' -f2 <<< "${pool_counts}")"
    pool_free="$(cut -d' ' -f3 <<< "${pool_counts}")"
  fi
  echo "MetalLB IPs: total=${pool_total} used=${pool_used} free=${pool_free}"
  echo
  echo "| Service | Namespace | IP Address |"
  echo "| :------ | :-------- | :--------- |"
  kubectl get svc -A --field-selector spec.type=LoadBalancer \
      -o custom-columns=NAME:.metadata.name,NAMESPACE:.metadata.namespace,EXTERNAL-IP:.status.loadBalancer.ingress[0].ip \
      --no-headers \
      | sort -k3,3 \
      | while read -r name namespace ip; do
          if [[ -z "${ip}" || "${ip}" == "<none>" ]]; then
            ip=""
          fi
          printf "| %s | %s | %s |\n" "${name}" "${namespace}" "${ip}"
        done
} > "${temp_file}"

mv "${temp_file}" "${output_file}"
