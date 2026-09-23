#!/usr/bin/env bash
# Start a biomni-arm MCP pod: shared lake + per-ucode tmp volume.
# Usage: bash platform/docker/run_pod.sh <ucode> [host_port]
#
# Env:
#   BIOMNI_MCP_TOOL_PROFILE  all|cpu|gpu  (default: all)
#   DOCKER_GPUS              1=--gpus all (default), 0=no GPU devices
# Prefer the wrappers: run_pod_cpu.sh / run_pod_gpu.sh
set -euo pipefail

IMAGE_TAG="${IMAGE_TAG:-biomni-arm:latest}"
PORT_MIN=5000
PORT_MAX=6000
BIOMNI_MCP_TOOL_PROFILE="${BIOMNI_MCP_TOOL_PROFILE:-all}"
DOCKER_GPUS="${DOCKER_GPUS:-1}"

usage() {
  echo "usage: $0 <ucode> [host_port]" >&2
  echo "  ucode: single path segment [A-Za-z0-9_-]+" >&2
  echo "  host_port: optional, ${PORT_MIN}-${PORT_MAX}; default max(used)+1 or ${PORT_MIN}" >&2
  echo "  BIOMNI_MCP_TOOL_PROFILE=${BIOMNI_MCP_TOOL_PROFILE}  DOCKER_GPUS=${DOCKER_GPUS}" >&2
  exit 1
}

[[ $# -ge 1 && $# -le 2 ]] || usage
UCODE="$1"
[[ "${UCODE}" =~ ^[A-Za-z0-9_-]+$ ]] || {
  echo "error: invalid ucode '${UCODE}'" >&2
  exit 1
}

NAME="biomni-${UCODE}"
VOL="biomni-${UCODE}-tmp"

resolve_lake() {
  if [[ -n "${BIOMNI_LAKE_HOST:-}" ]]; then
    echo "${BIOMNI_LAKE_HOST}"
    return
  fi
  if [[ -d /data/lake ]]; then
    echo /data/lake
    return
  fi
  if [[ -d "${HOME}/biomni-data-lake" ]]; then
    echo "${HOME}/biomni-data-lake"
    return
  fi
  echo "error: data lake not found; set BIOMNI_LAKE_HOST or create /data/lake" >&2
  exit 1
}

occupied_ports() {
  docker ps --filter 'name=^biomni-' --format '{{.Ports}}' 2>/dev/null \
    | grep -oE '0\.0\.0\.0:([0-9]+)' \
    | grep -oE '[0-9]+$' \
    | sort -n \
    || true
}

pick_port() {
  local used max=$((PORT_MIN - 1)) p
  used="$(occupied_ports)"
  if [[ -n "${used}" ]]; then
    max="$(echo "${used}" | tail -1)"
  fi
  p=$((max + 1))
  if (( p < PORT_MIN )); then
    p="${PORT_MIN}"
  fi
  if (( p > PORT_MAX )); then
    echo "error: next port ${p} exceeds ${PORT_MAX}" >&2
    exit 1
  fi
  echo "${p}"
}

port_in_use() {
  local p="$1"
  echo "$(occupied_ports)" | grep -qx "${p}"
}

HOST_PORT="${2:-}"
if [[ -z "${HOST_PORT}" ]]; then
  HOST_PORT="$(pick_port)"
else
  [[ "${HOST_PORT}" =~ ^[0-9]+$ ]] || {
    echo "error: host_port must be an integer" >&2
    exit 1
  }
  if (( HOST_PORT < PORT_MIN || HOST_PORT > PORT_MAX )); then
    echo "error: host_port must be in ${PORT_MIN}-${PORT_MAX}" >&2
    exit 1
  fi
  if port_in_use "${HOST_PORT}"; then
    echo "error: host_port ${HOST_PORT} already used by a biomni-* container" >&2
    exit 1
  fi
fi

LAKE_HOST="$(resolve_lake)"
if [[ ! -d "${LAKE_HOST}" ]]; then
  echo "error: lake path is not a directory: ${LAKE_HOST}" >&2
  exit 1
fi

if docker inspect "${NAME}" >/dev/null 2>&1; then
  echo "error: container ${NAME} already exists; stop/rm it first (volume ${VOL} is kept on docker rm)" >&2
  exit 1
fi

docker volume create "${VOL}" >/dev/null

case "${BIOMNI_MCP_TOOL_PROFILE}" in
  all|cpu|gpu) ;;
  *)
    echo "error: BIOMNI_MCP_TOOL_PROFILE must be all|cpu|gpu, got '${BIOMNI_MCP_TOOL_PROFILE}'" >&2
    exit 1
    ;;
esac

GPU_ARGS=()
if [[ "${DOCKER_GPUS}" == "1" ]]; then
  GPU_ARGS=(--gpus all)
fi

echo "starting ${NAME}"
echo "  image:   ${IMAGE_TAG}"
echo "  lake:    ${LAKE_HOST} -> /data (ro)"
echo "  tmp:     volume ${VOL} -> /app/tmp"
echo "  profile: ${BIOMNI_MCP_TOOL_PROFILE}"
echo "  gpus:    ${DOCKER_GPUS} (${GPU_ARGS[*]:-none})"
echo "  publish: 0.0.0.0:${HOST_PORT}->8000"

docker run -d \
  --name "${NAME}" \
  "${GPU_ARGS[@]}" \
  -p "0.0.0.0:${HOST_PORT}:8000" \
  -v "${LAKE_HOST}:/data:ro" \
  -v "${VOL}:/app/tmp" \
  -e MCP_TRANSPORT=http \
  -e MCP_HOST=0.0.0.0 \
  -e MCP_PORT=8000 \
  -e PYTHONUNBUFFERED=1 \
  -e BIOMNI_DATA_LAKE_PATH=/data \
  -e BIOMNI_MCP_DATA_PATH=/app/tmp/mcp_runtime \
  -e BIOMNI_MCP_TOOL_PROFILE="${BIOMNI_MCP_TOOL_PROFILE}" \
  "${IMAGE_TAG}"

echo "ok ${NAME} on 0.0.0.0:${HOST_PORT} (profile=${BIOMNI_MCP_TOOL_PROFILE})"
