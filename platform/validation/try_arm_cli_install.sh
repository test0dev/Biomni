#!/usr/bin/env bash
# Best-effort ARM CLI probes (optional). Prefer platform/install.sh.
set -euo pipefail

VAL="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLATFORM_DIR="$(cd "$VAL/.." && pwd)"
ROOT="$(cd "$PLATFORM_DIR/.." && pwd)"
TOOLS="$PLATFORM_DIR/biomni_tools"
ARM_BIN="$TOOLS/arm_bin"
mkdir -p "$ARM_BIN" "$VAL/reports"

# shellcheck disable=SC1091
source "$HOME/miniconda3/etc/profile.d/conda.sh"
conda activate biomni_e1

echo "Host arch: $(uname -m)"
REPORT="$VAL/reports/cli_arm_install.json"

python - <<'PY' > "$REPORT.tmp"
import json, shutil, subprocess, os
from pathlib import Path

results = []
def try_conda(pkg, bin_name):
    r = {"pkg": pkg, "bin": bin_name, "method": "conda"}
    p = subprocess.run(["conda", "install", "-y", "-c", "bioconda", "-c", "conda-forge", pkg],
                       capture_output=True, text=True)
    r["returncode"] = p.returncode
    r["stderr_tail"] = (p.stderr or "")[-500:]
    which = shutil.which(bin_name)
    r["which"] = which
    if which:
        fr = subprocess.run(["file", "-b", which], capture_output=True, text=True)
        r["file"] = fr.stdout.strip()
        r["status"] = "PASS" if "aarch64" in r["file"] or "ARM aarch64" in r["file"] else "FAIL_ARM"
    else:
        r["status"] = "FAIL_DEP"
    results.append(r)

try_conda("muscle", "muscle")
try_conda("iqtree", "iqtree")
try_conda("plink", "plink")
print(json.dumps({"results": results}, indent=2))
PY
mv "$REPORT.tmp" "$REPORT"
echo "Wrote $REPORT"
echo "repo: $ROOT"
