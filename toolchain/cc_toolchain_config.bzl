"""
Custom CC Toolchain configuration for Android Bionic (Termux)
"""

load("@rules_cc//cc/common:cc_common.bzl", "cc_common")
load("@rules_cc//cc:cc_toolchain_config_lib.bzl",
    "feature",
    "flag_group",
    "flag_set",
    "tool_path",
)
load("@bazel_tools//tools/build_defs/cc:action_names.bzl", "ACTION_NAMES")

all_compile_actions = [
    ACTION_NAMES.c_compile,
    ACTION_NAMES.cpp_compile,
    ACTION_NAMES.linkstamp_compile,
    ACTION_NAMES.assemble,
    ACTION_NAMES.preprocess_assemble,
    ACTION_NAMES.cpp_header_parsing,
    ACTION_NAMES.cpp_module_compile,
    ACTION_NAMES.cpp_module_codegen,
    ACTION_NAMES.lto_backend,
    ACTION_NAMES.clif_match,
]

all_cpp_compile_actions = [
    ACTION_NAMES.cpp_compile,
    ACTION_NAMES.linkstamp_compile,
    ACTION_NAMES.cpp_header_parsing,
    ACTION_NAMES.cpp_module_compile,
    ACTION_NAMES.cpp_module_codegen,
    ACTION_NAMES.lto_backend,
    ACTION_NAMES.clif_match,
]

all_link_actions = [
    ACTION_NAMES.cpp_link_executable,
    ACTION_NAMES.cpp_link_dynamic_library,
    ACTION_NAMES.cpp_link_nodeps_dynamic_library,
]

def _impl(ctx):
    target_triple = ctx.attr.target_triple
    api_level = ctx.attr.api_level
    ndk_path = ctx.attr.ndk_path

    tool_paths = [
        tool_path(name = "gcc", path = "wrappers/clang"),
        tool_path(name = "g++", path = "wrappers/clang++"),
        tool_path(name = "cpp", path = "wrappers/clang-cpp"),
        tool_path(name = "ar", path = "wrappers/llvm-ar"),
        tool_path(name = "nm", path = "wrappers/llvm-nm"),
        tool_path(name = "ld", path = "wrappers/ld.lld"),
        tool_path(name = "objdump", path = "wrappers/llvm-objdump"),
        tool_path(name = "strip", path = "wrappers/llvm-strip"),
    ]

    compile_flags = [
        "-target", target_triple + str(api_level),
        "-fPIC",
        "-no-canonical-prefixes",
        "-D__ANDROID__",
        "-D__ANDROID_API__=" + str(api_level),
        "-D__TERMUX__",
        "-ffunction-sections",
        "-fdata-sections",
        "-Wall",
        "-Wno-invalid-offsetof",
        "-Wno-unknown-warning-option",
    ]

    cxx_flags = [
        "-stdlib=libc++",
    ]

    link_flags = [
        "-target", target_triple + str(api_level),
        "-fuse-ld=lld",
        "-Wl,--gc-sections",
        "-Wl,-z,nocopyreloc",
        "-Wl,-z,relro",
        "-Wl,-z,now",
        "-pie",
        "-static-libstdc++",
        "-lc++_static",
        "-lc++abi",
        "-lunwind",
        "-ldl",
        "-lm",
        "-llog",
        "-lc",
    ]

    features = [
        feature(
            name = "default_compile_flags",
            enabled = True,
            flag_sets = [
                flag_set(
                    actions = all_compile_actions,
                    flag_groups = [flag_group(flags = compile_flags)],
                ),
                flag_set(
                    actions = all_cpp_compile_actions,
                    flag_groups = [flag_group(flags = cxx_flags)],
                ),
            ],
        ),
        feature(
            name = "default_link_flags",
            enabled = True,
            flag_sets = [
                flag_set(
                    actions = all_link_actions,
                    flag_groups = [flag_group(flags = link_flags)],
                ),
            ],
        ),
        feature(
            name = "opt",
            flag_sets = [
                flag_set(
                    actions = all_compile_actions,
                    flag_groups = [flag_group(flags = ["-O3", "-DNDEBUG"])],
                ),
            ],
        ),
        feature(
            name = "dbg",
            flag_sets = [
                flag_set(
                    actions = all_compile_actions,
                    flag_groups = [flag_group(flags = ["-g", "-O0"])],
                ),
            ],
        ),
    ]

    return cc_common.create_cc_toolchain_config_info(
        ctx = ctx,
        features = features,
        action_configs = [],
        artifact_name_patterns = [],
        cxx_builtin_include_directories = [
            ndk_path + "/toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/include",
            ndk_path + "/toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/include/" + target_triple,
            ndk_path + "/toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/include/c++/v1",
        ],
        toolchain_identifier = "android_bionic_toolchain",
        host_system_name = "x86_64-unknown-linux-gnu",
        target_system_name = target_triple,
        target_cpu = ctx.attr.target_cpu,
        target_libc = "bionic",
        compiler = "clang",
        abi_version = "clang",
        abi_libc_version = "bionic",
        tool_paths = tool_paths,
    )

android_cc_toolchain_config = rule(
    implementation = _impl,
    attrs = {
        "target_triple": attr.string(mandatory = True),
        "target_cpu": attr.string(mandatory = True),
        "api_level": attr.int(default = 24),
        "ndk_path": attr.string(mandatory = True),
    },
)
