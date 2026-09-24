#!/usr/bin/env bash
# Unified host bootstrap: probe arch/GPU/lake → init env → platform install →
# conda-pack → call existing platform/docker/build.sh (unchanged).
#
# Usage:
#   bash bootstrap_docker.sh
#
# Env (optional):
#   AUTO_DOWNLOAD_LAKE=1|0   default 1
#   FORCE_REPACK=1           rebuild biomni_e1.tar.gz
#   SKIP_ENV_SETUP=1         require existing biomni_e1
#   SKIP_PLATFORM_INSTALL=1
#   SKIP_DOCKER_BUILD=1      pack only
#   SKIP_DISK_CHECK=1
#   SKIP_LAKE=1              skip lake probe/download
#   IMAGE_TAG=biomni-arm:latest
#   BIOMNI_DATA_LAKE_PATH / BIOMNI_LAKE_HOST
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${REPO_ROOT}"

ENV_NAME="${BIOMNI_ENV_NAME:-biomni_e1}"
CACHE_DIR="${REPO_ROOT}/platform/docker/.cache"
PACK_TGZ="${CACHE_DIR}/biomni_e1.tar.gz"
IMAGE_TAG="${IMAGE_TAG:-biomni-arm:latest}"
AUTO_DOWNLOAD_LAKE="${AUTO_DOWNLOAD_LAKE:-1}"
export AUTO_DOWNLOAD_LAKE
export NON_INTERACTIVE=1

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

# --- detect ---
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
  case "${HOST_ARCH}:${HOST_GPU}" in
    arm64:yes)   echo arm64-gpu ;;
    arm64:no)    echo arm64-cpu ;;
    x86_64:yes)  echo x86_64-gpu ;;
    x86_64:no)   echo x86_64-cpu ;;
    *) die "cannot select init profile for ${HOST_ARCH}/${HOST_GPU}" ;;
  esac
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
  local out
  out="$(bash "${REPO_ROOT}/platform/scripts/ensure_data_lake.sh" 2>/tmp/biomni_lake_probe.err || true)"
  # shellcheck disable=SC2086
  eval "$(echo "${out}" | grep -E '^LAKE_(PATH|STATUS|HAVE|EXPECTED|MISSING)=')"
  if [[ -s /tmp/biomni_lake_probe.err ]]; then
    cat /tmp/biomni_lake_probe.err >&2 || true
  fi
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
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

ensure_conda_hook() {
  if command -v conda >/dev/null 2>&1; then
    # shellcheck disable=SC1091
    eval "$(conda shell.bash hook)"
    return
  fi
  if [[ -f "${HOME}/miniconda3/etc/profile.d/conda.sh" ]]; then
    # shellcheck disable=SC1091
    source "${HOME}/miniconda3/etc/profile.d/conda.sh"
    return
  fi
  if [[ -f "${HOME}/anaconda3/etc/profile.d/conda.sh" ]]; then
    # shellcheck disable=SC1091
    source "${HOME}/anaconda3/etc/profile.d/conda.sh"
    return
  fi
  if command -v micromamba >/dev/null 2>&1; then
    # shellcheck disable=SC2139
    conda() { micromamba "$@"; }
    export -f conda
    return
  fi
  die "conda/micromamba not found"
}

env_exists() {
  conda env list 2>/dev/null | grep -qE "^${ENV_NAME}[[:space:]]"
}

ensure_biomni_env() {
  if env_exists; then
    log_ok "reuse conda env: ${ENV_NAME}"
    return
  fi
  if [[ "${SKIP_ENV_SETUP:-0}" == "1" ]]; then
    die "conda env ${ENV_NAME} missing and SKIP_ENV_SETUP=1"
  fi
  log_info "creating ${ENV_NAME} via biomni_env/setup.sh (NON_INTERACTIVE=1; may take hours)"
  (
    cd "${REPO_ROOT}/biomni_env"
    NON_INTERACTIVE=1 bash setup.sh
  )
  env_exists || die "biomni_env/setup.sh finished but env ${ENV_NAME} still missing"
}

activate_biomni() {
  ensure_conda_hook
  conda activate "${ENV_NAME}"
  export PATH="${CONDA_PREFIX}/bin:${PATH}"
  log_ok "activated ${ENV_NAME} (${CONDA_PREFIX})"
}

ensure_x86_cuda_torch() {
  [[ "${HOST_GPU}" == "yes" ]] || return 0
  if python - <<'PY'
import torch, sys
ok = torch.cuda.is_available() and bool(getattr(torch.version, "cuda", None))
sys.exit(0 if ok else 1)
PY
  then
    log_ok "torch CUDA already available"
    return
  fi
  log_info "attempting CUDA torch install for x86_64 (best-effort)"
  if pip install --upgrade 'torch' --index-url https://download.pytorch.org/whl/cu124; then
    python - <<'PY' || log_warn "torch installed but cuda still unavailable"
import torch
print(f"torch {torch.__version__} cuda={torch.version.cuda} available={torch.cuda.is_available()}")
PY
  else
    log_warn "CUDA torch install failed; continuing with CPU torch"
  fi
}

