#!/usr/bin/env bash
# Linux aarch64 setup — run only via platform/install.sh on arm64 hosts.
set -euo pipefail

PLATFORM_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$PLATFORM_DIR/lib/common.sh"

CONFIG="$(config_for_platform linux-arm)"
REPORT="$PLATFORM_DIR/linux-arm/cli_install_report.json"

echo -e "${YELLOW}=== linux-arm setup ===${NC}"
ensure_conda
activate_env

# Ensure Biomni package is importable from this checkout
export PYTHONPATH="${REPO_ROOT}:${PYTHONPATH:-}"
if ! python -c "import biomni" 2>/dev/null; then
  log_info "pip install -e $REPO_ROOT (editable)"
  pip install -e "$REPO_ROOT" || log_warn "editable install failed; PYTHONPATH=$REPO_ROOT may still work"
fi

# MCP runtime deps (may already be in env)
python -c "import mcp" 2>/dev/null || pip install 'mcp' || true
python -c "import fastmcp" 2>/dev/null || pip install 'fastmcp' || true

# GPU: need CUDA-enabled torch on aarch64 (GB10 / CUDA 13). CPU wheels fail L3.
# Set BIOMNI_SKIP_CUDA_TORCH=1 on arm64 hosts without NVIDIA GPU (CPU-only pods).
ensure_cuda_torch() {
  local need_cuda=0
  if ! python - <<'PY'
import torch, sys
ok = torch.cuda.is_available() and bool(getattr(torch.version, "cuda", None))
sys.exit(0 if ok else 1)
PY
  then
    need_cuda=1
  fi
  if [[ "$need_cuda" -eq 1 ]]; then
    log_info "installing torch with CUDA 13 (cu130) for linux-arm GPU"
    pip install --upgrade 'torch==2.13.0' --index-url https://download.pytorch.org/whl/cu130
    python - <<'PY'
import torch, sys
assert torch.cuda.is_available(), "torch.cuda still unavailable after cu130 install"
print(f"torch {torch.__version__} cuda={torch.version.cuda} device={torch.cuda.get_device_name(0)}")
PY
  else
    log_ok "torch CUDA already available"
  fi
}
if [[ "${BIOMNI_SKIP_CUDA_TORCH:-0}" == "1" ]]; then
  log_warn "BIOMNI_SKIP_CUDA_TORCH=1 — skipping CUDA torch install"
else
  ensure_cuda_torch
fi

# Ensure jq for config installer
if ! command -v jq &>/dev/null; then
  conda install -y -c conda-forge jq
fi

python -c "import meeko" 2>/dev/null || pip install meeko || log_warn "meeko pip install failed (arm64 receptor prep)"

log_info "install CLI from $CONFIG"
bash "$PLATFORM_DIR/lib/install_cli_from_config.sh" "$CONFIG" "$REPORT"

# Prefer conda + platform tools on PATH for this session
export PATH="${CONDA_PREFIX}/bin:${PLATFORM_TOOLS}/bin:${PATH}"

echo
log_ok "linux-arm setup complete"
echo "CLI report: $REPORT"
echo "PATH helper: source $PLATFORM_DIR/setup_path.sh"
echo
echo "Verify imports:"
echo "  python -c \"from biomni.agent import A1; print('A1 OK')\""
echo "MCP example:"
echo "  platform/mcp/cursor.mcp.json.example"
echo "Validation (this host):"
echo "  bash platform/validation/run_all.sh"
