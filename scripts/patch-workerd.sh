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

# 2. Update src/workerd/server/workerd.c++ and fix Clang 19 noexcept = default destructors & incomplete types
echo "--> Patching workerd source files..."
if ! grep -q "defined(__ANDROID__)" src/workerd/server/workerd.c++; then
  sed -i '/KJ_IF_SOME(link, fs.getRoot().tryReadlink(kj::Path({"proc", "self", "exe"}))) {/i \
#if defined(__ANDROID__)\
    KJ_IF_SOME(link, fs.getRoot().tryReadlink(kj::Path({"proc", "self", "exe"}))) {\
      return tryOpenExe(fs, link);\
    }\
#endif' src/workerd/server/workerd.c++ || true
fi

# Fix incomplete type Blob in hibernation-manager and related headers for Clang 19 template destructor instantiation
for h in src/workerd/io/hibernation-manager.h src/workerd/io/legacy-hibernation-manager.h src/workerd/api/hibernatable-web-socket.h; do
  if [ -f "$h" ] && ! grep -q '<workerd/api/blob.h>' "$h"; then
    sed -i 's|#include <workerd/api/web-socket.h>|#include <workerd/api/blob.h>\n#include <workerd/api/web-socket.h>|g' "$h"
  fi
done
if [ -f "src/workerd/io/hibernation-manager.c++" ] && ! grep -q '<workerd/api/blob.h>' "src/workerd/io/hibernation-manager.c++"; then
  sed -i 's|#include "hibernation-manager.h"|#include <workerd/api/blob.h>\n#include "hibernation-manager.h"|g' src/workerd/io/hibernation-manager.c++
fi

# Fix Clang 19 exception specification deduction for defaulted destructors across all workerd headers
python3 -c '
import os
for root, _, files in os.walk("src/workerd"):
    for file in files:
        if file.endswith(".h") or file.endswith(".c++") or file.endswith(".cc"):
            path = os.path.join(root, file)
            with open(path, "r") as f:
                c = f.read()
            c_new = c.replace("noexcept(false) = default;", "noexcept(false) {}")
            c_new = c_new.replace("noexcept(true) = default;", "noexcept {}")
            if c_new != c:
                with open(path, "w") as f:
                    f.write(c_new)
                print(f"    Fixed noexcept destructor in {path}")
'

# 3. Add Android target triples to rust.MODULE.bazel
if [ -f "build/deps/rust.MODULE.bazel" ]; then
  if ! grep -q "aarch64-linux-android" build/deps/rust.MODULE.bazel; then
    echo "--> Adding Android triples to rust.MODULE.bazel..."
    sed -i 's|"aarch64-unknown-linux-gnu",|"aarch64-unknown-linux-gnu",\n    "aarch64-linux-android",\n    "x86_64-linux-android",|' build/deps/rust.MODULE.bazel
  fi
fi

# 4. Integrate capnp-cpp, simdutf, and perfetto patches in deps.MODULE.bazel
echo "--> Integrating capnp-cpp, simdutf, and perfetto patches..."
mkdir -p patches/capnp patches/simdutf patches/perfetto
cp "${REPO_ROOT}/patches/capnp/0001-android-memfd.patch" patches/capnp/0001-android-memfd.patch
cp "${REPO_ROOT}/patches/simdutf/0001-simdutf-atomic-ref.patch" patches/simdutf/0001-simdutf-atomic-ref.patch
cp "${REPO_ROOT}/patches/perfetto/0003-include-task-runner.patch" patches/perfetto/0003-include-task-runner.patch

if [ -f "build/deps/gen/deps.MODULE.bazel" ]; then
  python3 -c '
with open("build/deps/gen/deps.MODULE.bazel", "r") as f:
    c = f.read()

# capnp-cpp
target_capnp = "    name = \"capnp-cpp\","
replacement_capnp = """    name = "capnp-cpp",
    patch_args = ["-p1"],
    patches = ["//:patches/capnp/0001-android-memfd.patch"],"""
if "patches/capnp/0001-android-memfd.patch" not in c and target_capnp in c:
    c = c.replace(target_capnp, replacement_capnp, 1)

