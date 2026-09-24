# Biomni platform (additive)

Extra install / validation layer for **linux-arm**, **linux-x86**, and **macos-arm**.  
Does **not** modify upstream `biomni_env/` or `biomni/` files.

## Entry

```bash
cd biomni-arm
bash platform/install.sh
```

`install.sh` uses `uname -s` / `uname -m` (host wins; no cross-arch gates):

| OS | Arch | Branch |
|---|---|---|
| Linux | aarch64 / arm64 | `linux-arm` |
| Linux | x86_64 / amd64 | `linux-x86` |
| Darwin | arm64 | `macos-arm` (native; Docker pods still use `linux/arm64` images) |
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

Conda / `biomni_e1` live **inside Docker** (base image). The host only needs Docker, downloads the **data lake**, and runs pods.

| Image | Dockerfile | Contents |
|-------|------------|----------|
| `biomni-base:latest` | `platform/docker/Dockerfile.base` | Miniconda + `biomni_e1` + `platform/install.sh` |
| `biomni-arm:latest` | `platform/docker/Dockerfile` | FROM base + app code + MCP entrypoint |

Host **does not** need conda or `biomni_e1.tar.gz`. Data lake stays on the host and is mounted read-only at runtime.

**Packaging follows the host** (`uname -s` / `uname -m`), with no mismatch gates:

| Host | `docker --platform` | In-image `BIOMNI_PLATFORM` |
|------|---------------------|----------------------------|
| Linux x86_64 | `linux/amd64` | `linux-x86` |
| Linux aarch64 / arm64 | `linux/arm64` | `linux-arm` |
| macOS arm64 | `linux/arm64` | `linux-arm` (container is Linux) |

`BUILD_PROFILE` (`*-gpu` / `*-cpu`) is derived from host GPU detection (`BIOMNI_FORCE_CPU=1` forces CPU). Do not use it to select architecture.

### One-shot bootstrap (recommended)

```bash
bash bootstrap_docker.sh
```

It will:

1. Detect **host OS/arch** / **GPU** → packaging target + `BUILD_PROFILE` (`*-gpu` / `*-cpu`)
2. Ensure host **Docker** (and apt helpers); never installs host conda
3. Download **data_lake** on the host (`platform/scripts/ensure_data_lake.sh`)
4. Build `biomni-base` then `biomni-arm` via `platform/docker/build.sh` (first base build can take hours)
5. Print `run_pod_*` commands — **does not start pods**

Useful env vars: `AUTO_DOWNLOAD_LAKE` (default `1`), `SKIP_LAKE=1`, `SKIP_DOCKER_BUILD=1`, `SKIP_BASE_BUILD=1`, `SKIP_DISK_CHECK=1`, `BIOMNI_FORCE_CPU=1`, `IMAGE_TAG`, `BIOMNI_BASE_TAG`.

Lake-only: `bash platform/scripts/ensure_data_lake.sh` (or `--probe`).

### Run pods (you start them)

```bash
# lake: BIOMNI_LAKE_HOST or /data/lake or ~/biomni-data-lake
BIOMNI_LAKE_HOST=/path/to/lake bash platform/docker/run_pod_cpu.sh userA
BIOMNI_LAKE_HOST=/path/to/lake bash platform/docker/run_pod_gpu.sh userB

# Or full tool surface:
bash platform/docker/run_pod.sh userC
```

Ports are in 5000–6000. Omit the port to take max(used)+1. `run_pod_gpu.sh` / default `run_pod.sh` use `--gpus all`; `run_pod_cpu.sh` omits GPU devices.

Rebuild images only (always packs for **this** host):

```bash
bash platform/docker/build.sh
# force CPU torch policy: BIOMNI_FORCE_CPU=1 bash platform/docker/build.sh
# runtime only: SKIP_BASE_BUILD=1 bash platform/docker/build.sh
```
