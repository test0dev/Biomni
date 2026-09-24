#!/usr/bin/env bash
# Host bootstrap for Biomni MCP Docker images.
# - Ensures Docker (+ apt helpers); does NOT install host conda
# - Downloads data_lake on the host
# - Builds base + runtime images via platform/docker/build.sh
# - Does NOT start pods (you run run_pod_cpu.sh / run_pod_gpu.sh yourself)
#
# Usage:
#   bash bootstrap_docker.sh
#
# Env:
#   AUTO_DOWNLOAD_LAKE=1|0   default 1
#   SKIP_DISK_CHECK=1
#   SKIP_LAKE=1
#   SKIP_DOCKER_BUILD=1
#   SKIP_BASE_BUILD=1        passed to build.sh
#   BIOMNI_FORCE_CPU=1       force *-cpu profile (arch still from host)
#   IMAGE_TAG / BIOMNI_BASE_TAG
#   BIOMNI_DATA_LAKE_PATH / BIOMNI_LAKE_HOST
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${REPO_ROOT}"

IMAGE_TAG="${IMAGE_TAG:-biomni-arm:latest}"
BIOMNI_BASE_TAG="${BIOMNI_BASE_TAG:-biomni-base:latest}"
AUTO_DOWNLOAD_LAKE="${AUTO_DOWNLOAD_LAKE:-1}"
export AUTO_DOWNLOAD_LAKE

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()  { echo -e "${BLUE}[info]${NC} $*"; }
log_ok()    { echo -e "${GREEN}[ok]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[warn]${NC} $*"; }
log_err()   { echo -e "${RED}[error]${NC} $*" >&2; }
die()       { log_err "$*"; exit 1; }

detect_host_kind() {
  case "$(uname -s):$(uname -m)" in
    Linux:x86_64 | Linux:amd64) echo linux-x86 ;;
    Linux:aarch64 | Linux:arm64) echo linux-arm ;;
    Darwin:arm64 | Darwin:aarch64) echo macos-arm ;;
    *) die "unsupported host $(uname -s)/$(uname -m) (need Linux x86_64, Linux arm64, or macOS arm64)" ;;
  esac
}

detect_arch() {
  case "$(uname -m)" in
    aarch64 | arm64) echo arm64 ;;
    x86_64 | amd64)  echo x86_64 ;;
    *) die "unsupported arch: $(uname -m) (need arm64 or x86_64)" ;;
  esac
}

detect_gpu() {
  if command -v nvidia-smi >/dev/null 2>&1; then
    if nvidia-smi -L 2>/dev/null | grep -qi 'GPU'; then
      echo yes
      return
    fi
  fi
  echo no
}

gpu_label() {
  if [[ "${HOST_GPU}" != "yes" ]]; then
    echo "no"
    return
  fi
  local line
  line="$(nvidia-smi -L 2>/dev/null | head -1 || true)"
  if [[ -n "${line}" ]]; then
    echo "yes (${line})"
  else
    echo "yes"
  fi
}

select_profile() {
  # Arch always from host; GPU/CPU only.
  if [[ "${BIOMNI_FORCE_CPU:-0}" == "1" || "${HOST_GPU}" != "yes" ]]; then
    echo "${HOST_ARCH}-cpu"
  else
    echo "${HOST_ARCH}-gpu"
  fi
}

check_disk() {
  if [[ "${SKIP_DISK_CHECK:-0}" == "1" ]]; then
    return
  fi
  local avail
  avail="$(df -BG --output=avail "${REPO_ROOT}" 2>/dev/null | tail -1 | tr -dc '0-9' || echo 0)"
  if [[ -z "${avail}" || "${avail}" -lt 40 ]]; then
    die "need >=40GB free on ${REPO_ROOT} (have ${avail:-?}GB); set SKIP_DISK_CHECK=1 to override"
  fi
  log_ok "disk free: ${avail}GB"
}

