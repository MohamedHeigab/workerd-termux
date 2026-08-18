#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
WORKERD_DIR="${1:-${REPO_ROOT}/workerd-src}"

echo "=== Applying Termux Bionic Patches to workerd ==="
echo "Target directory: ${WORKERD_DIR}"

if [ ! -d "${WORKERD_DIR}" ]; then
  echo "Error: Directory ${WORKERD_DIR} does not exist."
  exit 1
fi

cd "${WORKERD_DIR}"

# 1. Update root BUILD.bazel with Android platforms and constraints
echo "--> Configuring Android platforms in BUILD.bazel..."
if ! grep -q "name = \"android_aarch64\"" BUILD.bazel; then
cat << 'EOF' >> BUILD.bazel

# Android platforms for Termux cross-compilation
platform(
    name = "android_aarch64",
    constraint_values = [
        "@platforms//os:android",
        "@platforms//cpu:arm64",
    ],
)

platform(
    name = "android_x86_64",
    constraint_values = [
        "@platforms//os:android",
        "@platforms//cpu:x86_64",
    ],
)

config_setting(
    name = "is_android",
    constraint_values = ["@platforms//os:android"],
    visibility = ["//visibility:public"],
)
EOF
fi

# Update is_unix group to include is_android
if ! grep -q '":is_android"' BUILD.bazel; then
  sed -i '/":is_macos",/a \        ":is_android",' BUILD.bazel
fi

# 2. Update src/workerd/server/workerd.c++ for Android exe resolution
echo "--> Patching src/workerd/server/workerd.c++..."
if ! grep -q "defined(__ANDROID__)" src/workerd/server/workerd.c++; then
  sed -i '/KJ_IF_SOME(link, fs.getRoot().tryReadlink(kj::Path({"proc", "self", "exe"}))) {/i \
#if defined(__ANDROID__)\
    KJ_IF_SOME(link, fs.getRoot().tryReadlink(kj::Path({"proc", "self", "exe"}))) {\
      return tryOpenExe(fs, link);\
    }\
#endif' src/workerd/server/workerd.c++ || true
fi

# 3. Add V8 patches into workerd's patches/v8 directory
echo "--> Integrating V8 Termux patch..."
mkdir -p patches/v8
cp "${REPO_ROOT}/patches/0002-v8-termux-bionic.patch" patches/v8/0040-termux-bionic-support.patch

# 4. Register the new V8 patch in v8.MODULE.bazel if not already present
if [ -f "build/deps/v8.MODULE.bazel" ]; then
  if ! grep -q "0040-termux-bionic-support.patch" build/deps/v8.MODULE.bazel; then
    echo "--> Registering 0040-termux-bionic-support.patch in build/deps/v8.MODULE.bazel"
    sed -i '/"0039-wasm-memory.discard-prototype-for-the-memory-control.patch",/a \    "0040-termux-bionic-support.patch",' build/deps/v8.MODULE.bazel
  fi
fi

# 5. Patch workerd .bazelrc for Android / Bionic build configs
echo "--> Appending Android Bionic configuration to .bazelrc..."
if ! grep -q "build:android" .bazelrc; then
cat << 'EOF' >> .bazelrc

# ==========================================
# Termux Android Bionic Build Configuration
# ==========================================
build:android --//src/workerd/server:use_tcmalloc=False
build:android --copt=-D__ANDROID__
build:android --copt=-D__TERMUX__
build:android --copt=-D__ANDROID_API__=24
build:android --copt=-ffunction-sections
build:android --copt=-fdata-sections
build:android --cxxopt=-stdlib=libc++
build:android --linkopt=-stdlib=libc++
build:android --linkopt=-fuse-ld=lld
build:android --linkopt=-Wl,--gc-sections
build:android --linkopt=-Wl,-z,nocopyreloc
build:android --linkopt=-Wl,-z,relro
build:android --linkopt=-Wl,-z,now
build:android --linkopt=-pie
build:android --linkopt=-static-libstdc++
build:android --linkopt=-lc++_static
build:android --linkopt=-lc++abi
build:android --linkopt=-lunwind
build:android --linkopt=-ldl
build:android --linkopt=-lm
build:android --linkopt=-llog
build:android --linkopt=-lc

# Release config for Android
build:release_android --config=android
build:release_android --config=opt
build:release_android --copt=-O3
build:release_android --linkopt=-Wl,-O2
EOF
fi

echo "=== Patches successfully applied! ==="
