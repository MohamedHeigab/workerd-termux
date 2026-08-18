load("@bazel_skylib//rules:write_file.bzl", "write_file")
load("//:build/wd_cc_library.bzl", "wd_cc_library")

# Normalizes an embed name constructed from the embed path.
def normalize_embed_name(file_name):
    return file_name.replace(".", "_").replace("-", "_").replace("/", "_").upper()

# Converts file name or label into string of the corresponding embed name.
def wd_cc_embed_name(src):
    embed_filename = native.package_relative_label(src).name
    return normalize_embed_name(embed_filename)

# Portable embed mechanism using Python code generator
def wd_cc_embed(name, src, base_name = "", is_text = None, **kwargs):
    embed_filename = native.package_relative_label(src).name
    embed_name = normalize_embed_name(embed_filename)

    # Heuristically determine if file is intended to be used as text or binary.
    if is_text == None:
        is_text = embed_filename.endswith(".txt") or embed_filename.endswith(".js") or embed_filename.endswith(".ts")
    pod_data_type = "unsigned char"
    data_type = "kj::ArrayPtr<const kj::byte>"
    if is_text:
        pod_data_type = "char"
        data_type = "kj::StringPtr"

    # Optionally construct output file names from embed file name
    if (base_name == ""):
        base_name = embed_filename.replace(".", "_").replace("-", "_")
    else:
        embed_name = normalize_embed_name(base_name)

    native.genrule(
        name = embed_filename + "_embed_c_gen",
        srcs = [src],
        outs = [base_name + ".embed.c"],
        cmd = """python3 -c '
import sys
src_path = sys.argv[1]
out_path = sys.argv[2]
embed_name = sys.argv[3]
pod_type = sys.argv[4]
is_text = sys.argv[5] == "True"
with open(src_path, "rb") as f:
    data = f.read()
with open(out_path, "w") as f:
    f.write("#include <stddef.h>\\n")
    f.write("__attribute__ ((aligned (8))) const " + pod_type + " " + embed_name + "_begin[] = {\\n")
    if is_text:
        bytes_list = [str(b) for b in data]
        if not data.endswith(b"\\0"):
            bytes_list.append("0")
        f.write(", ".join(bytes_list) + "\\n")
    else:
        f.write(", ".join(str(b) for b in data) + "\\n")
    f.write("};\\n")
    f.write("size_t " + embed_name + "_size = " + str(len(data)) + ";\\n")
' "$(location " + src + ")" "$@" "{embed_name}" "{pod_data_type}" "{is_text}" """.format(
            embed_name = embed_name,
            pod_data_type = pod_data_type,
            is_text = str(is_text),
        ),
    )

    write_file(
        name = embed_filename + "@h",
        out = base_name + ".embed.h",
        content = ["""#pragma once
#include <kj/common.h>
#include <kj/string.h>
#include <stddef.h>
#ifdef __cplusplus
extern "C" {{
#endif
extern const {pod_data_type} {embed_name}_begin[];
extern size_t {embed_name}_size;
#define {embed_name} ({data_type}({embed_name}_begin, {embed_name}_size))
#ifdef __cplusplus
}}
#endif""".format(embed_name = embed_name, data_type = data_type, pod_data_type = pod_data_type)],
    )

    wd_cc_library(
        name = name,
        srcs = [base_name + ".embed.c"],
        hdrs = [base_name + ".embed.h"],
        conlyopts = ["-g0"],
        deps = [
            "@capnp-cpp//src/kj",
        ],
        **kwargs
    )
