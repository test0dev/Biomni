#!/usr/bin/env bash
# Source after: conda activate biomni_e1
PLATFORM_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$PLATFORM_DIR/.." && pwd)"
if [[ -n "${CONDA_PREFIX:-}" && -d "${CONDA_PREFIX}/bin" ]]; then
  export PATH="${CONDA_PREFIX}/bin:${PLATFORM_DIR}/biomni_tools/bin:${PATH}"
else
  export PATH="${PLATFORM_DIR}/biomni_tools/bin:${PATH}"
fi
export PYTHONPATH="${PLATFORM_DIR}:${REPO_ROOT}:${PYTHONPATH:-}"
