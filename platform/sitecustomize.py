"""Load arm64 tool overrides when this directory is on PYTHONPATH."""

from __future__ import annotations

import importlib.util
from pathlib import Path

_override = Path(__file__).resolve().parent / "lib" / "arm64_tool_overrides.py"
try:
    spec = importlib.util.spec_from_file_location("arm64_tool_overrides", _override)
    if spec and spec.loader:
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        mod.apply()
except Exception:
    # Biomni may be unavailable during early env setup; ignore.
    pass
