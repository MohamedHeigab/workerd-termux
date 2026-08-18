TERMUX_PKG_HOMEPAGE=https://github.com/cloudflare/workerd
TERMUX_PKG_DESCRIPTION="Open Source JavaScript/Wasm runtime powering Cloudflare Workers"
TERMUX_PKG_LICENSE="Apache-2.0"
TERMUX_PKG_MAINTAINER="Termux Community"
TERMUX_PKG_VERSION=1.20250214.0
TERMUX_PKG_SRCURL=https://github.com/cloudflare/workerd/archive/refs/tags/v${TERMUX_PKG_VERSION}.tar.gz
TERMUX_PKG_SHA256=SKIP_CHECKSUM
TERMUX_PKG_DEPENDS="libc++"
TERMUX_PKG_BUILD_IN_SRC=true
TERMUX_PKG_HOSTBUILD=true

termux_step_post_get_source() {
	# Copy patches into source directory
	local p
	for p in $TERMUX_PKG_BUILDER_DIR/*.patch; do
		if [ -f "$p" ]; then
			echo "Applying patch: $p"
			patch -p1 < "$p" || true
		fi
	done
}

termux_step_make() {
	local BAZEL_CPU
	local PLATFORM_CPU
	if [ "$TERMUX_ARCH" = "aarch64" ]; then
		BAZEL_CPU="arm64-v8a"
		PLATFORM_CPU="arm64"
	elif [ "$TERMUX_ARCH" = "x86_64" ]; then
		BAZEL_CPU="x86_64"
		PLATFORM_CPU="x86_64"
	else
		termux_error_exit "Unsupported arch: $TERMUX_ARCH"
	fi

	bazel build //src/workerd/server:workerd \
		--config=release_android \
		--platforms=@platforms//os:android,@platforms//cpu:${PLATFORM_CPU} \
		--cpu=${BAZEL_CPU} \
		--//src/workerd/server:use_tcmalloc=False \
		--verbose_failures
}

termux_step_make_install() {
	install -Dm755 bazel-bin/src/workerd/server/workerd "$TERMUX_PREFIX/bin/workerd"
	$STRIP --strip-unneeded "$TERMUX_PREFIX/bin/workerd"
}
