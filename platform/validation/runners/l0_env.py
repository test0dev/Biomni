#!/usr/bin/env python3
"""L0 environment gate."""

from __future__ import annotations

import shutil
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
sys.path.insert(0, str(Path(__file__).resolve().parents[3]))

from common import REPORTS, host_info, run_cmd, stamp, write_json  # noqa: E402


def main() -> int:
    checks = []
    host = host_info()
    machine = host.get("machine", "")
    checks.append(
        {
            "name": "arch_is_aarch64",
            "status": "PASS" if machine in ("aarch64", "arm64") else "FAIL_LOGIC",
            "detail": machine,
        }
    )

    # nvidia-smi
    r = run_cmd(["nvidia-smi"], timeout=30)
    checks.append(
        {
            "name": "nvidia_smi",
            "status": "PASS" if r["returncode"] == 0 else "FAIL_GPU",
            "detail": r,
        }
    )

    # disk
    usage = shutil.disk_usage("/")
    free_gb = usage.free / (1024**3)
    checks.append(
        {
            "name": "disk_free_gb",
            "status": "PASS" if free_gb > 5 else "FAIL_DEP",
            "detail": {"free_gb": round(free_gb, 2)},
        }
    )

    # tool count
    try:
        from biomni.utils import read_module2api

        m = read_module2api()
        n = sum(len(v) for v in m.values())
        checks.append(
            {
                "name": "tool_count_224",
                "status": "PASS" if n == 224 else "FAIL_SCHEMA",
                "detail": {"count": n, "modules": len(m)},
            }
        )
    except Exception as e:  # noqa: BLE001
        checks.append(
            {
                "name": "tool_count_224",
                "status": "FAIL_DEP",
                "detail": f"{type(e).__name__}: {e}",
            }
        )

    # docker
    r = run_cmd(["docker", "--version"], timeout=15)
    checks.append(
        {
            "name": "docker",
            "status": "PASS" if r["returncode"] == 0 else "FAIL_DEP",
            "detail": r,
        }
    )

    overall = "PASS" if all(c["status"] == "PASS" for c in checks) else "FAIL"
    payload = {
        "layer": "L0",
        "timestamp": stamp(),
        "host": host,
        "overall": overall,
        "checks": checks,
    }
    out = REPORTS / "l0_env.json"
    write_json(out, payload)
    print(f"L0 overall={overall} -> {out}")
    for c in checks:
        print(f"  [{c['status']}] {c['name']}")
    return 0 if overall == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
