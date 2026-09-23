#!/usr/bin/env bash
# Container entry: prepare /app/tmp layout, then start MCP (HTTP by default).
set -euo pipefail

APP_ROOT="${APP_ROOT:-/app}"
TMP_ROOT="${TMP_ROOT:-/app/tmp}"

mkdir -p \
  "${TMP_ROOT}/home" \
  "${TMP_ROOT}/cache" \
  "${TMP_ROOT}/mcp_runtime" \
  "${TMP_ROOT}/tmp"

export HOME="${TMP_ROOT}/home"
export TMPDIR="${TMP_ROOT}/tmp"
export XDG_CACHE_HOME="${TMP_ROOT}/cache"
export BIOMNI_MCP_DATA_PATH="${BIOMNI_MCP_DATA_PATH:-${TMP_ROOT}/mcp_runtime}"
export BIOMNI_DATA_LAKE_PATH="${BIOMNI_DATA_LAKE_PATH:-/data}"
export MCP_TRANSPORT="${MCP_TRANSPORT:-http}"
export MCP_HOST="${MCP_HOST:-0.0.0.0}"
export MCP_PORT="${MCP_PORT:-8000}"
export PYTHONPATH="${APP_ROOT}/platform:${APP_ROOT}${PYTHONPATH:+:${PYTHONPATH}}"
export PATH="${CONDA_PREFIX:-/opt/conda/envs/biomni_e1}/bin:${APP_ROOT}/platform/biomni_tools/bin:${PATH}"

# A1 constructs an LLM client at init; MCP tool calls do not use it.
export ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY:-sk-ant-placeholder-for-mcp-init}"

cd "${APP_ROOT}"

if [[ ! -d "${BIOMNI_DATA_LAKE_PATH}" ]]; then
  echo "error: data lake not mounted at ${BIOMNI_DATA_LAKE_PATH}" >&2
  exit 1
fi

exec python "${APP_ROOT}/tutorials/examples/expose_biomni_server/run_mcp_server.py"
