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

# Setup githooks if directory exists to satisfy workerd workspace check
mkdir -p githooks
git config core.hooksPath githooks || true

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

# 3. Add Android target triples to rust.MODULE.bazel
if [ -f "build/deps/rust.MODULE.bazel" ]; then
  if ! grep -q "aarch64-linux-android" build/deps/rust.MODULE.bazel; then
    echo "--> Adding Android triples to rust.MODULE.bazel..."
    sed -i 's|"aarch64-unknown-linux-gnu",|"aarch64-unknown-linux-gnu",\n    "aarch64-linux-android",\n    "x86_64-linux-android",|' build/deps/rust.MODULE.bazel
  fi
fi

# 4. Patch capnp-cpp for Android Bionic memfd_create syscall fallback in deps.MODULE.bazel
if [ -f "build/deps/gen/deps.MODULE.bazel" ]; then
  echo "--> Patching capnp-cpp in build/deps/gen/deps.MODULE.bazel..."
  python3 -c '
with open("build/deps/gen/deps.MODULE.bazel", "r") as f:
    c = f.read()

target = "    name = \"capnp-cpp\","
patch_cmd = """    name = "capnp-cpp",
    patch_cmds = [
        "python3 -c \\x27src = open(\\"src/kj/filesystem.c++\\").read(); open(\\"src/kj/filesystem.c++\\", \\"w\\").write(src.replace(\\"#include <sys/mman.h>    // for memfd_create()\\", \\"#include <sys/mman.h>\\\\n#include <sys/syscall.h>\\\\n#include <unistd.h>\\\\n#if defined(__ANDROID__) && !defined(SYS_memfd_create) && defined(__NR_memfd_create)\\\\n#define SYS_memfd_create __NR_memfd_create\\\\n#endif\\\\n#if defined(__ANDROID__)\\\\nstatic inline int kj_memfd_create(const char* n, unsigned int f) {\\\\n#if defined(SYS_memfd_create)\\\\n  return syscall(SYS_memfd_create, n, f);\\\\n#else\\\\n  errno = ENOSYS;\\\\n  return -1;\\\\n#endif\\\\n}\\\\n#define memfd_create kj_memfd_create\\\\n#endif\\"))\\x27",
    ],"""

if "patch_cmds =" not in c and target in c:
    with open("build/deps/gen/deps.MODULE.bazel", "w") as f:
        f.write(c.replace(target, patch_cmd, 1))
    print("    Successfully injected capnp-cpp patch_cmds")
'
fi

# 5. Patch build/BUILD.zlib for Android compatibility
if [ -f "${REPO_ROOT}/patches/BUILD.zlib" ]; then
  echo "--> Applying Android-compatible build/BUILD.zlib..."
  cp "${REPO_ROOT}/patches/BUILD.zlib" build/BUILD.zlib
fi

# 6. Patch build/wd_cc_embed.bzl for portable embed generation
if [ -f "${REPO_ROOT}/patches/wd_cc_embed.bzl" ]; then
  echo "--> Applying portable build/wd_cc_embed.bzl..."
  cp "${REPO_ROOT}/patches/wd_cc_embed.bzl" build/wd_cc_embed.bzl
fi

# 7. Patch workerd .bazelrc for Android / Bionic build configs
echo "--> Appending Android Bionic configuration to .bazelrc..."
if ! grep -q "build:android" .bazelrc; then
cat << 'EOF' >> .bazelrc

# ==========================================
# Termux Android Bionic Build Configuration
# ==========================================
build:android --//src/workerd/server:use_tcmalloc=False
build:android --//src/workerd/server:use_transpiler=False
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
