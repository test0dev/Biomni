#!/usr/bin/env bash
# Ensure host packages needed to *build* images and download the data lake.
# Does NOT install conda (conda lives in the Docker base image).
#
# Usage: source from bootstrap_docker.sh, or:
#   bash platform/scripts/ensure_host_deps.sh
set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

_log_info()  { echo -e "${BLUE}[check]${NC} $*"; }
_log_ok()    { echo -e "${GREEN}[ok]${NC} $*"; }
_log_warn()  { echo -e "${YELLOW}[warn]${NC} $*"; }
_log_err()   { echo -e "${RED}[error]${NC} $*" >&2; }
_die()       { _log_err "$*"; exit 1; }

_is_root() { [[ "$(id -u)" -eq 0 ]]; }
_have_apt() { command -v apt-get >/dev/null 2>&1; }

ensure_apt_packages() {
  local need=() 
  command -v curl >/dev/null 2>&1 || need+=(curl)
  command -v rsync >/dev/null 2>&1 || need+=(rsync)
  if [[ ${#need[@]} -eq 0 ]]; then
    _log_ok "curl rsync present"
    return
  fi
  if ! _have_apt; then
    _die "missing: ${need[*]}; install manually (no apt-get on this host)"
  fi
  if ! _is_root; then
    _die "missing: ${need[*]}; re-run as root or install manually"
  fi
  _log_info "apt-get install -y ${need[*]} ca-certificates"
  apt-get update -y
  apt-get install -y --no-install-recommends "${need[@]}" ca-certificates
  _log_ok "apt packages installed"
}

ensure_docker() {
  if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    _log_ok "docker available"
    return
  fi
  if command -v docker >/dev/null 2>&1; then
    _die "docker CLI found but daemon not reachable (docker info failed)"
  fi
  if ! _is_root; then
    _die "docker not installed; install Docker or re-run as root to auto-install"
  fi
  _log_info "installing Docker via get.docker.com"
  curl -fsSL https://get.docker.com | sh
  if command -v systemctl >/dev/null 2>&1; then
    systemctl enable --now docker || true
  fi
  docker info >/dev/null 2>&1 || _die "docker installed but daemon still unreachable"
  _log_ok "docker installed"
}

ensure_nvidia_container_toolkit() {
  local want_gpu="${1:-no}"
  [[ "${want_gpu}" == "yes" ]] || return 0

  if docker run --rm --gpus all nvidia/cuda:12.6.0-base-ubuntu22.04 nvidia-smi >/dev/null 2>&1; then
    _log_ok "docker --gpus works"
    return
  fi

  _log_warn "GPU host but docker --gpus failed; attempting nvidia-container-toolkit (best-effort)"
  if ! _is_root || ! _have_apt; then
    _log_warn "install nvidia-container-toolkit before run_pod_gpu.sh"
    return 0
  fi

  if curl -fsSL "https://nvidia.github.io/libnvidia-container/gpgkey" \
    | gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg 2>/dev/null; then
    local distribution
    distribution="$(. /etc/os-release; echo "${ID}${VERSION_ID}")"
    curl -fsSL "https://nvidia.github.io/libnvidia-container/${distribution}/libnvidia-container.list" \
      | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
      > /etc/apt/sources.list.d/nvidia-container-toolkit.list || true
    apt-get update -y || true
    apt-get install -y nvidia-container-toolkit || true
    nvidia-ctk runtime configure --runtime=docker 2>/dev/null || true
    systemctl restart docker 2>/dev/null || true
  fi

  if docker run --rm --gpus all nvidia/cuda:12.6.0-base-ubuntu22.04 nvidia-smi >/dev/null 2>&1; then
    _log_ok "docker --gpus works after toolkit install"
  else
    _log_warn "docker --gpus still failing; fix toolkit before run_pod_gpu.sh"
  fi
}

ensure_host_deps() {
  local host_gpu="${1:-no}"
  ensure_apt_packages
  ensure_docker
  ensure_nvidia_container_toolkit "${host_gpu}"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  GPU=no
  if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi -L 2>/dev/null | grep -qi GPU; then
    GPU=yes
  fi
  ensure_host_deps "${GPU}"
fi
