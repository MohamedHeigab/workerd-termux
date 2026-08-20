#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
WORKERD_DIR="${1:-${REPO_ROOT}/workerd-src}"
VERSION="${2:-1.0.0}"
ARCH="${3:-aarch64}"

# Debian version MUST start with a digit (deb-version(7))
DEB_VERSION="${VERSION}"
if [[ ! "${DEB_VERSION}" =~ ^[0-9] ]]; then
  DEB_VERSION="1.0.0+${DEB_VERSION}"
fi

DIST_DIR="${REPO_ROOT}/dist"
BINARY_SOURCE="${WORKERD_DIR}/bazel-bin/src/workerd/server/workerd"

echo "=== Packaging workerd for Termux (${ARCH}) ==="
echo "Version: ${VERSION} (Debian: ${DEB_VERSION})"
echo "Binary:  ${BINARY_SOURCE}"

if [ ! -f "${BINARY_SOURCE}" ]; then
  echo "Error: Binary not found at ${BINARY_SOURCE}"
  exit 1
fi

mkdir -p "${DIST_DIR}"

# 1. Package Termux Debian (.deb)
PKG_NAME="workerd"
PKG_DIR="${DIST_DIR}/${PKG_NAME}_${DEB_VERSION}_${ARCH}"
mkdir -p "${PKG_DIR}/DEBIAN"
mkdir -p "${PKG_DIR}/data/data/com.termux/files/usr/bin"
mkdir -p "${PKG_DIR}/data/data/com.termux/files/usr/share/doc/workerd"

# Copy binary
cp "${BINARY_SOURCE}" "${PKG_DIR}/data/data/com.termux/files/usr/bin/workerd"
chmod 755 "${PKG_DIR}/data/data/com.termux/files/usr/bin/workerd"

# Copy docs/license
cat << EOF > "${PKG_DIR}/data/data/com.termux/files/usr/share/doc/workerd/copyright"
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: workerd
Upstream-Contact: Cloudflare <workers-runtime@cloudflare.com>
Source: https://github.com/cloudflare/workerd

Files: *
Copyright: 2017-2025 Cloudflare, Inc.
License: Apache-2.0
EOF

# Create Debian control file
INSTALLED_SIZE=$(du -sk "${PKG_DIR}/data" | cut -f1)
cat << EOF > "${PKG_DIR}/DEBIAN/control"
Package: ${PKG_NAME}
Version: ${DEB_VERSION}
Architecture: ${ARCH}
Maintainer: Termux Community
Installed-Size: ${INSTALLED_SIZE}
Homepage: https://github.com/cloudflare/workerd
Depends: libc++
Section: devel
Priority: optional
Description: Cloudflare Workers JavaScript/Wasm runtime (built for Termux with Bionic)
 workerd is the JavaScript/Wasm server runtime that powers Cloudflare
 Workers. This package provides a native build for Android/Termux
 linked against Android Bionic libc and libc++.
EOF

echo "--> Building .deb package..."
dpkg-deb --build --root-owner-group "${PKG_DIR}" "${DIST_DIR}/${PKG_NAME}_${DEB_VERSION}_${ARCH}.deb"
rm -rf "${PKG_DIR}"

# 2. Package standalone tarball
TAR_DIR="${DIST_DIR}/workerd-v${VERSION}-android-${ARCH}"
mkdir -p "${TAR_DIR}"
cp "${BINARY_SOURCE}" "${TAR_DIR}/workerd"
chmod 755 "${TAR_DIR}/workerd"

cat << 'EOF' > "${TAR_DIR}/install.sh"
#!/data/data/com.termux/files/usr/bin/sh
set -e
PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
echo "Installing workerd to ${PREFIX}/bin/workerd..."
mkdir -p "${PREFIX}/bin"
cp "$(dirname "$0")/workerd" "${PREFIX}/bin/workerd"
chmod 755 "${PREFIX}/bin/workerd"
echo "Installation complete! Run 'workerd --version' to test."
EOF
chmod +x "${TAR_DIR}/install.sh"

echo "--> Building tarball package..."
tar -czf "${DIST_DIR}/workerd-v${VERSION}-android-${ARCH}.tar.gz" -C "${DIST_DIR}" "workerd-v${VERSION}-android-${ARCH}"
rm -rf "${TAR_DIR}"

echo "=== Generated Packages in ${DIST_DIR} ==="
ls -lh "${DIST_DIR}"
