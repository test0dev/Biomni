#!/usr/bin/env bash
# Optional: link prior aarch64 source builds into conda + platform tools.
# Prefer platform/lib/install_cli_from_config.sh via install.sh.
set -euo pipefail
VAL="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLATFORM_DIR="$(cd "$VAL/.." && pwd)"
ROOT="$(cd "$PLATFORM_DIR/.." && pwd)"
TOOLS="$PLATFORM_DIR/biomni_tools"
SRC="$TOOLS/src"
BIN="$TOOLS/bin"
# shellcheck disable=SC1091
source "$HOME/miniconda3/etc/profile.d/conda.sh"
conda activate biomni_e1
CONDA_BIN="${CONDA_PREFIX}/bin"
export PATH="/usr/bin:${CONDA_BIN}:$PATH"
mkdir -p "$BIN" "$SRC"

echo "==> plink2 (from prior source build if present)"
if [[ -x "$SRC/plink-ng/2.0/build_dynamic/plink2" ]]; then
  cp -f "$SRC/plink-ng/2.0/build_dynamic/plink2" "$CONDA_BIN/plink2"
  ln -sfn "$CONDA_BIN/plink2" "$BIN/plink2"
fi

echo "==> gcta64 (from prior source build if present)"
if [[ -x "$SRC/GCTA/build/Release/gcta64" ]]; then
  cp -f "$SRC/GCTA/build/Release/gcta64" "$CONDA_BIN/gcta64"
  ln -sfn "$CONDA_BIN/gcta64" "$BIN/gcta64"
fi

echo "==> bioconda fallbacks: muscle, iqtree, plink1.9"
conda install -y -c bioconda -c conda-forge muscle iqtree plink || true

echo "==> iqtree2 -> iqtree compatibility"
ln -sfn "$CONDA_BIN/iqtree" "$CONDA_BIN/iqtree2"
ln -sfn "$CONDA_BIN/iqtree" "$BIN/iqtree2"

echo "==> status"
for b in plink2 gcta64 iqtree iqtree2 muscle plink; do
  w=$(command -v "$b" || true)
  if [[ -n "$w" ]]; then
    echo "  $b -> $w ($(file -b -L "$w" | cut -c1-50))"
  else
    echo "  $b -> MISSING"
  fi
done

echo "repo root: $ROOT"
