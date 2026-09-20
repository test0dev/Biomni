#!/usr/bin/env python3
"""L4 full tool invocation — all 224 tools."""

from __future__ import annotations

import importlib
import json
import os
import signal
import sys
import traceback
from pathlib import Path

VAL = Path(__file__).resolve().parents[1]
REPO = VAL.parents[1]
sys.path.insert(0, str(VAL))
sys.path.insert(0, str(REPO))

from common import REPORTS, load_json, stamp, write_json  # noqa: E402
from inventory import inventory  # noqa: E402

FIX = VAL / "fixtures"


class _Timeout(Exception):
    pass


def _alarm_handler(signum, frame):  # noqa: ARG001
    raise _Timeout("timeout")


def load_tags() -> dict:
    p = VAL / "tags.json"
    if not p.exists():
        return {}
    return load_json(p).get("tools", {})


def load_l1_arm_bins() -> set[str]:
    p = REPORTS / "l1_cli.json"
    if not p.exists():
        return set()
    data = load_json(p)
    return set(data.get("arm_incompatible") or [])


def classify_exception(exc: BaseException, tags: set[str]) -> str:
    msg = f"{type(exc).__name__}: {exc}"
    low = msg.lower()
    if "exec format" in low or "wrong elf" in low:
        return "FAIL_ARM"
    if any(x in low for x in ("cuda", "gpu", "out of memory", "cublas", "cudnn")):
        return "FAIL_GPU"
    if any(
        x in low
        for x in (
            "connection",
            "timeout",
            "timed out",
            "http",
            "urlerror",
            "max retries",
            "name or service not known",
            "temporary failure",
            "403",
            "404",
            "429",
            "502",
            "503",
        )
    ):
        return "FAIL_NET"
    if any(
        x in low
        for x in (
            "no module named",
            "cannot import",
            "modulenotfound",
            "importerror",
            "file not found",
            "filenotfound",
            "command not found",
            "not found on path",
            "no such file",
        )
    ):
        # Only escalate to FAIL_ARM when the message clearly indicates bad ELF
        if "exec format" in low or "wrong elf" in low:
            return "FAIL_ARM"
        return "FAIL_DEP"
    return "FAIL_LOGIC"