# simdutf
target_simd = """    name = "simdutf",
    build_file = "//:build/BUILD.simdutf\","""
replacement_simd = """    name = "simdutf",
    build_file = "//:build/BUILD.simdutf",
    patch_args = ["-p1"],
    patches = ["//:patches/simdutf/0001-simdutf-atomic-ref.patch"],"""
if "patches/simdutf/0001-simdutf-atomic-ref.patch" not in c and target_simd in c:
    c = c.replace(target_simd, replacement_simd, 1)

# perfetto
target_perf = "\"//:patches/perfetto/0002-disable-info-level-logging-re2.patch\","
replacement_perf = """\"//:patches/perfetto/0002-disable-info-level-logging-re2.patch\",
        \"//:patches/perfetto/0003-include-task-runner.patch\","""
if "patches/perfetto/0003-include-task-runner.patch" not in c and target_perf in c:
    c = c.replace(target_perf, replacement_perf, 1)

with open("build/deps/gen/deps.MODULE.bazel", "w") as f:
    f.write(c)
print("    Registered patches in build/deps/gen/deps.MODULE.bazel")
'
fi

# 5. Integrate V8 Android Bionic atomic_ref & header patch
echo "--> Integrating V8 Android Bionic header patch..."
mkdir -p patches/v8
cp "${REPO_ROOT}/patches/v8/0040-stack-trace-android.patch" patches/v8/0040-stack-trace-android.patch
if [ -f "build/deps/v8.MODULE.bazel" ]; then
  python3 -c '
with open("build/deps/v8.MODULE.bazel", "r") as f:
    c = f.read()

target = "\"0039-wasm-memory.discard-prototype-for-the-memory-control.patch\","
replacement = """\"0039-wasm-memory.discard-prototype-for-the-memory-control.patch\",
    \"0040-stack-trace-android.patch\","""

if "0040-stack-trace-android.patch" not in c and target in c:
    with open("build/deps/v8.MODULE.bazel", "w") as f:
        f.write(c.replace(target, replacement, 1))
    print("    Registered patches/v8/0040-stack-trace-android.patch in build/deps/v8.MODULE.bazel")
'
fi

# 6. Fix cross-compilation exec config for code generator binaries
echo "--> Configuring cross-compilation execution platforms for generator binaries..."
if [ -f "build/run_binary_target.bzl" ]; then
  sed -i 's|cfg = "target"|cfg = "exec"|g' build/run_binary_target.bzl
fi
if [ -f "build/wd_js_bundle.bzl" ]; then
  sed -i 's|cfg = "target"|cfg = "exec"|g' build/wd_js_bundle.bzl
fi
if [ -f "patches/v8/0005-Speed-up-V8-bazel-build-by-always-using-target-cfg.patch" ]; then
  sed -i 's|+    return "target"|+    return "exec"|g' patches/v8/0005-Speed-up-V8-bazel-build-by-always-using-target-cfg.patch
fi

# 7. Patch build/BUILD.zlib for Android compatibility
if [ -f "${REPO_ROOT}/patches/BUILD.zlib" ]; then
  echo "--> Applying Android-compatible build/BUILD.zlib..."
  cp "${REPO_ROOT}/patches/BUILD.zlib" build/BUILD.zlib
fi

# 8. Patch build/BUILD.simdutf for Android compatibility
if [ -f "${REPO_ROOT}/patches/BUILD.simdutf" ]; then
  echo "--> Applying Android-compatible build/BUILD.simdutf..."
  cp "${REPO_ROOT}/patches/BUILD.simdutf" build/BUILD.simdutf
fi

# 9. Patch build/wd_cc_embed.bzl for portable embed generation
if [ -f "${REPO_ROOT}/patches/wd_cc_embed.bzl" ]; then
  echo "--> Applying portable build/wd_cc_embed.bzl..."
  cp "${REPO_ROOT}/patches/wd_cc_embed.bzl" build/wd_cc_embed.bzl
fi

# 10. Patch workerd .bazelrc for Android / Bionic build configs
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
