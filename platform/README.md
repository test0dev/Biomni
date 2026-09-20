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

See `mcp/cursor.mcp.json.example` — points at upstream  
`tutorials/examples/expose_biomni_server/run_mcp_server.py`.
