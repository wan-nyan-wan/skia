"""
This file specifies a clang toolchain that can run on a Linux host which does depend on any
installed packages from the host machine.

See build_toolchain.bzl for more details on the creation of the toolchain.

It uses the usr subfolder of the built toolchain as a sysroot

It follows the example of:
 - https://docs.bazel.build/versions/4.2.1/tutorial/cc-toolchain-config.html
 - https://github.com/emscripten-core/emsdk/blob/7f39d100d8cd207094decea907121df72065517e/bazel/emscripten_toolchain/crosstool.bzl
"""

load(
    "@bazel_tools//tools/cpp:cc_toolchain_config_lib.bzl",
    "action_config",
    "feature",
    "feature_set",
    "flag_group",
    "flag_set",
    "tool",
    "variable_with_value",
)
load("@bazel_tools//tools/build_defs/cc:action_names.bzl", "ACTION_NAMES")

# The location of the created clang toolchain.
EXTERNAL_TOOLCHAIN = "external/clang_linux_amd64"

def _clang_impl(ctx):
    action_configs = _make_action_configs()
    features = []
    features += _make_default_flags()
    features += _make_diagnostic_flags()
    features += _make_iwyu_flags()

    # https://docs.bazel.build/versions/main/skylark/lib/cc_common.html#create_cc_toolchain_config_info
    # Note, this rule is defined in Java code, not Starlark
    # https://cs.opensource.google/bazel/bazel/+/master:src/main/java/com/google/devtools/build/lib/starlarkbuildapi/cpp/CcModuleApi.java
    return cc_common.create_cc_toolchain_config_info(
        ctx = ctx,
        features = features,
        abi_libc_version = "unknown",
        abi_version = "unknown",
        action_configs = action_configs,
        # This is important because the linker will complain if the libc shared libraries are not
        # under this directory. Because we extract the libc libraries to
        # EXTERNAL_TOOLCHAIN/lib, and the various headers and shared libraries to
        # EXTERNAL_TOOLCHAIN/usr, we make the top level folder the sysroot so the linker can
        # find the referenced libraries (e.g. EXTERNAL_TOOLCHAIN/usr/lib/x86_64-linux-gnu/libc.so
        # is just a text file that refers to "/lib/x86_64-linux-gnu/libc.so.6" and
        # "/lib64/ld-linux-x86-64.so.2" which will use the sysroot as the root).
        builtin_sysroot = EXTERNAL_TOOLCHAIN,
        compiler = "clang",
        host_system_name = "local",
        target_cpu = "k8",
        # It is unclear if target_libc matters.
        target_libc = "glibc-2.31",
        target_system_name = "local",
        toolchain_identifier = "clang-toolchain",
    )

provide_clang_toolchain_config = rule(
    attrs = {},
    provides = [CcToolchainConfigInfo],
    implementation = _clang_impl,
)