probe_lake() {
  LAKE_PATH=""
  LAKE_STATUS=missing
  LAKE_HAVE=0
  LAKE_EXPECTED=0
  LAKE_MISSING=0
  if [[ "${SKIP_LAKE:-0}" == "1" ]]; then
    LAKE_STATUS=skipped
    return
  fi
  local out err
  err="$(mktemp)"
  out="$(bash "${REPO_ROOT}/platform/scripts/ensure_data_lake.sh" 2>"${err}" || true)"
  eval "$(echo "${out}" | grep -E '^LAKE_(PATH|STATUS|HAVE|EXPECTED|MISSING)=')" || true
  if [[ -s "${err}" ]]; then
    cat "${err}" >&2 || true
  fi
  rm -f "${err}"
}

print_result_tips() {
  echo
  echo "=== Bootstrap result ==="
  echo "  host kind:     ${HOST_KIND}"
  echo "  BUILD_PROFILE: ${BUILD_PROFILE}"
  echo "  arch:          ${HOST_ARCH}"
  echo "  gpu:           $(gpu_label)"
  echo "  lake:          ${LAKE_PATH:-n/a}  status=${LAKE_STATUS} (${LAKE_HAVE}/${LAKE_EXPECTED})"
  echo "  base image:    ${BIOMNI_BASE_TAG}"
  echo "  runtime image: ${IMAGE_TAG}"
  echo
  echo "Start a pod yourself (not started by this script):"
  if [[ "${HOST_GPU}" == "yes" ]]; then
    echo "  BIOMNI_LAKE_HOST=${LAKE_PATH:-/path/to/lake} bash platform/docker/run_pod_gpu.sh <ucode>"
    echo "  # or CPU-only tools on this host:"
    echo "  BIOMNI_LAKE_HOST=${LAKE_PATH:-/path/to/lake} bash platform/docker/run_pod_cpu.sh <ucode>"
  else
    echo "  BIOMNI_LAKE_HOST=${LAKE_PATH:-/path/to/lake} bash platform/docker/run_pod_cpu.sh <ucode>"
  fi
  if [[ "${LAKE_STATUS}" != "ok" && "${LAKE_STATUS}" != "skipped" ]]; then
    echo
    echo -e "${YELLOW}  WARNING: data lake status=${LAKE_STATUS} — fix before run_pod_*${NC}"
    echo "  AUTO_DOWNLOAD_LAKE=1 bash platform/scripts/ensure_data_lake.sh"
  fi
}

# --- main ---
HOST_KIND="$(detect_host_kind)"
HOST_ARCH="$(detect_arch)"
HOST_GPU="$(detect_gpu)"
BUILD_PROFILE="$(select_profile)"

echo "=== Host profile ==="
echo "  kind:  ${HOST_KIND}"
echo "  arch:  $(uname -m) (${HOST_ARCH})"
echo "  gpu:   $(gpu_label)"
echo "  build: ${BUILD_PROFILE} (arch from host; GPU/CPU only)"

check_disk

# shellcheck disable=SC1091
source "${REPO_ROOT}/platform/scripts/ensure_host_deps.sh"
ensure_host_deps "${HOST_GPU}"

probe_lake
echo "  lake:  ${LAKE_PATH:-n/a}  status=${LAKE_STATUS} (${LAKE_HAVE}/${LAKE_EXPECTED})"
echo

if [[ "${SKIP_DOCKER_BUILD:-0}" == "1" ]]; then
  log_warn "SKIP_DOCKER_BUILD=1 — skipping image build"
else
  log_info "building images for host ${HOST_KIND} (conda/E1 inside Docker base — may take hours on first run)"
  IMAGE_TAG="${IMAGE_TAG}" \
    BIOMNI_BASE_TAG="${BIOMNI_BASE_TAG}" \
    BIOMNI_FORCE_CPU="${BIOMNI_FORCE_CPU:-0}" \
    SKIP_BASE_BUILD="${SKIP_BASE_BUILD:-0}" \
    bash "${REPO_ROOT}/platform/docker/build.sh"
fi

print_result_tips
log_ok "bootstrap_docker.sh finished (start pods manually)"
