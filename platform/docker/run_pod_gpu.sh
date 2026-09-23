#!/usr/bin/env bash
# CUDA MCP pod: only requires_gpu tools (see platform/mcp/tools_gpu.json).
# Usage: bash platform/docker/run_pod_gpu.sh <ucode> [host_port]
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export BIOMNI_MCP_TOOL_PROFILE=gpu
export DOCKER_GPUS=1
exec bash "${ROOT}/run_pod.sh" "$@"
