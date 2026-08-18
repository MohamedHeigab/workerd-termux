# Compiling `workerd` for Termux Android via GitHub Actions

This repository provides a complete, automated **GitHub Actions CI/CD pipeline** to cross-compile Cloudflare's **`workerd`** (the JavaScript/WebAssembly runtime powering Cloudflare Workers) natively for **Android (Termux)** using **Android Bionic libc** and the **Android NDK**.

Nothing needs to be installed or compiled on your local Android/Termux device. Everything is built entirely in the cloud via GitHub Actions.

---

## Table of Contents

- [Overview & Technical Background](#overview--technical-background)
- [How to Build using GitHub Actions](#how-to-build-using-github-actions)
- [Installing on Termux](#installing-on-termux)
- [How `workerd` is Patched for Bionic & Termux](#how-workerd-is-patched-for-bionic--termux)
- [Repository Structure](#repository-structure)

---

## Overview & Technical Background

`workerd` is normally built with Bazel targeting standard desktop Linux distributions (glibc), macOS, and Windows. When porting to Android / Termux, several system-level differences must be addressed:

1. **C Library (Bionic vs. glibc):**
   - Android uses Google's **Bionic libc**, not GNU glibc.
   - Libraries like `libpthread.so` and `librt.so` are built into `libc.so` on Android.
   - Memory allocation functions and signal frame structures (`ucontext_t`, `siginfo_t`) differ from glibc.
2. **tcmalloc:**
   - Upstream `workerd` links `tcmalloc` on Linux. `tcmalloc` relies on internal glibc syscalls and is incompatible with Android Bionic. Bionic's allocator is used instead.
3. **Filesystem & Path Conventions (Termux):**
   - Android lacks standard `/tmp` and `/bin/sh` in the root filesystem.
   - In Termux, paths live under `$PREFIX` (`/data/data/com.termux/files/usr/tmp` and `/data/data/com.termux/files/usr/bin/sh`).
4. **V8 Engine on Android:**
   - V8 defaults to `/data/local/tmp` on Android or `/tmp` on Linux. Patches route this to Termux's `$TMPDIR` / `$PREFIX/tmp`.
   - V8 trap handlers for WebAssembly memory boundaries are enabled for ARM64 standalone userspace binaries (similar to `termux-packages` Node.js patches).
5. **Host vs. Target Cross-Compilation:**
   - Host tools (`mksnapshot`, `protoc`, `capnpc`) run on Linux x86_64 runners, while the final `workerd` binary is compiled for Android `aarch64` / `x86_64`.

---

## How to Build using GitHub Actions

### Method 1: Trigger Manually via GitHub UI (`workflow_dispatch`)

1. **Fork or push** this repository to your GitHub account.
2. Navigate to the **Actions** tab in your GitHub repository.
3. In the sidebar, select **"Build workerd for Termux Android"**.
4. Click **Run workflow**:
   - **`workerd_version`**: Enter `main` or any specific release tag (e.g., `v1.20250214.0`).
   - **`build_type`**: Select `release` (optimized with `-O3` and symbol stripping) or `opt`.
5. Click **Run workflow**.

### Method 2: Trigger via Git Tags

Creating and pushing a Git tag will automatically trigger the build and create a GitHub Release with all compiled packages:

```bash
git tag v1.20250214.0
git push origin v1.20250214.0
```

### Artifacts Produced

The workflow generates:
- **`workerd_<version>_aarch64.deb`**: Standard Termux Debian package for ARM64 Android devices.
- **`workerd_<version>_x86_64.deb`**: Termux Debian package for x86_64 Android emulators / Chromebooks.
- **`workerd-v<version>-android-aarch64.tar.gz`**: Standalone portable tarball with `install.sh` script.
- **`SHA256SUMS`**: Cryptographic checksums for verifying binary integrity.

---

## Installing on Termux

### Option A: Install the `.deb` package (Recommended)

Download the generated `.deb` file for your device architecture (most modern Android phones are `aarch64`):

```bash
# Install required runtime dependencies in Termux
pkg update
pkg install libc++

# Install the downloaded workerd package
pkg install ./workerd_*_aarch64.deb
```

Verify the installation:
```bash
workerd --version
```

### Option B: Install from the Standalone Tarball

```bash
# Extract the tarball
tar -xzf workerd-v*-android-aarch64.tar.gz
cd workerd-*-android-aarch64

# Run the installation script (copies to $PREFIX/bin/workerd)
./install.sh

# Verify
workerd --version
```

---

## How `workerd` is Patched for Bionic & Termux

This repository adapts patches aligned with how `node` and `v8` are patched in the [termux-packages](https://github.com/termux/termux-packages) repository:

| Component | Patch File | Description |
|---|---|---|
| **workerd Core** | `patches/0001-workerd-bionic-support.patch` | Disables `tcmalloc` on Android, adapts `/proc/self/exe` resolution, and fixes Bionic includes. |
| **V8 Engine** | `patches/0002-v8-termux-bionic.patch` | Sets Termux temp directories and enables V8 WebAssembly trap handlers on ARM64 Android. |
| **Cap'n Proto (KJ)** | `patches/0003-capnp-kj-bionic.patch` | Ensures Bionic libc stack unwinding and filesystem system calls (`copy_file_range` / `ioctl`) handle Android kernels gracefully. |
| **Toolchain** | `toolchain/cc_toolchain_config.bzl` | Configures Android NDK Clang, static `libc++_static`, `libc++abi`, and Bionic link flags (`-pie`, `-Wl,-z,nocopyreloc`). |

---

## Repository Structure

```
├── .github/
│   └── workflows/
│       └── build-termux.yml          # GitHub Actions workflow for Bionic build
├── patches/
│   ├── 0001-workerd-bionic-support.patch # Workerd core patches
│   ├── 0002-v8-termux-bionic.patch       # V8 Termux / Bionic patches
│   └── 0003-capnp-kj-bionic.patch        # Cap'n Proto KJ Bionic compatibility
├── packages/
│   └── workerd/
│       └── build.sh                  # Termux-packages compatible package definition
├── scripts/
│   ├── setup-toolchain.sh            # Sets up Android NDK & Bazel toolchain wrappers
│   ├── patch-workerd.sh              # Applies patches to workerd source tree
│   ├── build-workerd.sh              # Executes Bazel Android cross-compilation
│   └── package-deb.sh                # Generates .deb and tarball distribution packages
├── toolchain/
│   ├── BUILD.bazel                   # Bazel toolchain targets for aarch64 and x86_64
│   └── cc_toolchain_config.bzl       # Bazel C++ toolchain rules for Android NDK
└── README.md                         # Documentation & build instructions
```

---

## Running a Cloudflare Worker on Termux

Once `workerd` is installed on your Termux device:

1. Create a `config.capnp` configuration file:
   ```capnp
   using Workerd = import "/workerd/workerd.capnp";

   const config :Workerd.Config = (
     services = [
       (name = "main", worker = .myWorker),
     ],
     sockets = [
       ( name = "http",
         address = "127.0.0.1:8080",
         http = (),
         service = "main"
       ),
     ]
   );

   const myWorker :Workerd.Worker = (
     modules = [
       (name = "worker.js", esModule = embed "worker.js")
     ],
     compatibilityDate = "2025-02-14",
   );
   ```

2. Create `worker.js`:
   ```javascript
   export default {
     async fetch(request) {
       return new Response("Hello from Cloudflare workerd running on Termux Android!");
     }
   };
   ```

3. Start `workerd`:
   ```bash
   workerd serve config.capnp
   ```

4. Test in another Termux session or browser:
   ```bash
   curl http://127.0.0.1:8080
   ```
