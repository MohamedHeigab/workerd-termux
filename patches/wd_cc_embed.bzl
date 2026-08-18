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
        cmd = (
            "python3 -c '\n" +
            "import sys\n" +
            "src_path, out_path, ename, ptype, is_txt = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], (sys.argv[5] == \"True\")\n" +
            "with open(src_path, \"rb\") as f:\n" +
            "    data = f.read()\n" +
            "with open(out_path, \"w\") as f:\n" +
            "    f.write(\"#include <stddef.h>\\n\")\n" +
            "    f.write(\"__attribute__ ((aligned (8))) const \" + ptype + \" \" + ename + \"_begin[] = {\")\n" +
            "    if is_txt:\n" +
            "        vals = [str(b) for b in data]\n" +
            "        if not data.endswith(b\"\\0\"):\n" +
            "            vals.append(\"0\")\n" +
            "        f.write(\", \".join(vals))\n" +
            "    else:\n" +
            "        f.write(\", \".join(str(b) for b in data))\n" +
            "    f.write(\"};\\n\")\n" +
            "    f.write(\"size_t \" + ename + \"_size = \" + str(len(data)) + \";\\n\")\n" +
            "' \"$(location " + src + ")\" \"$@\" \"" + embed_name + "\" \"" + pod_data_type + "\" \"" + str(is_text) + "\""
        ),
    )

    header_content = (
        "#pragma once\n" +
        "#include <kj/common.h>\n" +
        "#include <kj/string.h>\n" +
        "#include <stddef.h>\n" +
        "#ifdef __cplusplus\n" +
        "extern \"C\" {\n" +
        "#endif\n" +
        "extern const " + pod_data_type + " " + embed_name + "_begin[];\n" +
        "extern size_t " + embed_name + "_size;\n" +
        "#define " + embed_name + " (" + data_type + "(" + embed_name + "_begin, " + embed_name + "_size))\n" +
        "#ifdef __cplusplus\n" +
        "}\n" +
        "#endif"
    )

    write_file(
        name = embed_filename + "@h",
        out = base_name + ".embed.h",
        content = [header_content],
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
