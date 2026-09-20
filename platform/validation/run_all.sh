#!/usr/bin/env bash
# ARM + GPU validation entrypoint (lives under platform/; repo root = biomni-arm).
set -euo pipefail

VAL="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLATFORM_DIR="$(cd "$VAL/.." && pwd)"
ROOT="$(cd "$PLATFORM_DIR/.." && pwd)"
cd "$ROOT"

# shellcheck disable=SC1091
if [[ -f "$HOME/miniconda3/etc/profile.d/conda.sh" ]]; then
  source "$HOME/miniconda3/etc/profile.d/conda.sh"
elif [[ -f "/opt/conda/etc/profile.d/conda.sh" ]]; then
  source "/opt/conda/etc/profile.d/conda.sh"
fi

if conda env list | grep -qE '^biomni_e1[[:space:]]'; then
  conda activate biomni_e1
fi

# Prefer conda (ARM-native) then platform tools
if [[ -n "${CONDA_PREFIX:-}" && -d "$CONDA_PREFIX/bin" ]]; then
  export PATH="$CONDA_PREFIX/bin:$PATH"
fi
if [[ -d "$PLATFORM_DIR/biomni_tools/bin" ]]; then
  export PATH="$PATH:$PLATFORM_DIR/biomni_tools/bin"
fi
if [[ -f "$PLATFORM_DIR/setup_path.sh" ]]; then
  # shellcheck disable=SC1091
  source "$PLATFORM_DIR/setup_path.sh" || true
fi
if [[ -n "${CONDA_PREFIX:-}" && -d "$CONDA_PREFIX/bin" ]]; then
  export PATH="$CONDA_PREFIX/bin:$PATH"
fi

export PYTHONPATH="$ROOT:${PYTHONPATH:-}"
mkdir -p "$VAL/reports" "$VAL/fixtures" "$VAL/data"

# Default: L0 + L1 + L3 (GPU). Opt-in L2/L4.
RUN_L2="${VAL_RUN_L2:-0}"
RUN_L4="${VAL_RUN_L4:-0}"
# Docker GPU optional / non-blocking for host GPU verdict
export VAL_SKIP_DOCKER="${VAL_SKIP_DOCKER:-0}"

echo "=== inventory ==="
python "$VAL/inventory.py" || true

echo "=== generate_tags ==="
python "$VAL/generate_tags.py"

echo "=== generate_fixtures ==="
python "$VAL/generate_fixtures.py"

echo "=== L0 env ==="
python "$VAL/runners/l0_env.py" || true

echo "=== L1 CLI ==="
python "$VAL/runners/l1_cli.py" || true

if [[ "$RUN_L2" == "1" ]]; then
  echo "=== L2 imports ==="
  python "$VAL/runners/l2_imports.py" || true
else
  echo "=== L2 imports (skipped; set VAL_RUN_L2=1) ==="
fi

echo "=== L3 GPU ==="
python "$VAL/runners/l3_gpu.py" || true

if [[ "$RUN_L4" == "1" ]]; then
  echo "=== L4 tools (full) ==="
  python "$VAL/runners/l4_tools.py" || true
else
  echo "=== L4 tools (skipped; set VAL_RUN_L4=1) ==="
fi

echo "=== report ==="
python "$VAL/report.py" || true

echo "Done. See $VAL/reports/validation_latest.md"
