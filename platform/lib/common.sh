#!/usr/bin/env bash
# Shared helpers for platform/install.sh (additive; does not modify upstream).
# shellcheck disable=SC2034

PLATFORM_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "$PLATFORM_DIR/.." && pwd)"
BIOMNI_ENV_DIR="$REPO_ROOT/biomni_env"
PLATFORM_TOOLS="$PLATFORM_DIR/biomni_tools"
PLATFORM_CONFIGS="$PLATFORM_DIR/configs"
ENV_NAME="${BIOMNI_ENV_NAME:-biomni_e1}"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()  { echo -e "${BLUE}[info]${NC} $*"; }
log_ok()    { echo -e "${GREEN}[ok]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[warn]${NC} $*"; }
log_err()   { echo -e "${RED}[error]${NC} $*" >&2; }

die() { log_err "$*"; exit 1; }

ensure_conda() {
  if command -v conda &>/dev/null; then
    return 0
  fi
  if [[ -f "$HOME/miniconda3/etc/profile.d/conda.sh" ]]; then
    # shellcheck disable=SC1091
    source "$HOME/miniconda3/etc/profile.d/conda.sh"
    return 0
  fi
  if [[ -f "/opt/conda/etc/profile.d/conda.sh" ]]; then
    # shellcheck disable=SC1091
    source "/opt/conda/etc/profile.d/conda.sh"
    return 0
  fi
  die "conda not found. Install Miniconda first: https://docs.conda.io/en/latest/miniconda.html"
}

activate_env() {
  ensure_conda
  if ! conda env list | grep -qE "^${ENV_NAME}[[:space:]]"; then
    die "conda env '${ENV_NAME}' not found. Create it first (see platform README), or set BIOMNI_ENV_NAME."
  fi
  # shellcheck disable=SC1091
  eval "$(conda shell.bash hook)"
  conda activate "$ENV_NAME"
  export PATH="${CONDA_PREFIX}/bin:${PATH}"
  log_ok "activated conda env: ${ENV_NAME} (${CONDA_PREFIX})"
}

detect_platform() {
  local os arch
  os="$(uname -s)"
  arch="$(uname -m)"
  case "${os}:${arch}" in
    Linux:aarch64|Linux:arm64) echo "linux-arm" ;;
    Linux:x86_64|Linux:amd64)  echo "linux-x86" ;;
    Darwin:arm64|Darwin:aarch64) echo "macos-arm" ;;
    *) echo "unsupported" ;;
  esac
}

config_for_platform() {
  case "$1" in
    linux-arm) echo "$PLATFORM_CONFIGS/cli_tools_config_linux_aarch64.json" ;;
    linux-x86) echo "$PLATFORM_CONFIGS/cli_tools_config_linux_x86_64.json" ;;
    macos-arm) echo "$PLATFORM_CONFIGS/cli_tools_config_macos_arm64.json" ;;
    *) die "no CLI config for platform: $1" ;;
  esac
}
