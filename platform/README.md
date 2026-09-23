# Biomni platform (additive)

Extra install / validation layer for **linux-arm** and **linux-x86**.  
Does **not** modify upstream `biomni_env/` or `biomni/` files.

## Entry

```bash
cd biomni-arm
bash platform/install.sh
```

`install.sh` uses `uname -s` / `uname -m`:

| OS | Arch | Branch |
|---|---|---|
| Linux | aarch64 / arm64 | `linux-arm` (install + validate here) |
| Linux | x86_64 / amd64 | `linux-x86` (skeleton; not run on arm64 hosts) |
| other | — | error |

Optional override (debug only): `BIOMNI_PLATFORM=linux-arm bash platform/install.sh`

## Prerequisites

- Conda env `biomni_e1` already created from upstream yml (`biomni_env/environment.yml` or `fixed_env.yml`). This layer does not re-run the multi-hour upstream `setup.sh`.
- `jq`, a C/C++ compiler, `cmake` for source builds.
- **linux-arm GPU:** if `torch.cuda` is unavailable, `linux-arm/setup.sh` installs `torch==2.13.0` from the PyTorch `cu130` index (GB10 / CUDA 13).
- Source-build libraries: zlib, OpenBLAS, LAPACK, Boost (installed into the conda env when a tool lists `conda_deps`).

## Source builds and arm64 substitutes

`method: source_build` in `cli_tools_config_linux_aarch64.json` compiles plink2, gcta64, FastTree, and vina. BWA stays on conda unless that install fails.

ADFRsuite (`autosite`, `prepare_receptor`) is not built. On aarch64, `platform/sitecustomize.py` (via `PYTHONPATH` from `setup_path.sh`) replaces `run_autosite` with fpocket + Meeko and updates the exposed description. x86 does not load that replacement.

`FORCE_REBUILD=1 bash platform/install.sh` rebuilds even when a native binary already exists.

## Local / generated (do not treat as upstream)

- `platform/biomni_tools/` — installed CLI symlinks
- `platform/validation/reports/` — validation outputs
- `platform/linux-arm/cli_install_report.json` — per-tool pass/skip record

## CLI configs

Platform-specific files under `configs/` (upstream `cli_tools_config.json` untouched):

- `cli_tools_config_linux_aarch64.json`
- `cli_tools_config_linux_x86_64.json`

## Validation (linux-arm only)

```bash
conda activate biomni_e1
source platform/setup_path.sh   # after install
bash platform/validation/run_all.sh
```

Default layers: L0, L1, L3 (GPU). Set `VAL_RUN_L2=1` / `VAL_RUN_L4=1` for more.

Docker GPU checks are non-blocking when host CUDA works (`VAL_SKIP_DOCKER=1` to skip).

## MCP

Full-tool stdio server for external clients (Mastra, etc.):

```bash
# server (all tools; reuses ~/biomni-data-lake)
source platform/setup_path.sh
python tutorials/examples/expose_biomni_server/run_mcp_server.py

# Node client smoke test
cd platform/mcp && npm install && node verify_mcp.mjs
```

`BIOMNI_DATA_LAKE_PATH` overrides the lake root (default `~/biomni-data-lake`).

`MCP_TRANSPORT=http` (or `streamable-http`) starts FastMCP on `MCP_HOST`/`MCP_PORT` (defaults `0.0.0.0:8000`). Default remains `stdio` for the Node verifier above.

Tool access inventory (static classification of the MCP/`module2api` surface):

- [`platform/mcp/tools_remote.json`](mcp/tools_remote.json) — needs remote HTTP/API/network during execution
- [`platform/mcp/tools_local.json`](mcp/tools_local.json) — local compute and/or local data lake / files
- [`platform/mcp/tools_gpu.json`](mcp/tools_gpu.json) — `requires_gpu` vs CPU-viable tools (used by MCP profiles)

`BIOMNI_MCP_TOOL_PROFILE` filters tools at MCP start: `all` (default), `cpu` (exclude `requires_gpu`), `gpu` (only `requires_gpu`).

## Docker multi-Pod

Image packs `biomni_e1` + this repo into `/app`. Host only mounts the data lake read-only; per-user state is a Docker volume on `/app/tmp`.

```bash
# once: pack env + build (needs conda-pack on the host)
conda-pack -n biomni_e1 -o platform/docker/.cache/biomni_e1.tar.gz \
  --n-threads -1 --ignore-editable-packages --ignore-missing-files
bash platform/docker/build.sh

# lake: prefer /data/lake; otherwise ~/biomni-data-lake (or BIOMNI_LAKE_HOST=...)
# Split across hosts: x86 without GPU tools vs CUDA with GPU-only tools
bash platform/docker/run_pod_cpu.sh userA       # no --gpus; profile=cpu
bash platform/docker/run_pod_gpu.sh userB       # --gpus all; profile=gpu

# Or full tool surface (legacy):
bash platform/docker/run_pod.sh userC           # --gpus all; profile=all
```

Ports are in 5000–6000. Omit the port to take max(used)+1. `run_pod_gpu.sh` / default `run_pod.sh` use `--gpus all` with no CPU/memory caps; `run_pod_cpu.sh` omits GPU devices.
