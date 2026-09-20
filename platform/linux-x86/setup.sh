#!/usr/bin/env bash
# Linux x86_64 setup skeleton — NOT executed or validated on arm64 hosts.
# Invoked only when uname reports x86_64/amd64.
set -euo pipefail

PLATFORM_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$PLATFORM_DIR/lib/common.sh"

CONFIG="$(config_for_platform linux-x86)"
REPORT="$PLATFORM_DIR/linux-x86/cli_install_report.json"

echo -e "${YELLOW}=== linux-x86 setup (skeleton / default upstream path) ===${NC}"

# Safety: refuse to run downloads meant for x86 when host is aarch64
host_arch="$(uname -m)"
if [[ "$host_arch" == "aarch64" || "$host_arch" == "arm64" ]]; then
  die "linux-x86/setup.sh must not run on $host_arch (would pull x86 binaries). Use linux-arm instead."
fi

ensure_conda
activate_env

export PYTHONPATH="${REPO_ROOT}:${PYTHONPATH:-}"
if ! python -c "import biomni" 2>/dev/null; then
  pip install -e "$REPO_ROOT" || true
fi

if ! command -v jq &>/dev/null; then
  conda install -y -c conda-forge jq
fi

log_info "install CLI from $CONFIG"
bash "$PLATFORM_DIR/lib/install_cli_from_config.sh" "$CONFIG" "$REPORT"

log_ok "linux-x86 setup complete (not validated in the arm64 CI/dev environment)"
echo "CLI report: $REPORT"
echo "PATH helper: source $PLATFORM_DIR/setup_path.sh"
