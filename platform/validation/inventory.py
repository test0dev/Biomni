#!/usr/bin/env python3
"""Enumerate all Biomni tools from tool_description and verify implementations exist."""

from __future__ import annotations

import importlib
import inspect
import json
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

FIELDS = [
    "literature",
    "biochemistry",
    "bioimaging",
    "bioengineering",
    "biophysics",
    "glycoengineering",
    "cancer_biology",
    "cell_biology",
    "molecular_biology",
    "genetics",
    "genomics",
    "immunology",
    "microbiology",
    "pathology",
    "pharmacology",
    "physiology",
    "synthetic_biology",
    "systems_biology",
    "support_tools",
    "database",
    "lab_automation",
    "protocols",
]

STATUS_CODES = (
    "PASS",
    "FAIL_ARM",
    "FAIL_GPU",
    "FAIL_DEP",
    "FAIL_NET",
    "SKIP_EXTRA_ENV",
    "SKIP_AUTH",
    "FAIL_LOGIC",
    "FAIL_SCHEMA",
    "SKIP",
)


def load_descriptions() -> dict[str, list[dict]]:
    module2api: dict[str, list[dict]] = {}
    for field in FIELDS:
        mod = importlib.import_module(f"biomni.tool.tool_description.{field}")
        module2api[field] = list(mod.description)
    return module2api


def _ast_defined_functions(py_path: Path) -> set[str]:
    """Parse top-level function names from a module file (works even if imports fail)."""
    import ast

    try:
        tree = ast.parse(py_path.read_text(encoding="utf-8", errors="ignore"))
    except SyntaxError:
        return set()
    names: set[str] = set()
    for node in tree.body:
        if isinstance(node, ast.FunctionDef | ast.AsyncFunctionDef):
            names.add(node.name)
    return names


def inventory() -> list[dict]:
    """Return flat list of tool records with schema + impl presence."""
    rows: list[dict] = []
    for field, tools in load_descriptions().items():
        impl_path = REPO_ROOT / "biomni" / "tool" / f"{field}.py"
        ast_funcs = _ast_defined_functions(impl_path) if impl_path.exists() else set()
        try:
            impl_mod = importlib.import_module(f"biomni.tool.{field}")
        except Exception as e:  # noqa: BLE001
            impl_mod = None
            impl_err = f"{type(e).__name__}: {e}"
        else:
            impl_err = None

        for tool in tools:
            name = tool.get("name")
            if not name:
                continue
            record = {
                "module": field,
                "name": name,
                "key": f"{field}.{name}",
                "description": (tool.get("description") or "")[:200],
                "required_parameters": tool.get("required_parameters") or [],
                "optional_parameters": tool.get("optional_parameters") or [],
                "impl_module_ok": impl_mod is not None,
                "impl_module_error": impl_err,
                "impl_exists": False,
                "impl_callable": False,
                "impl_in_source": name in ast_funcs,
                "signature": None,
            }
            if impl_mod is not None:
                fn = getattr(impl_mod, name, None)
                record["impl_exists"] = fn is not None
                record["impl_callable"] = callable(fn)
                if callable(fn):
                    try:
                        record["signature"] = str(inspect.signature(fn))
                    except (TypeError, ValueError):
                        record["signature"] = None
            else:
                # Module import failed (often missing deps) but source may still define the function
                record["impl_exists"] = name in ast_funcs
                record["impl_callable"] = False
            rows.append(record)
    return rows


def main() -> int:
    out_dir = Path(__file__).parent / "reports"
    out_dir.mkdir(parents=True, exist_ok=True)
    rows = inventory()
    missing = [r for r in rows if not r["impl_exists"]]
    summary = {
        "total": len(rows),
        "modules": len({r["module"] for r in rows}),
        "impl_missing": len(missing),
        "missing_keys": [r["key"] for r in missing],
    }
    payload = {"summary": summary, "tools": rows}
    out = out_dir / "inventory.json"
    out.write_text(json.dumps(payload, indent=2, ensure_ascii=False))
    print(json.dumps(summary, indent=2))
    print(f"Wrote {out}")
    return 0 if not missing else 1


if __name__ == "__main__":
    raise SystemExit(main())
