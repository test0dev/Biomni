#!/usr/bin/env python3
"""Aggregate L0–L4 reports into final JSON + Markdown."""

from __future__ import annotations

import json
import sys
from collections import Counter
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from common import REPORTS, host_info, load_json, stamp, write_json  # noqa: E402


def load_layer(name: str):
    p = REPORTS / name
    if not p.exists():
        return None
    return load_json(p)


def main() -> int:
    l0 = load_layer("l0_env.json")
    l1 = load_layer("l1_cli.json")
    l2 = load_layer("l2_imports.json")
    l3 = load_layer("l3_gpu.json")
    l4 = load_layer("l4_tools.json")
    inv = load_layer("inventory.json")

    arm_cli = (l1 or {}).get("arm_incompatible") or []
    l4_results = (l4 or {}).get("results") or []
    arm_tools = [r for r in l4_results if r.get("status") == "FAIL_ARM"]
    gpu_tools = [r for r in l4_results if r.get("status") == "FAIL_GPU"]
    counts = Counter(r.get("status") for r in l4_results)

    summary = {
        "timestamp": stamp(),
        "host": host_info(),
        "l0_overall": (l0 or {}).get("overall"),
        "l1_overall": (l1 or {}).get("overall"),
        "l1_arm_incompatible_binaries": arm_cli,
        "l2_overall": (l2 or {}).get("overall"),
        "l2_fail_count": (l2 or {}).get("fail_count"),
        "l3_overall": (l3 or {}).get("overall"),
        "l3_verdict": (l3 or {}).get("verdict"),
        "l4_total": (l4 or {}).get("total") or len(l4_results),
        "l4_status_counts": dict(counts),
        "inventory_total": (inv or {}).get("summary", {}).get("total"),
        "arm_fail_tools": [{"key": r["key"], "error": r.get("error")} for r in arm_tools],
        "gpu_fail_tools": [{"key": r["key"], "error": r.get("error")} for r in gpu_tools],
    }

    out_json = REPORTS / f"validation_{stamp()}.json"
    write_json(
        out_json,
        {
            "summary": summary,
            "l0": l0,
            "l1": l1,
            "l2": l2,
            "l3": l3,
            "l4": l4,
        },
    )
    # also stable name
    write_json(REPORTS / "validation_latest.json", {"summary": summary})

    # Markdown
    lines = []
    lines.append("# Biomni ARM + GPU 全量 Tools 验证报告")
    lines.append("")
    lines.append(f"- 时间: `{summary['timestamp']}`")
    lines.append(f"- 架构: `{summary['host'].get('machine')}`")
    lines.append(f"- 平台: `{summary['host'].get('platform')}`")
    lines.append(f"- Conda: `{summary['host'].get('conda_default_env')}`")
    lines.append("")
    lines.append("## 总览")
    lines.append("")
    lines.append(f"| 层 | 结果 |")
    lines.append(f"|---|---|")
    lines.append(f"| L0 环境 | {summary['l0_overall']} |")
    lines.append(f"| L1 CLI 架构 | {summary['l1_overall']} |")
    lines.append(f"| L2 Import | {summary['l2_overall']} (fail={summary['l2_fail_count']}) |")
    lines.append(f"| L3 GPU | {summary['l3_overall']} — **{summary['l3_verdict']}** |")
    lines.append(f"| L4 Tools | {summary['l4_total']} tools |")
    lines.append("")
    lines.append("### L4 状态计数")
    lines.append("")
    for k, v in sorted(counts.items()):
        lines.append(f"- `{k}`: {v}")
    lines.append("")

    lines.append("## 1. ARM 不可用")
    lines.append("")
    lines.append("### 二进制 (L1)")
    lines.append("")
    if arm_cli:
        for b in arm_cli:
            lines.append(f"- `{b}`")
    else:
        lines.append("- （无，或 L1 未运行）")
    lines.append("")
    lines.append("### Tools (L4 FAIL_ARM)")
    lines.append("")
    if arm_tools:
        for r in arm_tools:
            lines.append(f"- `{r['key']}`: {r.get('error')}")
    else:
        lines.append("- （无）")
    lines.append("")

    lines.append("## 2. GPU 结论")
    lines.append("")
    lines.append(f"**{(l3 or {}).get('verdict', '未知')}** (overall={summary['l3_overall']})")
    lines.append("")
    if l3 and l3.get("checks"):
        for c in l3["checks"]:
            lines.append(f"- [{c['status']}] `{c['name']}`")
    lines.append("")
    lines.append("### GPU 相关 tool 失败 (FAIL_GPU)")
    lines.append("")
    if gpu_tools:
        for r in gpu_tools:
            lines.append(f"- `{r['key']}`: {r.get('error')}")
    else:
        lines.append("- （无）")
    lines.append("")

    lines.append("## 3. 全量矩阵 (module.tool → status)")
    lines.append("")
    lines.append("| Tool | Status | Error |")
    lines.append("|---|---|---|")
    for r in sorted(l4_results, key=lambda x: x.get("key", "")):
        err = (r.get("error") or "").replace("|", "\\|").replace("\n", " ")
        if len(err) > 120:
            err = err[:120] + "…"
        lines.append(f"| `{r.get('key')}` | `{r.get('status')}` | {err} |")
    lines.append("")

    # Import failures
    lines.append("## 附录: L2 失败包")
    lines.append("")
    if l2:
        for r in l2.get("results") or []:
            if r.get("status") != "PASS":
                lines.append(f"- `{r['name']}`: {r.get('error')}")
    lines.append("")

    md_path = REPORTS / f"validation_{stamp()}.md"
    md_path.write_text("\n".join(lines), encoding="utf-8")
    latest_md = REPORTS / "validation_latest.md"
    latest_md.write_text("\n".join(lines), encoding="utf-8")
    print(f"Wrote {out_json}")
    print(f"Wrote {md_path}")
    print(f"Wrote {latest_md}")
    print(json.dumps(summary["l4_status_counts"], indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
