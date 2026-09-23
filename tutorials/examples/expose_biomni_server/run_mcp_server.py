#!/usr/bin/env python3
"""Expose Biomni tools over MCP (stdio or HTTP) for external clients.

Tool profiles (BIOMNI_MCP_TOOL_PROFILE):
  all  — every tool in module2api (default)
  cpu  — exclude requires_gpu tools (x86 / no-GPU hosts)
  gpu  — only requires_gpu tools (CUDA hosts)
"""

from __future__ import annotations

import json
import os
from pathlib import Path

from biomni.agent.a1 import A1

# Official A1 layout: {path}/biomni_data/data_lake
# Reuse the shared host lake at ~/biomni-data-lake via symlink when needed.
REPO_ROOT = Path(__file__).resolve().parents[3]
DEFAULT_LAKE = Path.home() / "biomni-data-lake"
MCP_DATA_ROOT = Path(os.environ.get("BIOMNI_MCP_DATA_PATH", REPO_ROOT / "data" / "mcp_runtime"))
DEFAULT_GPU_TOOLS_JSON = REPO_ROOT / "platform" / "mcp" / "tools_gpu.json"
VALID_PROFILES = frozenset({"all", "cpu", "gpu"})


def ensure_lake_path(data_root: Path, lake_src: Path) -> Path:
    """Return the A1 data_lake dir, linking lake_src into place if needed."""
    data_lake = data_root / "biomni_data" / "data_lake"
    data_lake.parent.mkdir(parents=True, exist_ok=True)

    # Satisfy A1 benchmark presence check without re-downloading benchmark.zip.
    (data_root / "biomni_data" / "benchmark" / "hle").mkdir(parents=True, exist_ok=True)

    if data_lake.is_symlink():
        if data_lake.resolve() != lake_src.resolve():
            data_lake.unlink()
            data_lake.symlink_to(lake_src.resolve())
    elif data_lake.exists():
        # Already a real directory — leave as-is (A1 will skip existing files).
        pass
    else:
        if not lake_src.is_dir():
            raise FileNotFoundError(
                f"Data lake not found at {lake_src}. "
                "Fill it first (e.g. scripts/download_official_lake.sh ~/biomni-data-lake)."
            )
        data_lake.symlink_to(lake_src.resolve())

    return data_lake


def _load_requires_gpu_names(path: Path) -> set[str]:
    data = json.loads(path.read_text(encoding="utf-8"))
    return {entry["name"] for entry in data.get("requires_gpu", []) if entry.get("name")}


def apply_tool_profile(agent: A1, profile: str, gpu_tools_json: Path) -> tuple[int, int, list[str]]:
    """Filter agent.module2api in place. Returns (before, after, gpu_names_sorted)."""
    profile = profile.strip().lower()
    if profile not in VALID_PROFILES:
        raise ValueError(f"BIOMNI_MCP_TOOL_PROFILE must be one of {sorted(VALID_PROFILES)}, got {profile!r}")

    before = sum(len(apis) for apis in agent.module2api.values())
    gpu_names = sorted(_load_requires_gpu_names(gpu_tools_json))
    gpu_set = set(gpu_names)

    if profile == "all":
        return before, before, gpu_names

    filtered: dict[str, list] = {}
    for module_name, tools in agent.module2api.items():
        if profile == "gpu":
            kept = [t for t in tools if t.get("name") in gpu_set]
        else:
            kept = [t for t in tools if t.get("name") not in gpu_set]
        if kept:
            filtered[module_name] = kept

    agent.module2api = filtered
    after = sum(len(apis) for apis in agent.module2api.values())
    return before, after, gpu_names


def _configure_http(mcp) -> None:
    """Bind FastMCP to 0.0.0.0 for container publish (not loopback-only)."""
    from mcp.server.transport_security import TransportSecuritySettings

    host = os.environ.get("MCP_HOST", "0.0.0.0")
    port = int(os.environ.get("MCP_PORT", "8000"))
    mcp.settings.host = host
    mcp.settings.port = port
    # Default FastMCP enables DNS-rebinding guards only for localhost; clear for public bind.
    mcp.settings.transport_security = TransportSecuritySettings(
        enable_dns_rebinding_protection=False
    )


def main() -> None:
    lake_src = Path(os.environ.get("BIOMNI_DATA_LAKE_PATH", DEFAULT_LAKE)).expanduser()
    data_root = MCP_DATA_ROOT.expanduser()
    data_root.mkdir(parents=True, exist_ok=True)
    data_lake = ensure_lake_path(data_root, lake_src)

    profile = os.environ.get("BIOMNI_MCP_TOOL_PROFILE", "all").strip().lower() or "all"
    gpu_tools_json = Path(
        os.environ.get("BIOMNI_MCP_GPU_TOOLS_JSON", str(DEFAULT_GPU_TOOLS_JSON))
    ).expanduser()

    print(f"MCP data root: {data_root}")
    print(f"MCP data lake: {data_lake} -> {data_lake.resolve()}")
    print(f"MCP tool profile: {profile}")

    # Full official A1 init (checks lake; skips files that already exist).
    agent = A1(path=str(data_root))
    before, after, gpu_names = apply_tool_profile(agent, profile, gpu_tools_json)
    if profile != "all":
        print(f"GPU tool list ({len(gpu_names)}): {', '.join(gpu_names)}")
        print(f"Filtered module2api: {before} -> {after} tools")

    mcp = agent.create_mcp_server()

    n_tools = sum(len(apis) for apis in agent.module2api.values())
    transport = os.environ.get("MCP_TRANSPORT", "stdio").strip().lower()
    if transport in ("http", "streamable-http"):
        _configure_http(mcp)
        print(
            f"Starting Biomni MCP server with {n_tools} tools "
            f"on {mcp.settings.host}:{mcp.settings.port} (streamable-http)..."
        )
        mcp.run(transport="streamable-http")
    else:
        print(f"Starting Biomni MCP server with {n_tools} tools (stdio)...")
        mcp.run(transport="stdio")


if __name__ == "__main__":
    main()