run_platform_install() {
  if [[ "${SKIP_PLATFORM_INSTALL:-0}" == "1" ]]; then
    log_warn "SKIP_PLATFORM_INSTALL=1"
    return
  fi
  case "${INIT_PROFILE}" in
    arm64-cpu)
      export BIOMNI_SKIP_CUDA_TORCH=1
      log_info "arm64-cpu: BIOMNI_SKIP_CUDA_TORCH=1"
      ;;
    arm64-gpu)
      unset BIOMNI_SKIP_CUDA_TORCH || true
      ;;
    x86_64-*)
      unset BIOMNI_SKIP_CUDA_TORCH || true
      ;;
  esac
  log_info "running platform/install.sh"
  bash "${REPO_ROOT}/platform/install.sh"
  if [[ "${INIT_PROFILE}" == "x86_64-gpu" ]]; then
    activate_biomni
    ensure_x86_cuda_torch
  fi
}

ensure_conda_pack_tool() {
  activate_biomni
  if python -c "import conda_pack" 2>/dev/null; then
    log_ok "conda-pack available"
    return
  fi
  log_info "installing conda-pack"
  pip install conda-pack || conda install -y -c conda-forge conda-pack
  python -c "import conda_pack" || die "conda-pack install failed"
}

run_conda_pack() {
  mkdir -p "${CACHE_DIR}"
  if [[ -f "${PACK_TGZ}" && "${FORCE_REPACK:-0}" != "1" ]]; then
    log_ok "reuse existing pack: ${PACK_TGZ}"
    return
  fi
  ensure_conda_pack_tool
  log_info "conda-pack → ${PACK_TGZ}"
  # Prefer conda run so the packager runs with the env on PATH without keeping it active.
  conda run -n "${ENV_NAME}" conda-pack -n "${ENV_NAME}" -o "${PACK_TGZ}" \
    --n-threads -1 \
    --ignore-editable-packages \
    --ignore-missing-files
  [[ -f "${PACK_TGZ}" ]] || die "conda-pack did not produce ${PACK_TGZ}"
  log_ok "packed $(du -h "${PACK_TGZ}" | awk '{print $1}')"
}

run_docker_build() {
  if [[ "${SKIP_DOCKER_BUILD:-0}" == "1" ]]; then
    log_warn "SKIP_DOCKER_BUILD=1 — skipping docker build"
    return
  fi
  [[ -f "${PACK_TGZ}" ]] || die "missing ${PACK_TGZ}; pack step failed"
  log_info "calling platform/docker/build.sh (IMAGE_TAG=${IMAGE_TAG})"
  IMAGE_TAG="${IMAGE_TAG}" bash "${REPO_ROOT}/platform/docker/build.sh"
}

print_result_tips() {
  echo
  echo "=== Bootstrap result ==="
  echo "  INIT_PROFILE: ${INIT_PROFILE}"
  echo "  arch:         ${HOST_ARCH}"
  echo "  gpu:          $(gpu_label)"
  echo "  lake:         ${LAKE_PATH:-n/a}  status=${LAKE_STATUS} (${LAKE_HAVE}/${LAKE_EXPECTED})"
  echo "  pack:         ${PACK_TGZ}"
  if [[ "${SKIP_DOCKER_BUILD:-0}" == "1" ]]; then
    echo "  image:        (skipped)"
  else
    echo "  image:        ${IMAGE_TAG}"
  fi
  echo
  echo "Next steps:"
  if [[ "${HOST_GPU}" == "yes" ]]; then
    echo "  # This GPU host — GPU-only MCP tools:"
    echo "  BIOMNI_LAKE_HOST=${LAKE_PATH:-/path/to/lake} bash platform/docker/run_pod_gpu.sh <ucode>"
    echo "  # On a CPU-only sibling host (after bootstrap there):"
    echo "  BIOMNI_LAKE_HOST=${LAKE_PATH:-/path/to/lake} bash platform/docker/run_pod_cpu.sh <ucode>"
  else
    echo "  # This host has no GPU — CPU MCP profile only (8 requires_gpu tools unavailable):"
    echo "  BIOMNI_LAKE_HOST=${LAKE_PATH:-/path/to/lake} bash platform/docker/run_pod_cpu.sh <ucode>"
  fi
  if [[ "${LAKE_STATUS}" != "ok" && "${LAKE_STATUS}" != "skipped" ]]; then
    echo
    echo -e "${YELLOW}  WARNING: data lake status=${LAKE_STATUS}.${NC}"
    echo "  run_pod_* will fail until the lake is ready. Retry:"
    echo "  AUTO_DOWNLOAD_LAKE=1 bash platform/scripts/ensure_data_lake.sh"
  else
    echo
    echo "  Lake mount tip: BIOMNI_LAKE_HOST=${LAKE_PATH}"
  fi
}

# --- main ---
HOST_ARCH="$(detect_arch)"
HOST_GPU="$(detect_gpu)"
INIT_PROFILE="$(select_profile)"

echo "=== Host profile ==="
echo "  arch:  $(uname -m) (${HOST_ARCH})"
echo "  gpu:   $(gpu_label)"
echo "  init:  ${INIT_PROFILE}"

require_cmd bash
require_cmd rsync
require_cmd docker
docker info >/dev/null 2>&1 || die "docker daemon not reachable (docker info failed)"
check_disk
ensure_conda_hook

probe_lake
echo "  lake:  ${LAKE_PATH:-n/a}  status=${LAKE_STATUS} (${LAKE_HAVE}/${LAKE_EXPECTED})"
echo

ensure_biomni_env
activate_biomni
run_platform_install
run_conda_pack
run_docker_build
print_result_tips
log_ok "bootstrap_docker.sh finished"
