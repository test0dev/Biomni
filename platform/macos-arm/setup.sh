#!/usr/bin/env bash
# Native macOS arm64 setup — run only via platform/install.sh on Darwin/arm64.
# Docker packaging on this host still builds linux/arm64 images (see build.sh).
set -euo pipefail

PLATFORM_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$PLATFORM_DIR/lib/common.sh"

CONFIG="$(config_for_platform macos-arm)"
REPORT="$PLATFORM_DIR/macos-arm/cli_install_report.json"

echo -e "${YELLOW}=== macos-arm setup ===${NC}"
ensure_conda
activate_env

export PYTHONPATH="${REPO_ROOT}:${PYTHONPATH:-}"
if ! python -c "import biomni" 2>/dev/null; then
  log_info "pip install -e $REPO_ROOT (editable)"
  pip install -e "$REPO_ROOT" || log_warn "editable install failed; PYTHONPATH=$REPO_ROOT may still work"
fi

python -c "import mcp" 2>/dev/null || pip install 'mcp' || true
python -c "import fastmcp" 2>/dev/null || pip install 'fastmcp' || true

# No NVIDIA CUDA on typical Apple Silicon; keep CPU torch.
log_warn "macos-arm: skipping CUDA torch (use Docker linux/arm64 + GPU host for CUDA pods)"

if ! command -v jq &>/dev/null; then
  conda install -y -c conda-forge jq
fi

log_info "install CLI from $CONFIG"
bash "$PLATFORM_DIR/lib/install_cli_from_config.sh" "$CONFIG" "$REPORT"

export PATH="${CONDA_PREFIX}/bin:${PLATFORM_TOOLS}/bin:${PATH}"

echo
log_ok "macos-arm setup complete"
echo "CLI report: $REPORT"
echo "Docker images on this Mac: bash platform/docker/build.sh  →  linux/arm64"
echo "PATH helper: source $PLATFORM_DIR/setup_path.sh"
