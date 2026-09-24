#!/usr/bin/env bash
# Build biomni-base (conda/E1 in-image) then biomni-arm runtime (app + entrypoint).
# No host biomni_e1.tar.gz required.
#
# Env:
#   IMAGE_TAG          default biomni-arm:latest
#   BIOMNI_BASE_TAG    default biomni-base:latest
#   BUILD_PROFILE      arm64-gpu|arm64-cpu|x86_64-gpu|x86_64-cpu
#   SKIP_BASE_BUILD=1  only rebuild runtime
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
CACHE_DIR="${SCRIPT_DIR}/.cache"
CTX_DIR="${CACHE_DIR}/context"
IMAGE_TAG="${IMAGE_TAG:-biomni-arm:latest}"
BIOMNI_BASE_TAG="${BIOMNI_BASE_TAG:-biomni-base:latest}"
BUILD_PROFILE="${BUILD_PROFILE:-}"

if [[ -z "${BUILD_PROFILE}" ]]; then
  case "$(uname -m)" in
    aarch64 | arm64)
      if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi -L 2>/dev/null | grep -qi GPU; then
        BUILD_PROFILE=arm64-gpu
      else
        BUILD_PROFILE=arm64-cpu
      fi
      ;;
    x86_64 | amd64)
      if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi -L 2>/dev/null | grep -qi GPU; then
        BUILD_PROFILE=x86_64-gpu
      else
        BUILD_PROFILE=x86_64-cpu
      fi
      ;;
    *)
      echo "error: unsupported arch $(uname -m)" >&2
      exit 1
      ;;
  esac
fi

echo "==> BUILD_PROFILE=${BUILD_PROFILE}"
echo "==> preparing build context in ${CTX_DIR}"
rm -rf "${CTX_DIR}"
mkdir -p "${CTX_DIR}/app"

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

cp -a "${SCRIPT_DIR}/Dockerfile.base" "${CTX_DIR}/Dockerfile.base"
cp -a "${SCRIPT_DIR}/Dockerfile" "${CTX_DIR}/Dockerfile"
cp -a "${SCRIPT_DIR}/entrypoint.sh" "${CTX_DIR}/entrypoint.sh"

if [[ "${SKIP_BASE_BUILD:-0}" != "1" ]]; then
  echo "==> docker build base ${BIOMNI_BASE_TAG}"
  docker build \
    -t "${BIOMNI_BASE_TAG}" \
    -f "${CTX_DIR}/Dockerfile.base" \
    --build-arg "BUILD_PROFILE=${BUILD_PROFILE}" \
    "${CTX_DIR}"
else
  echo "==> SKIP_BASE_BUILD=1 — reusing ${BIOMNI_BASE_TAG}"
fi

echo "==> docker build runtime ${IMAGE_TAG} (FROM ${BIOMNI_BASE_TAG})"
docker build \
  -t "${IMAGE_TAG}" \
  -f "${CTX_DIR}/Dockerfile" \
  --build-arg "BASE_IMAGE=${BIOMNI_BASE_TAG}" \
  "${CTX_DIR}"

echo "==> done: base=${BIOMNI_BASE_TAG} runtime=${IMAGE_TAG}"
