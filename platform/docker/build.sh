#!/usr/bin/env bash
# Build biomni-base (conda/E1 in-image) then biomni-arm runtime (app + entrypoint).
# No host biomni_e1.tar.gz required.
#
# Packaging ALWAYS follows the host OS/arch (no cross-arch / mismatch gates):
#   Linux x86_64     → docker linux/amd64  + BIOMNI_PLATFORM=linux-x86
#   Linux aarch64    → docker linux/arm64  + BIOMNI_PLATFORM=linux-arm
#   macOS arm64      → docker linux/arm64  + BIOMNI_PLATFORM=linux-arm
#                      (container is Linux; host kind logged as macos-arm)
#
# Env:
#   IMAGE_TAG          default biomni-arm:latest
#   BIOMNI_BASE_TAG    default biomni-base:latest
#   BIOMNI_FORCE_CPU=1 force *-cpu profile (skip CUDA torch policy)
#   SKIP_BASE_BUILD=1  only rebuild runtime
#   BUILD_PROFILE      ignored if set — kept for compat log only; host wins
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
CACHE_DIR="${SCRIPT_DIR}/.cache"
CTX_DIR="${CACHE_DIR}/context"
IMAGE_TAG="${IMAGE_TAG:-biomni-arm:latest}"
BIOMNI_BASE_TAG="${BIOMNI_BASE_TAG:-biomni-base:latest}"

HOST_OS="$(uname -s)"
HOST_ARCH="$(uname -m)"

# Host → packaging target (explicit; no override by BUILD_PROFILE).
case "${HOST_OS}:${HOST_ARCH}" in
  Linux:x86_64 | Linux:amd64)
    HOST_KIND=linux-x86
    DOCKER_PLATFORM=linux/amd64
    BIOMNI_PLATFORM=linux-x86
    ARCH_PREFIX=x86_64
    ;;
  Linux:aarch64 | Linux:arm64)
    HOST_KIND=linux-arm
    DOCKER_PLATFORM=linux/arm64
    BIOMNI_PLATFORM=linux-arm
    ARCH_PREFIX=arm64
    ;;
  Darwin:arm64 | Darwin:aarch64)
    HOST_KIND=macos-arm
    # Docker Desktop on Apple Silicon builds Linux arm64 images.
    DOCKER_PLATFORM=linux/arm64
    BIOMNI_PLATFORM=linux-arm
    ARCH_PREFIX=arm64
    ;;
  *)
    echo "error: unsupported host ${HOST_OS}/${HOST_ARCH}" >&2
    echo "supported: Linux x86_64, Linux aarch64/arm64, Darwin arm64" >&2
    exit 1
    ;;
esac

has_gpu=no
if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi -L 2>/dev/null | grep -qi GPU; then
  has_gpu=yes
fi

if [[ "${BIOMNI_FORCE_CPU:-0}" == "1" || "${has_gpu}" != "yes" ]]; then
  BUILD_PROFILE="${ARCH_PREFIX}-cpu"
else
  BUILD_PROFILE="${ARCH_PREFIX}-gpu"
fi

echo "==> host=${HOST_OS}/${HOST_ARCH} kind=${HOST_KIND}"
echo "==> pack docker_platform=${DOCKER_PLATFORM} BIOMNI_PLATFORM=${BIOMNI_PLATFORM} BUILD_PROFILE=${BUILD_PROFILE} gpu=${has_gpu}"
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
  echo "==> docker build base ${BIOMNI_BASE_TAG} (--platform ${DOCKER_PLATFORM})"
  docker build \
    --platform "${DOCKER_PLATFORM}" \
    -t "${BIOMNI_BASE_TAG}" \
    -f "${CTX_DIR}/Dockerfile.base" \
    --build-arg "BUILD_PROFILE=${BUILD_PROFILE}" \
    --build-arg "BIOMNI_PLATFORM=${BIOMNI_PLATFORM}" \
    "${CTX_DIR}"
else
  echo "==> SKIP_BASE_BUILD=1 — reusing ${BIOMNI_BASE_TAG}"
fi

echo "==> docker build runtime ${IMAGE_TAG} (FROM ${BIOMNI_BASE_TAG}, --platform ${DOCKER_PLATFORM})"
docker build \
  --platform "${DOCKER_PLATFORM}" \
  -t "${IMAGE_TAG}" \
  -f "${CTX_DIR}/Dockerfile" \
  --build-arg "BASE_IMAGE=${BIOMNI_BASE_TAG}" \
  "${CTX_DIR}"

echo "==> done: host_kind=${HOST_KIND} base=${BIOMNI_BASE_TAG} runtime=${IMAGE_TAG} platform=${DOCKER_PLATFORM}"