def run_one(row: dict, fixture: dict, arm_bins: set[str], tags_map: dict) -> dict:
    key = row["key"]
    module = row["module"]
    name = row["name"]
    tinfo = tags_map.get(key, {})
    tagset = set(tinfo.get("tags") or [])
    bins = [b.lower() for b in (tinfo.get("bins") or [])]

    base = {
        "key": key,
        "module": module,
        "name": name,
        "tags": sorted(tagset),
        "mode": fixture.get("mode"),
        "timestamp": stamp(),
    }

    if not row.get("impl_exists"):
        return {**base, "status": "FAIL_SCHEMA", "error": "implementation function missing"}

    # Prefail ARM only on exact binary name match from L1
    for b in bins:
        bl = b.lower()
        if bl in {x.lower() for x in arm_bins}:
            return {
                **base,
                "status": "FAIL_ARM",
                "error": f"depends on ARM-incompatible binary: {bl}",
                "skipped_invoke": True,
            }
    # Map iqtree2 -> iqtree: if tool needs iqtree and only iqtree2 is bad but iqtree OK, continue
    if "iqtree2" in {x.lower() for x in arm_bins} and "iqtree" in bins and "iqtree2" not in bins:
        pass  # native iqtree available

    mode = fixture.get("mode") or "import_and_try"

    if mode == "skip_extra_env":
        return {
            **base,
            "status": "SKIP_EXTRA_ENV",
            "error": fixture.get("reason") or "separate env required",
        }

    if mode == "skip_auth":
        env_name = fixture.get("auth_env") or "SYNAPSE_AUTH_TOKEN"
        if not os.environ.get(env_name):
            return {
                **base,
                "status": "SKIP_AUTH",
                "error": f"missing env {env_name}",
            }

    # Import check
    try:
        mod = importlib.import_module(f"biomni.tool.{module}")
        fn = getattr(mod, name)
        if not callable(fn):
            return {**base, "status": "FAIL_SCHEMA", "error": "not callable"}
    except Exception as e:  # noqa: BLE001
        status = classify_exception(e, tagset)
        return {**base, "status": status, "error": f"{type(e).__name__}: {e}"}

    if mode == "import_only":
        return {**base, "status": "PASS", "note": "import_only"}

    kwargs = fixture.get("kwargs") or {}
    timeout_s = int(fixture.get("timeout_s") or 60)

    # Resolve relative data paths
    for k, v in list(kwargs.items()):
        if isinstance(v, str) and v.startswith("data/"):
            kwargs[k] = str(VAL / v)

    old_handler = signal.signal(signal.SIGALRM, _alarm_handler)
    signal.alarm(timeout_s)
    try:
        result = fn(**kwargs)
        text = result if isinstance(result, str) else repr(result)
        if len(text) > 2000:
            text = text[:2000] + "…"
        if fixture.get("expect_substr") and fixture["expect_substr"] not in text:
            return {
                **base,
                "status": "FAIL_LOGIC",
                "error": f"expect_substr missing: {fixture['expect_substr']}",
                "result_preview": text,
            }
        return {**base, "status": "PASS", "result_preview": text}
    except _Timeout:
        return {**base, "status": "FAIL_LOGIC", "error": f"Timeout after {timeout_s}s"}
    except Exception as e:  # noqa: BLE001
        status = classify_exception(e, tagset)
        return {
            **base,
            "status": status,
            "error": f"{type(e).__name__}: {e}",
            "traceback": traceback.format_exc()[-2000:],
        }
    finally:
        signal.alarm(0)
        signal.signal(signal.SIGALRM, old_handler)


def main() -> int:
    REPORTS.mkdir(parents=True, exist_ok=True)
    tags_map = load_tags()
    arm_bins = load_l1_arm_bins()
    rows = inventory()

    only_module = os.environ.get("VAL_MODULE")
    only_key = os.environ.get("VAL_TOOL")
    resume = os.environ.get("VAL_RESUME", "1") != "0"
    partial_path = REPORTS / "l4_tools_partial.json"
    results = []
    done_keys: set[str] = set()
    if resume and partial_path.exists():
        try:
            prev = load_json(partial_path).get("results") or []
            results = list(prev)
            done_keys = {r["key"] for r in results}
            print(f"Resuming with {len(done_keys)} prior results", flush=True)
        except Exception as e:  # noqa: BLE001
            print(f"Resume load failed: {e}", flush=True)

    for row in rows:
        if only_module and row["module"] != only_module:
            continue
        if only_key and row["key"] != only_key:
            continue
        if row["key"] in done_keys:
            continue
        fix_path = FIX / row["module"] / f"{row['name']}.json"
        if fix_path.exists():
            fixture = load_json(fix_path)
        else:
            fixture = {"mode": "import_and_try", "kwargs": {}}
        print(f"L4 {row['key']} …", flush=True)
        res = run_one(row, fixture, arm_bins, tags_map)
        print(f"  -> {res['status']}", flush=True)
        results.append(res)
        done_keys.add(row["key"])
        write_json(partial_path, {"results": results})

    from collections import Counter

    counts = Counter(r["status"] for r in results)
    payload = {
        "layer": "L4",
        "timestamp": stamp(),
        "total": len(results),
        "status_counts": dict(counts),
        "arm_bins_from_l1": sorted(arm_bins),
        "results": results,
    }
    out = REPORTS / "l4_tools.json"
    write_json(out, payload)
    print(json.dumps({"total": len(results), "status_counts": dict(counts)}, indent=2))
    print(f"Wrote {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
