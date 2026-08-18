#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
WORKERD_DIR="${1:-${REPO_ROOT}/workerd-src}"

TARGET_ARCH="${TARGET_ARCH:-aarch64}"
TARGET_TRIPLE="${TARGET_TRIPLE:-aarch64-linux-android}"
API_LEVEL="${API_LEVEL:-24}"
ANDROID_NDK_HOME="${ANDROID_NDK_HOME:-/opt/android-ndk}"

echo "=== Building workerd for Android Bionic (${TARGET_ARCH}) ==="

cd "${WORKERD_DIR}"

if [ "${TARGET_ARCH}" = "aarch64" ]; then
  BAZEL_CPU="arm64-v8a"
  TARGET_PLATFORM="//:android_aarch64"
elif [ "${TARGET_ARCH}" = "x86_64" ]; then
  BAZEL_CPU="x86_64"
  TARGET_PLATFORM="//:android_x86_64"
else
  echo "Unsupported architecture: ${TARGET_ARCH}"
  exit 1
fi

echo "--> Target Platform: ${TARGET_PLATFORM}"
echo "--> Bazel CPU:       ${BAZEL_CPU}"

echo "--> Invoking Bazel..."
bazel build //src/workerd/server:workerd \
  --config=release_android \
  --platforms=${TARGET_PLATFORM} \
  --cpu=${BAZEL_CPU} \
  --//src/workerd/server:use_tcmalloc=False \
  --verbose_failures \
  --jobs="$(nproc)"

OUTPUT_BINARY="bazel-bin/src/workerd/server/workerd"

if [ ! -f "${OUTPUT_BINARY}" ]; then
  echo "Error: Output binary ${OUTPUT_BINARY} was not generated."
  exit 1
fi

echo "--> Stripping binary symbols..."
STRIP="${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strip"
if [ -x "${STRIP}" ]; then
  "${STRIP}" --strip-unneeded "${OUTPUT_BINARY}"
else
  llvm-strip --strip-unneeded "${OUTPUT_BINARY}" || true
fi

echo "=== Build finished successfully! Output at ${OUTPUT_BINARY} ==="
