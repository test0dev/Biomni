#!/usr/bin/env bash
# Unique entry: detect OS/arch via uname and dispatch to platform setup.
# Does not modify upstream Biomni files.
set -euo pipefail

PLATFORM_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$PLATFORM_DIR/lib/common.sh"

echo -e "${YELLOW}=== Biomni platform install ===${NC}"
log_info "repo: $REPO_ROOT"
log_info "host: $(uname -s) $(uname -m)"

if [[ -n "${BIOMNI_PLATFORM:-}" ]]; then
  PLATFORM="$BIOMNI_PLATFORM"
  log_warn "BIOMNI_PLATFORM override: $PLATFORM"
else
  PLATFORM="$(detect_platform)"
fi

case "$PLATFORM" in
  linux-arm)
    log_info "dispatch → linux-arm"
    bash "$PLATFORM_DIR/linux-arm/setup.sh"
    ;;
  linux-x86)
    log_info "dispatch → linux-x86"
    bash "$PLATFORM_DIR/linux-x86/setup.sh"
    ;;
  macos-arm)
    log_info "dispatch → macos-arm (native host; Docker pods still use linux/arm64 images)"
    bash "$PLATFORM_DIR/macos-arm/setup.sh"
    ;;
  *)
    die "unsupported platform (os=$(uname -s) arch=$(uname -m)). Supported: linux-arm, linux-x86, macos-arm."
    ;;
esac

echo
log_ok "install finished for: $PLATFORM"
echo
echo "Next:"
echo "  conda activate ${ENV_NAME}"
echo "  # MCP (stdio): see platform/mcp/cursor.mcp.json.example"
echo "  # Validation (linux-arm only): bash platform/validation/run_all.sh"