def _make_action_configs():
    """
    This function sets up the tools needed to perform the various compile/link actions.

    Bazel normally restricts us to referring to (and therefore running) executables/scripts
    that are in this directory (That is EXEC_ROOT/toolchain). However, the executables we want
    to run are brought in via WORKSPACE.bazel and are located in EXEC_ROOT/external/clang....
    Therefore, we make use of "trampoline scripts" that will call the binaries from the
    toolchain directory.

    These action_configs also let us dynamically specify arguments from the Bazel
    environment if necessary (see cpp_link_static_library_action).
    """

    # https://cs.opensource.google/bazel/bazel/+/master:tools/cpp/cc_toolchain_config_lib.bzl;l=435;drc=3b9e6f201a9a3465720aad8712ab7bcdeaf2e5da
    clang_tool = tool(path = "clang_trampoline.sh")
    lld_tool = tool(path = "lld_trampoline.sh")
    ar_tool = tool(path = "ar_trampoline.sh")

    # https://cs.opensource.google/bazel/bazel/+/master:tools/cpp/cc_toolchain_config_lib.bzl;l=488;drc=3b9e6f201a9a3465720aad8712ab7bcdeaf2e5da
    assemble_action = action_config(
        action_name = ACTION_NAMES.assemble,
        tools = [clang_tool],
    )
    c_compile_action = action_config(
        action_name = ACTION_NAMES.c_compile,
        tools = [clang_tool],
    )
    cpp_compile_action = action_config(
        action_name = ACTION_NAMES.cpp_compile,
        tools = [clang_tool],
    )
    linkstamp_compile_action = action_config(
        action_name = ACTION_NAMES.linkstamp_compile,
        tools = [clang_tool],
    )
    preprocess_assemble_action = action_config(
        action_name = ACTION_NAMES.preprocess_assemble,
        tools = [clang_tool],
    )

    cpp_link_dynamic_library_action = action_config(
        action_name = ACTION_NAMES.cpp_link_dynamic_library,
        tools = [lld_tool],
    )
    cpp_link_executable_action = action_config(
        action_name = ACTION_NAMES.cpp_link_executable,
        # Bazel assumes it is talking to clang when building an executable. There are
        # "-Wl" flags on the command: https://releases.llvm.org/6.0.1/tools/clang/docs/ClangCommandLineReference.html#cmdoption-clang-Wl
        tools = [clang_tool],
    )
    cpp_link_nodeps_dynamic_library_action = action_config(
        action_name = ACTION_NAMES.cpp_link_nodeps_dynamic_library,
        tools = [lld_tool],
    )

    # This is the same rule as
    # https://github.com/emscripten-core/emsdk/blob/7f39d100d8cd207094decea907121df72065517e/bazel/emscripten_toolchain/crosstool.bzl#L143
    # By default, there are no flags or libraries passed to the llvm-ar tool, so
    # we need to specify them. The variables mentioned by expand_if_available are defined
    # https://docs.bazel.build/versions/main/cc-toolchain-config-reference.html#cctoolchainconfiginfo-build-variables
    cpp_link_static_library_action = action_config(
        action_name = ACTION_NAMES.cpp_link_static_library,
        flag_sets = [
            flag_set(
                flag_groups = [
                    flag_group(
                        # https://llvm.org/docs/CommandGuide/llvm-ar.html
                        # replace existing files or insert them if they already exist,
                        # create the file if it doesn't already exist
                        # symbol table should be added
                        # Deterministic timestamps should be used
                        flags = ["rcsD", "%{output_execpath}"],
                        # Despite the name, output_execpath just refers to linker output,
                        # e.g. libFoo.a
                        expand_if_available = "output_execpath",
                    ),
                ],
            ),
            flag_set(
                flag_groups = [
                    flag_group(
                        iterate_over = "libraries_to_link",
                        flag_groups = [
                            flag_group(
                                flags = ["%{libraries_to_link.name}"],
                                expand_if_equal = variable_with_value(
                                    name = "libraries_to_link.type",
                                    value = "object_file",
                                ),
                            ),
                            flag_group(
                                flags = ["%{libraries_to_link.object_files}"],
                                iterate_over = "libraries_to_link.object_files",
                                expand_if_equal = variable_with_value(
                                    name = "libraries_to_link.type",
                                    value = "object_file_group",
                                ),
                            ),
                        ],
                        expand_if_available = "libraries_to_link",
                    ),
                ],
            ),
            flag_set(
                flag_groups = [
                    flag_group(
                        flags = ["@%{linker_param_file}"],
                        expand_if_available = "linker_param_file",
                    ),
                ],
            ),
        ],
        tools = [ar_tool],
    )

    action_configs = [
        assemble_action,
        c_compile_action,
        cpp_compile_action,
        cpp_link_dynamic_library_action,
        cpp_link_executable_action,
        cpp_link_nodeps_dynamic_library_action,
        cpp_link_static_library_action,
        linkstamp_compile_action,
        preprocess_assemble_action,
    ]
    return action_configs

