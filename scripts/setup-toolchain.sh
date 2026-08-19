#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
WORKERD_DIR="${1:-${REPO_ROOT}/workerd-src}"

ANDROID_NDK_HOME="${ANDROID_NDK_HOME:-/opt/android-ndk}"
TARGET_ARCH="${TARGET_ARCH:-aarch64}"
TARGET_TRIPLE="${TARGET_TRIPLE:-aarch64-linux-android}"
API_LEVEL="${API_LEVEL:-24}"

echo "=== Configuring Android Bionic Toolchain ==="
echo "Android NDK:    ${ANDROID_NDK_HOME}"
echo "Target Arch:    ${TARGET_ARCH}"
echo "Target Triple:  ${TARGET_TRIPLE}"
echo "API Level:      ${API_LEVEL}"
echo "workerd Dir:    ${WORKERD_DIR}"

if [ ! -d "${ANDROID_NDK_HOME}" ]; then
  echo "Error: ANDROID_NDK_HOME directory (${ANDROID_NDK_HOME}) does not exist."
  exit 1
fi

NDK_BIN="${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/linux-x86_64/bin"

# Make sure all binaries in NDK_BIN are executable and fix any broken symlinks if needed
chmod -R +x "${NDK_BIN}" 2>/dev/null || true

# Determine actual clang / clang++ binaries
CLANG_EXE="${NDK_BIN}/clang"
if [ ! -f "${CLANG_EXE}" ] && [ -f "${NDK_BIN}/clang-19" ]; then
  CLANG_EXE="${NDK_BIN}/clang-19"
fi

CLANGXX_EXE="${NDK_BIN}/clang++"
if [ ! -f "${CLANGXX_EXE}" ] && [ -f "${NDK_BIN}/clang-19" ]; then
  CLANGXX_EXE="${NDK_BIN}/clang-19"
fi

# 1. Copy toolchain package into workerd-src
mkdir -p "${WORKERD_DIR}/toolchain/wrappers"
cp "${REPO_ROOT}/toolchain/cc_toolchain_config.bzl" "${WORKERD_DIR}/toolchain/"
sed "s|\$\$ANDROID_NDK_HOME\$\$|${ANDROID_NDK_HOME}|g" "${REPO_ROOT}/toolchain/BUILD.bazel" > "${WORKERD_DIR}/toolchain/BUILD.bazel"

# Create dummy libpthread.a and librt.a for Bionic compatibility (pthread/rt are part of libc in Bionic)
"${NDK_BIN}/llvm-ar" cr "${WORKERD_DIR}/toolchain/libpthread.a" 2>/dev/null || true
"${NDK_BIN}/llvm-ar" cr "${WORKERD_DIR}/toolchain/librt.a" 2>/dev/null || true

# 2. Create direct toolchain wrappers passing --target explicitly and filtering non-Bionic flags
cat << EOF > "${WORKERD_DIR}/toolchain/wrappers/clang"
#!/usr/bin/env bash
args=()
for arg in "\$@"; do
  if [ "\$arg" = "-lpthread" ] || [ "\$arg" = "-lrt" ]; then
    continue
  fi
  args+=("\$arg")
done
exec "${CLANG_EXE}" --target="${TARGET_TRIPLE}${API_LEVEL}" "\${args[@]}"
EOF

cat << EOF > "${WORKERD_DIR}/toolchain/wrappers/clang++"
#!/usr/bin/env bash
args=()
for arg in "\$@"; do
  if [ "\$arg" = "-lpthread" ] || [ "\$arg" = "-lrt" ]; then
    continue
  fi
  args+=("\$arg")
done
exec "${CLANGXX_EXE}" --target="${TARGET_TRIPLE}${API_LEVEL}" "\${args[@]}"
EOF

cat << EOF > "${WORKERD_DIR}/toolchain/wrappers/clang-cpp"
#!/usr/bin/env bash
exec "${CLANG_EXE}" --target="${TARGET_TRIPLE}${API_LEVEL}" -E "\$@"
EOF

cat << EOF > "${WORKERD_DIR}/toolchain/wrappers/llvm-ar"
#!/usr/bin/env bash
exec "${NDK_BIN}/llvm-ar" "\$@"
EOF

cat << EOF > "${WORKERD_DIR}/toolchain/wrappers/llvm-nm"
#!/usr/bin/env bash
exec "${NDK_BIN}/llvm-nm" "\$@"
EOF

cat << EOF > "${WORKERD_DIR}/toolchain/wrappers/ld.lld"
#!/usr/bin/env bash
exec "${NDK_BIN}/ld.lld" "\$@"
EOF

cat << EOF > "${WORKERD_DIR}/toolchain/wrappers/llvm-objdump"
#!/usr/bin/env bash
exec "${NDK_BIN}/llvm-objdump" "\$@"
EOF

cat << EOF > "${WORKERD_DIR}/toolchain/wrappers/llvm-strip"
#!/usr/bin/env bash
exec "${NDK_BIN}/llvm-strip" "\$@"
EOF

chmod +x "${WORKERD_DIR}/toolchain/wrappers/"*

# 3. Register toolchains in workerd MODULE.bazel or .bazelrc
if ! grep -q "register_toolchains(\"//toolchain:" "${WORKERD_DIR}/MODULE.bazel" 2>/dev/null; then
  echo "" >> "${WORKERD_DIR}/MODULE.bazel"
  echo "register_toolchains(\"//toolchain:android_${TARGET_ARCH}_toolchain\")" >> "${WORKERD_DIR}/MODULE.bazel"
fi

echo "=== Toolchain successfully configured ==="
