#!/usr/bin/env bash
# Build biomni-arm:latest from packed biomni_e1 + repo sources.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
CACHE_DIR="${SCRIPT_DIR}/.cache"
CTX_DIR="${CACHE_DIR}/context"
IMAGE_TAG="${IMAGE_TAG:-biomni-arm:latest}"
PACK_TGZ="${CACHE_DIR}/biomni_e1.tar.gz"

if [[ ! -f "${PACK_TGZ}" ]]; then
  echo "error: missing ${PACK_TGZ}" >&2
  echo "Run: conda-pack -n biomni_e1 -o ${PACK_TGZ} --n-threads -1 --ignore-editable-packages --ignore-missing-files" >&2
  exit 1
fi

echo "==> preparing build context in ${CTX_DIR}"
rm -rf "${CTX_DIR}"
mkdir -p "${CTX_DIR}/app"

# Code + platform tools into context/app (exclude heavy / local-only paths).
rsync -a \
  --exclude '.git/' \
  --exclude '.cache/' \
  --exclude 'platform/docker/.cache/' \
  --exclude 'platform/mcp/node_modules/' \
  --exclude 'data/' \
  --exclude '__pycache__/' \
  --exclude '*.pyc' \
  --exclude '.pytest_cache/' \
  --exclude '.mypy_cache/' \
  --exclude '.ruff_cache/' \
  --exclude '.venv/' \
  --exclude 'venv/' \
  "${REPO_ROOT}/" "${CTX_DIR}/app/"

cp -a "${PACK_TGZ}" "${CTX_DIR}/biomni_e1.tar.gz"
cp -a "${SCRIPT_DIR}/Dockerfile" "${CTX_DIR}/Dockerfile"
cp -a "${SCRIPT_DIR}/entrypoint.sh" "${CTX_DIR}/entrypoint.sh"

echo "==> docker build ${IMAGE_TAG}"
docker build -t "${IMAGE_TAG}" -f "${CTX_DIR}/Dockerfile" "${CTX_DIR}"
echo "==> done: ${IMAGE_TAG}"