def _make_default_flags():
    """Here we define the flags for certain actions that are always applied."""
    cxx_compile_includes = flag_set(
        actions = [
            ACTION_NAMES.c_compile,
            ACTION_NAMES.cpp_compile,
        ],
        flag_groups = [
            flag_group(
                flags = [
                    # THIS ORDER MATTERS GREATLY. If these are in the wrong order, the
                    # #include_next directives will fail to find the files, causing a compilation
                    # error (or, without -no-canonical-prefixes, a mysterious case where files
                    # are included with an absolute path and fail the build).
                    "-isystem",
                    EXTERNAL_TOOLCHAIN + "/include/c++/v1",
                    "-isystem",
                    EXTERNAL_TOOLCHAIN + "/usr/include",
                    "-isystem",
                    EXTERNAL_TOOLCHAIN + "/lib/clang/13.0.0/include",
                    "-isystem",
                    EXTERNAL_TOOLCHAIN + "/usr/include/x86_64-linux-gnu",
                    # We do not want clang to search in absolute paths for files. This makes
                    # Bazel think we are using an outside resource and fail the compile.
                    "-no-canonical-prefixes",
                ],
            ),
        ],
    )

    cpp_compile_includes = flag_set(
        actions = [
            ACTION_NAMES.cpp_compile,
        ],
        flag_groups = [
            flag_group(
                flags = [
                    "-std=c++17",
                    "-Wno-psabi",  # noisy
                ],
            ),
        ],
    )

    link_exe_flags = flag_set(
        actions = [ACTION_NAMES.cpp_link_executable],
        flag_groups = [
            flag_group(
                flags = [
                    "-fuse-ld=lld",
                    # We chose to use the llvm runtime, not the gcc one because it is already
                    # included in the clang binary
                    "--rtlib=compiler-rt",
                    "-std=c++17",
                    # We statically include these libc++ libraries so they do not need to be
                    # on a developer's machine (they can be tricky to get).
                    EXTERNAL_TOOLCHAIN + "/lib/libc++.a",
                    EXTERNAL_TOOLCHAIN + "/lib/libc++abi.a",
                    EXTERNAL_TOOLCHAIN + "/lib/libunwind.a",
                    # Dynamically Link in the other parts of glibc (not needed in glibc 2.34+)
                    "-lpthread",
                    "-lm",
                    "-ldl",
                ],
            ),
        ],
    )
    return [feature(
        "default_flags",
        enabled = True,
        flag_sets = [
            cxx_compile_includes,
            cpp_compile_includes,
            link_exe_flags,
        ],
    )]

def _make_diagnostic_flags():
    """Here we define the flags that can be turned on via features to yield debug info."""
    cxx_diagnostic = flag_set(
        actions = [
            ACTION_NAMES.c_compile,
            ACTION_NAMES.cpp_compile,
        ],
        flag_groups = [
            flag_group(
                flags = [
                    "--trace-includes",
                    "-v",
                ],
            ),
        ],
    )

    link_diagnostic = flag_set(
        actions = [ACTION_NAMES.cpp_link_executable],
        flag_groups = [
            flag_group(
                flags = [
                    "-Wl,--verbose",
                    "-v",
                ],
            ),
        ],
    )

    link_search_dirs = flag_set(
        actions = [ACTION_NAMES.cpp_link_executable],
        flag_groups = [
            flag_group(
                flags = [
                    "--print-search-dirs",
                ],
            ),
        ],
    )
    return [
        # Running a Bazel command with --features diagnostic will cause the compilation and
        # link steps to be more verbose.
        feature(
            "diagnostic",
            enabled = False,
            flag_sets = [
                cxx_diagnostic,
                link_diagnostic,
            ],
        ),
        # Running a Bazel command with --features print_search_dirs will cause the link to fail
        # but directories searched for libraries, etc will be displayed.
        feature(
            "print_search_dirs",
            enabled = False,
            flag_sets = [
                link_search_dirs,
            ],
        ),
    ]

def _make_iwyu_flags():
    """Here we define the flags that signal whether or not to enforce IWYU."""

    # https://bazel.build/docs/cc-toolchain-config-reference#features
    opt_file_into_iwyu = flag_set(
        actions = [
            ACTION_NAMES.c_compile,
            ACTION_NAMES.cpp_compile,
        ],
        flag_groups = [
            flag_group(
                flags = [
                    # This define does not impact compilation, but it acts as a signal to the
                    # clang_trampoline.sh whether check the file with include-what-you-use
                    # A define was chosen because it is ignored by clang and IWYU, but can be
                    # easily found with bash.
                    "-DSKIA_ENFORCE_IWYU_FOR_THIS_FILE",
                ],
            ),
        ],
    )

    return [
        feature(
            # The IWYU checks can add some overhead to the build (1-5 seconds per file), so we only
            # want to run them sometimes. By adding --feature skia_enforce_iwyu to the Bazel
            # command, this will turn on the checking (for all files that have not been opted-out).
            "skia_enforce_iwyu",
            enabled = False,
        ),
        feature(
            "skia_opt_file_into_iwyu",
            enabled = False,
            flag_sets = [
                opt_file_into_iwyu,
            ],
            # If the skia_enforce_iwyu features is not enabled (e.g. globally via a CLI flag), we
            # will not run the IWYU analysis on any files.
            requires = [
                feature_set(features = [
                    "skia_enforce_iwyu",
                ]),
            ],
        ),
    ]
