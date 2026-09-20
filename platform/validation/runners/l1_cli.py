#!/usr/bin/env python3
"""L1 CLI architecture gate — scan external binaries for ARM compatibility."""

from __future__ import annotations

import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from common import REPORTS, REPO_ROOT, classify_elf, run_cmd, stamp, which, write_json  # noqa: E402

# Names to look up on PATH and under biomni_tools
BINARIES = [
    "plink2",
    "muscle",
    "iqtree2",
    "iqtree",
    "gcta64",
    "gcta",
    "FastTree",
    "bwa",
    "samtools",
    "bowtie2",
    "macs2",
    "blastn",
    "mafft",
    "bedtools",
    "vina",
    "autosite",
    "prepare_receptor",
    "findMotifsGenome.pl",
    "findMotifs.pl",
    "configureHomer.pl",
]

SMOKE = {
    "plink2": ["--version"],
    "muscle": ["-version"],
    "iqtree2": ["--version"],
    "iqtree": ["--version"],
    "FastTree": ["-help"],
    "bwa": [],
    "samtools": ["--version"],
    "bowtie2": ["--version"],
    "macs2": ["--version"],
    "blastn": ["-version"],
    "mafft": ["--version"],
    "bedtools": ["--version"],
    "vina": ["--version"],
}


def resolve_candidates(name: str) -> list[str]:
    paths: list[str] = []
    # Prefer conda env binaries (often ARM-native) before biomni_tools prebuilts
    conda_prefix = os.environ.get("CONDA_PREFIX")
    if conda_prefix:
        cand = Path(conda_prefix) / "bin" / name
        if cand.exists():
            paths.append(str(cand.resolve()))
    w = which(name)
    if w:
        paths.append(str(Path(w).resolve()))
    tools_bin = REPO_ROOT / "platform" / "biomni_tools" / "bin" / name
    if tools_bin.exists():
        paths.append(str(tools_bin.resolve()))
    tools_bin_legacy = REPO_ROOT / "biomni_env" / "biomni_tools" / "bin" / name
    if tools_bin_legacy.exists():
        paths.append(str(tools_bin_legacy.resolve()))
    for root_name in ("platform/biomni_tools", "biomni_env/biomni_tools"):
        root = REPO_ROOT / root_name
        if root.exists():
            for p in root.rglob(name):
                if p.is_file() or p.is_symlink():
                    try:
                        rp = str(p.resolve())
                    except Exception:  # noqa: BLE001
                        rp = str(p)
                    if p.name == name:
                        paths.append(rp)
    seen = set()
    out = []
    for p in paths:
        if p not in seen:
            seen.add(p)
            out.append(p)
    return out


def main() -> int:
    # Keep conda ahead of biomni_tools so `which` prefers native builds
    tools_bin = REPO_ROOT / "platform" / "biomni_tools" / "bin"
    tools_bin_legacy = REPO_ROOT / "biomni_env" / "biomni_tools" / "bin"
    conda_bin = Path(os.environ["CONDA_PREFIX"]) / "bin" if os.environ.get("CONDA_PREFIX") else None
    path_parts = []
    if conda_bin and conda_bin.exists():
        path_parts.append(str(conda_bin))
    if tools_bin.exists():
        path_parts.append(str(tools_bin))
    if tools_bin_legacy.exists():
        path_parts.append(str(tools_bin_legacy))
    path_parts.append(os.environ.get("PATH", ""))
    os.environ["PATH"] = ":".join(path_parts)

    results = []
    for name in BINARIES:
        cands = resolve_candidates(name)
        if not cands:
            results.append(
                {
                    "name": name,
                    "status": "FAIL_DEP",
                    "note": "not found on PATH or biomni_tools",
                    "paths": [],
                }
            )
            continue

        path_results = []
        statuses = []
        for path in cands:
            info = classify_elf(path)
            smoke = None
            if info["status"] == "PASS" and name in SMOKE:
                smoke = run_cmd([path] + SMOKE[name], timeout=20)
                # bwa with no args returns non-zero but prints usage — treat as runnable
                if name == "bwa":
                    smoke_ok = smoke.get("error") is None
                elif name == "FastTree":
                    smoke_ok = smoke.get("error") is None  # -help may be nonzero
                else:
                    smoke_ok = smoke.get("returncode") == 0 or (
                        smoke.get("stdout") or smoke.get("stderr")
                    )
                if info["runnable_on_host"] and not smoke_ok and smoke.get("error") == "TimeoutExpired":
                    info = dict(info)
                    info["status"] = "FAIL_LOGIC"
                    info["note"] = "smoke timeout"
                elif info["runnable_on_host"] and name not in ("bwa", "FastTree", "gcta64", "gcta"):
                    if smoke.get("returncode") not in (0, None) and not (
                        smoke.get("stdout") or smoke.get("stderr")
                    ):
                        info = dict(info)
                        info["status"] = "FAIL_DEP"
            path_results.append({**info, "smoke": smoke})
            statuses.append(info["status"])

        # If ANY path is runnable aarch64 PASS, treat overall as PASS (conda ARM
        # may coexist with broken x86 copies under biomni_tools/bin).
        if any(p.get("status") == "PASS" and p.get("runnable_on_host") for p in path_results):
            status = "PASS"
        elif "FAIL_ARM" in statuses and not any(p.get("status") == "PASS" for p in path_results):
            status = "FAIL_ARM"
        elif any(s.startswith("FAIL") for s in statuses):
            status = next(s for s in statuses if s.startswith("FAIL"))
        else:
            status = "PASS"

        results.append(
            {
                "name": name,
                "status": status,
                "paths": path_results,
                "preferred": next(
                    (p["path"] for p in path_results if p.get("status") == "PASS"),
                    cands[0],
                ),
            }
        )

    arm_fail = [r for r in results if r["status"] == "FAIL_ARM"]
    payload = {
        "layer": "L1",
        "timestamp": stamp(),
        "overall": "PASS" if not arm_fail else "FAIL_ARM",
        "arm_incompatible": [r["name"] for r in arm_fail],
        "results": results,
    }
    out = REPORTS / "l1_cli.json"
    write_json(out, payload)
    print(f"L1 overall={payload['overall']} arm_incompatible={payload['arm_incompatible']}")
    for r in results:
        print(f"  [{r['status']}] {r['name']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
