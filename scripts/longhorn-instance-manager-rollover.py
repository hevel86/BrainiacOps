#!/usr/bin/env python3
"""Longhorn instance-manager rollover helper.

Discovers workloads attached to Longhorn volumes (optionally on a specific node),
restarts them one-by-one, and prints live Longhorn migration metrics.
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
import time
from dataclasses import dataclass
from typing import Dict, List, Optional, Sequence, Set, Tuple


@dataclass(frozen=True)
class Workload:
    namespace: str
    kind: str
    name: str

    @property
    def ref(self) -> str:
        return f"{self.kind}/{self.name}"


@dataclass
class InstanceManagerStat:
    name: str
    node: str
    image: str
    engines: int
    replicas: int
    cpu: str = "-"
    memory: str = "-"


@dataclass
class WorkloadPlan:
    workload: Workload
    volumes: List[str]
    migrated: bool
    reason: str


def run(cmd: Sequence[str], expect_json: bool = False, allow_fail: bool = False):
    proc = subprocess.run(cmd, capture_output=True, text=True)
    if proc.returncode != 0 and not allow_fail:
        stderr = proc.stderr.strip() or "(no stderr)"
        raise RuntimeError(f"Command failed ({proc.returncode}): {' '.join(cmd)}\n{stderr}")
    if expect_json:
        stdout = proc.stdout.strip()
        if not stdout:
            return {}
        return json.loads(stdout)
    return proc.stdout


def check_dependencies() -> None:
    for tool in ("kubectl",):
        if shutil.which(tool) is None:
            raise RuntimeError(f"Missing required dependency: {tool}")


def get_volumes() -> Dict:
    return run(
        ["kubectl", "-n", "longhorn-system", "get", "volumes.longhorn.io", "-o", "json"],
        expect_json=True,
    )


def get_engines() -> Dict:
    return run(
        ["kubectl", "-n", "longhorn-system", "get", "engines.longhorn.io", "-o", "json"],
        expect_json=True,
    )


def get_replicaset_owner(ns: str, rs_name: str, cache: Dict[Tuple[str, str], Optional[Workload]]) -> Optional[Workload]:
    key = (ns, rs_name)
    if key in cache:
        return cache[key]

    rs = run(["kubectl", "-n", ns, "get", "rs", rs_name, "-o", "json"], expect_json=True, allow_fail=True)
    if not rs:
        cache[key] = None
        return None

    for owner in rs.get("metadata", {}).get("ownerReferences", []):
        if owner.get("kind") == "Deployment" and owner.get("name"):
            wl = Workload(namespace=ns, kind="deploy", name=owner["name"])
            cache[key] = wl
            return wl

    # Fallback: strip RS hash suffix for older objects.
    guessed = re.sub(r"-[a-f0-9]{9,10}$", "", rs_name)
    wl = Workload(namespace=ns, kind="deploy", name=guessed)
    cache[key] = wl
    return wl


def resolve_workload(ns: str, wtype: str, wname: str, rs_cache: Dict[Tuple[str, str], Optional[Workload]]) -> Optional[Workload]:
    if wtype == "ReplicaSet":
        return get_replicaset_owner(ns, wname, rs_cache)
    if wtype == "Deployment":
        return Workload(namespace=ns, kind="deploy", name=wname)
    if wtype == "StatefulSet":
        return Workload(namespace=ns, kind="statefulset", name=wname)
    if wtype == "DaemonSet":
        return Workload(namespace=ns, kind="daemonset", name=wname)
    return None


def discover_workload_volumes(target_node: Optional[str]) -> Dict[Workload, Set[str]]:
    vols = get_volumes()
    rs_cache: Dict[Tuple[str, str], Optional[Workload]] = {}
    workload_vols: Dict[Workload, Set[str]] = {}

    for item in vols.get("items", []):
        volume_name = item.get("metadata", {}).get("name", "")
        st = item.get("status", {})
        if st.get("state") != "attached":
            continue
        if target_node and st.get("currentNodeID") != target_node:
            continue

        ks = st.get("kubernetesStatus", {})
        ns = ks.get("namespace")
        statuses = ks.get("workloadsStatus") or []
        for ws in statuses:
            wl = resolve_workload(ns, ws.get("workloadType", ""), ws.get("workloadName", ""), rs_cache)
            if wl is None:
                continue
            if wl not in workload_vols:
                workload_vols[wl] = set()
            if volume_name:
                workload_vols[wl].add(volume_name)

    return workload_vols


def build_workload_plans(workload_vols: Dict[Workload, Set[str]]) -> List[WorkloadPlan]:
    engines = get_engines()
    im_data = run(
        ["kubectl", "-n", "longhorn-system", "get", "instancemanagers.longhorn.io", "-o", "json"],
        expect_json=True,
    )

    im_image: Dict[str, str] = {}
    for item in im_data.get("items", []):
        im_image[item.get("metadata", {}).get("name", "")] = item.get("spec", {}).get("image", "")

    vol_to_im: Dict[str, str] = {}
    for item in engines.get("items", []):
        vol_name = item.get("spec", {}).get("volumeName", "")
        vol_to_im[vol_name] = item.get("status", {}).get("instanceManagerName", "")

    plans: List[WorkloadPlan] = []
    for wl in sorted(workload_vols.keys(), key=lambda w: (w.namespace, w.kind, w.name)):
        volumes = sorted(workload_vols[wl])
        pending: List[str] = []
        for vol in volumes:
            im_name = vol_to_im.get(vol, "")
            image = im_image.get(im_name, "")
            if "hotfix" in image:
                continue
            if image:
                pending.append(f"{vol} ({image.split(':')[-1]})")
            elif im_name:
                pending.append(f"{vol} (unknown image via {im_name})")
            else:
                pending.append(f"{vol} (no instance-manager)")

        migrated = len(pending) == 0 and len(volumes) > 0
        reason = "all attached volumes on hotfix instance-manager" if migrated else "; ".join(pending)
        plans.append(WorkloadPlan(workload=wl, volumes=volumes, migrated=migrated, reason=reason))

    return plans


def parse_top_memory_to_mib(value: str) -> float:
    value = value.strip()
    if value.endswith("Ki"):
        return float(value[:-2]) / 1024.0
    if value.endswith("Mi"):
        return float(value[:-2])
    if value.endswith("Gi"):
        return float(value[:-2]) * 1024.0
    if value.endswith("Ti"):
        return float(value[:-2]) * 1024.0 * 1024.0
    return 0.0


def get_instance_manager_stats() -> List[InstanceManagerStat]:
    data = run(
        ["kubectl", "-n", "longhorn-system", "get", "instancemanagers.longhorn.io", "-o", "json"],
        expect_json=True,
    )
    top_out = run(
        [
            "kubectl",
            "-n",
            "longhorn-system",
            "top",
            "pod",
            "-l",
            "longhorn.io/component=instance-manager",
            "--no-headers",
        ],
        allow_fail=True,
    )

    top_map: Dict[str, Tuple[str, str]] = {}
    for line in (top_out or "").splitlines():
        cols = line.split()
        if len(cols) >= 3:
            top_map[cols[0]] = (cols[1], cols[2])

    stats: List[InstanceManagerStat] = []
    for item in data.get("items", []):
        st = item.get("status", {})
        pod_name = item.get("metadata", {}).get("name", "")
        cpu, mem = top_map.get(pod_name, ("-", "-"))
        stats.append(
            InstanceManagerStat(
                name=pod_name,
                node=item.get("spec", {}).get("nodeID", ""),
                image=item.get("spec", {}).get("image", ""),
                engines=len((st.get("instanceEngines") or {}).keys()),
                replicas=len((st.get("instanceReplicas") or {}).keys()),
                cpu=cpu,
                memory=mem,
            )
        )

    stats.sort(key=lambda s: (s.node, s.name))
    return stats


def get_node_memory(target_node: Optional[str]) -> str:
    out = run(["kubectl", "top", "nodes", "--no-headers"], allow_fail=True)
    if not out:
        return "n/a"

    lines = out.splitlines()
    if target_node:
        for line in lines:
            cols = line.split()
            if len(cols) >= 5 and cols[0] == target_node:
                return f"{cols[3]} ({cols[4]})"
        return "n/a"

    # summarize max node mem%
    max_pct = -1
    max_line = None
    for line in lines:
        cols = line.split()
        if len(cols) < 5:
            continue
        pct = int(cols[4].rstrip("%"))
        if pct > max_pct:
            max_pct = pct
            max_line = cols
    if max_line:
        return f"{max_line[0]} {max_line[3]} ({max_line[4]})"
    return "n/a"


def print_dashboard(target_node: Optional[str], header: str = "") -> None:
    stats = get_instance_manager_stats()

    if target_node:
        stats = [s for s in stats if s.node == target_node]

    old_mem_mib = 0.0
    new_mem_mib = 0.0
    old_engines = old_replicas = new_engines = new_replicas = 0

    for s in stats:
        mem_mib = parse_top_memory_to_mib(s.memory)
        if "hotfix" in s.image:
            new_mem_mib += mem_mib
            new_engines += s.engines
            new_replicas += s.replicas
        else:
            old_mem_mib += mem_mib
            old_engines += s.engines
            old_replicas += s.replicas

    if header:
        print(f"\n=== {header} ===")

    print(
        "Migration Summary: "
        f"old engines/replicas={old_engines}/{old_replicas}, "
        f"new engines/replicas={new_engines}/{new_replicas}, "
        f"old mem={old_mem_mib:.0f}Mi, new mem={new_mem_mib:.0f}Mi"
    )
    print(f"Node memory: {get_node_memory(target_node)}")

    print("Instance Managers:")
    print("  NODE         NAME                                         E/R      MEM      IMAGE")
    for s in stats:
        er = f"{s.engines}/{s.replicas}"
        image_tag = s.image.split(":")[-1] if ":" in s.image else s.image
        print(f"  {s.node:<12} {s.name:<44} {er:<8} {s.memory:<8} {image_tag}")


def restart_workload(w: Workload, timeout: int, interval: int, target_node: Optional[str]) -> None:
    print(f"\n-- Restarting {w.namespace} {w.ref}")
    run(["kubectl", "-n", w.namespace, "rollout", "restart", w.ref])

    start = time.time()
    while True:
        elapsed = int(time.time() - start)
        status = subprocess.run(
            ["kubectl", "-n", w.namespace, "rollout", "status", w.ref, "--timeout=5s"],
            capture_output=True,
            text=True,
        )
        print_dashboard(target_node, header=f"{w.ref} | t+{elapsed}s")
        if status.returncode == 0:
            msg = status.stdout.strip().splitlines()[-1] if status.stdout.strip() else "rollout complete"
            print(f"Completed: {msg}")
            return

        if time.time() - start > timeout:
            stderr = status.stderr.strip()
            stdout = status.stdout.strip()
            detail = stderr or stdout or "timeout waiting for rollout"
            raise RuntimeError(f"Timed out waiting for {w.ref}: {detail}")

        time.sleep(interval)


def get_replicas(w: Workload) -> int:
    out = run(
        [
            "kubectl",
            "-n",
            w.namespace,
            "get",
            w.ref,
            "-o",
            "jsonpath={.spec.replicas}",
        ]
    ).strip()
    if out == "":
        return 1
    return int(out)


def scale_workload(w: Workload, replicas: int) -> None:
    run(["kubectl", "-n", w.namespace, "scale", w.ref, f"--replicas={replicas}"])


def wait_rollout(w: Workload, timeout: int) -> None:
    run(["kubectl", "-n", w.namespace, "rollout", "status", w.ref, f"--timeout={timeout}s"])


def bounce_workload(
    w: Workload, timeout: int, interval: int, target_node: Optional[str], down_wait: int
) -> None:
    if w.kind not in ("deploy", "statefulset"):
        # DaemonSets cannot scale to 0, fallback to rollout restart.
        restart_workload(w, timeout=timeout, interval=interval, target_node=target_node)
        return

    original = get_replicas(w)
    print(f"\n-- Bounce {w.namespace} {w.ref} (replicas {original} -> 0 -> {original})")
    scale_workload(w, 0)
    wait_rollout(w, timeout=timeout)
    print_dashboard(target_node, header=f"{w.ref} scaled to 0")

    if down_wait > 0:
        print(f"Waiting {down_wait}s for detach to settle...")
        time.sleep(down_wait)
        print_dashboard(target_node, header=f"{w.ref} detach wait complete")

    scale_workload(w, original)
    start = time.time()
    while True:
        elapsed = int(time.time() - start)
        status = subprocess.run(
            ["kubectl", "-n", w.namespace, "rollout", "status", w.ref, "--timeout=5s"],
            capture_output=True,
            text=True,
        )
        print_dashboard(target_node, header=f"{w.ref} scale-up | t+{elapsed}s")
        if status.returncode == 0:
            msg = status.stdout.strip().splitlines()[-1] if status.stdout.strip() else "rollout complete"
            print(f"Completed: {msg}")
            return
        if time.time() - start > timeout:
            stderr = status.stderr.strip()
            stdout = status.stdout.strip()
            detail = stderr or stdout or "timeout waiting for rollout"
            raise RuntimeError(f"Timed out waiting for {w.ref}: {detail}")
        time.sleep(interval)


def filter_plans(
    plans: List[WorkloadPlan], namespace: Optional[str], include: Optional[str], limit: Optional[int]
) -> List[WorkloadPlan]:
    out = plans
    if namespace:
        out = [p for p in out if p.workload.namespace == namespace]
    if include:
        pattern = re.compile(include)
        out = [p for p in out if pattern.search(p.workload.name)]
    if limit is not None and limit >= 0:
        out = out[:limit]
    return out


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(
        description="Roll Longhorn-attached workloads to migrate old instance-manager instances",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    p.add_argument("--node", default=None, help="Only process workloads whose attached volume is on this node")
    p.add_argument("--namespace", default=None, help="Only process workloads in this namespace")
    p.add_argument("--include", default=None, help="Regex filter for workload names")
    p.add_argument("--limit", type=int, default=None, help="Max number of workloads to process")
    p.add_argument("--timeout", type=int, default=900, help="Rollout timeout per workload in seconds")
    p.add_argument("--interval", type=int, default=15, help="Dashboard refresh interval in seconds")
    p.add_argument(
        "--strategy",
        choices=("rollout", "bounce"),
        default="bounce",
        help="How to cycle workloads; bounce does scale 0 -> original to force volume detach/reattach",
    )
    p.add_argument(
        "--down-wait",
        type=int,
        default=20,
        help="Seconds to wait after scaling to 0 before scaling back up (bounce strategy)",
    )
    p.add_argument(
        "--no-skip-migrated",
        action="store_true",
        help="Process workloads even if all attached volumes are already on hotfix instance-managers",
    )
    p.add_argument("--execute", action="store_true", help="Actually restart workloads (default is dry-run)")
    p.add_argument("--continue-on-error", action="store_true", help="Continue to next workload if one fails")
    return p.parse_args()


def main() -> int:
    args = parse_args()

    try:
        check_dependencies()
        workload_vols = discover_workload_volumes(args.node)
        plans = build_workload_plans(workload_vols)
        plans = filter_plans(plans, args.namespace, args.include, args.limit)

        if not plans:
            print("No matching Longhorn-attached workloads found.")
            print_dashboard(args.node, header="Current Longhorn State")
            return 0

        selected = plans if args.no_skip_migrated else [p for p in plans if not p.migrated]
        skipped = [p for p in plans if p.migrated]

        print(f"Matched {len(plans)} workload(s):")
        for idx, p in enumerate(plans, 1):
            prefix = "SKIP" if p.migrated and not args.no_skip_migrated else "RUN "
            print(f"  {idx:>2}. [{prefix}] {p.workload.namespace} {p.workload.ref}")

        print_dashboard(args.node, header="Pre-Run Metrics")

        if not args.execute:
            if skipped and not args.no_skip_migrated:
                print(f"\nWill auto-skip {len(skipped)} workload(s) already migrated to hotfix.")
            print("\nDry-run mode. Re-run with --execute to apply restarts.")
            return 0

        if not selected:
            print("\nAll matched workloads are already migrated; nothing to do.")
            print_dashboard(args.node, header="Post-Run Metrics")
            return 0

        failures = []
        for idx, p in enumerate(selected, 1):
            w = p.workload
            print(f"\n## [{idx}/{len(selected)}] {w.namespace} {w.ref}")
            try:
                if args.strategy == "bounce":
                    bounce_workload(
                        w,
                        timeout=args.timeout,
                        interval=args.interval,
                        target_node=args.node,
                        down_wait=args.down_wait,
                    )
                else:
                    restart_workload(w, timeout=args.timeout, interval=args.interval, target_node=args.node)
            except Exception as exc:  # noqa: BLE001
                failures.append((w, str(exc)))
                print(f"ERROR: {exc}")
                if not args.continue_on_error:
                    break

        print_dashboard(args.node, header="Post-Run Metrics")

        if failures:
            print("\nFailures:")
            for w, msg in failures:
                print(f"  - {w.namespace} {w.ref}: {msg}")
            return 1

        if skipped and not args.no_skip_migrated:
            print(f"\nSkipped {len(skipped)} workload(s) already migrated.")
        print("\nAll requested workloads processed successfully.")
        return 0

    except Exception as exc:  # noqa: BLE001
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
