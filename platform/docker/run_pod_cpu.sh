#!/usr/bin/env bash
# x86 / no-GPU MCP pod: all tools except requires_gpu (see platform/mcp/tools_gpu.json).
# Usage: bash platform/docker/run_pod_cpu.sh <ucode> [host_port]
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export BIOMNI_MCP_TOOL_PROFILE=cpu
export DOCKER_GPUS=0
exec bash "${ROOT}/run_pod.sh" "$@"
