#
# Copyright (c) 2024-2025, Arm Limited and affiliates.
#
# Part of the Arm Toolchain project, under the Apache License v2.0 with LLVM Exceptions.
# See https://llvm.org/LICENSE.txt for license information.
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#
# ​​​​​Changes from Qualcomm Technologies, Inc. are provided under the following license:
# Copyright (c) Qualcomm Technologies, Inc. and/or its subsidiaries.
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#

# CMake build for a library variant, combining a chosen C library
# with builtins from compiler-rt and libcx/libcxxabi/libunwind

cmake_minimum_required(VERSION 3.20)

project(embedded-runtimes)

# Root directory of the CMake scrpts.
set(TOOLCHAIN_SOURCE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/..)
# Root directory of the llvm-project source.
set(llvmproject_src_dir ${TOOLCHAIN_SOURCE_DIR}/../..)

# CMake arguments are loaded from the JSON file depending on which C
# library is used, so this must be set before the JSON is processed.
set(C_LIBRARY "picolibc" CACHE STRING "Which C library to use.")
set_property(CACHE C_LIBRARY PROPERTY STRINGS picolibc musl-embedded)

set(VARIANT_JSON "" CACHE STRING "JSON file to load args from.")
if(VARIANT_JSON)
    file(READ ${VARIANT_JSON} variant_json_read)
    # Load arguments common to all libraries.
    string(JSON json_args GET ${variant_json_read} "args" "common")
    string(JSON json_args_len LENGTH ${json_args})
    math(EXPR json_args_len_dec "${json_args_len} - 1")
    foreach(json_idx RANGE ${json_args_len_dec})
        string(JSON json_param MEMBER ${json_args} ${json_idx})
        string(JSON json_val GET ${json_args} ${json_param})
        string(JSON json_val_type TYPE ${json_args} ${json_param})
        set(${json_param}_def ${json_val})
    endforeach()
    # Load arguments specific to the chosen library, overwriting any existing values.
    string(JSON json_args GET ${variant_json_read} "args" ${C_LIBRARY})
    string(JSON json_args_len LENGTH ${json_args})
    math(EXPR json_args_len_dec "${json_args_len} - 1")
    foreach(json_idx RANGE ${json_args_len_dec})
        string(JSON json_param MEMBER ${json_args} ${json_idx})
        string(JSON json_val GET ${json_args} ${json_param})
        string(JSON json_val_type TYPE ${json_args} ${json_param})
        set(${json_param}_def ${json_val})
    endforeach()
endif()

# Default values will be populated by the json above.
# Any user specified options will override the default.
set(TARGET_ARCH ${TARGET_ARCH_def} CACHE STRING "Architecture being targetted.")
set(VARIANT ${VARIANT_def} CACHE STRING "Name for the variant, usually architecture + suffix.")
set(COMPILE_FLAGS ${COMPILE_FLAGS_def} CACHE STRING "Flags required to build the variant.")
set(TEST_EXECUTOR ${TEST_EXECUTOR_def} CACHE STRING "Program used to run tests.")
set_property(CACHE TEST_EXECUTOR PROPERTY STRINGS qemu)

set(QEMU_MACHINE ${QEMU_MACHINE_def} CACHE STRING "Machine for QEMU to emulate.")
set(QEMU_CPU ${QEMU_CPU_def} CACHE STRING "CPU for QEMU to emulate.")
set(QEMU_PARAMS ${QEMU_PARAMS_def} CACHE STRING "Any additional parameters to pass to QEMU.")

set(FLASH_ADDRESS ${FLASH_ADDRESS_def} CACHE STRING "")
set(FLASH_SIZE ${FLASH_SIZE_def} CACHE STRING "")
set(RAM_ADDRESS ${RAM_ADDRESS_def} CACHE STRING "")
set(RAM_SIZE ${RAM_SIZE_def} CACHE STRING "")

set(ENABLE_EXCEPTIONS ${ENABLE_EXCEPTIONS_def} CACHE BOOL "Enable C++ exceptions.")
set(ENABLE_RTTI ${ENABLE_RTTI_def} CACHE BOOL "Enable C++ exceptions.")

set(SUPPORTED_LIBRARY_BUILD_TYPES minsizerelease release releasewithdebuginfo)
if(NOT LIBRARY_BUILD_TYPE_def IN_LIST SUPPORTED_LIBRARY_BUILD_TYPES)
    string(REPLACE ";" ", " SUPPORTED_LIBRARY_BUILD_TYPES_STR "${SUPPORTED_LIBRARY_BUILD_TYPES}")
    message(FATAL_ERROR "Unsupported LIBRARY_BUILD_TYPE value. Supported values are: ${SUPPORTED_LIBRARY_BUILD_TYPES_STR}")
endif()
set(LIBRARY_BUILD_TYPE ${LIBRARY_BUILD_TYPE_def} CACHE STRING "Build type to use in library builds.")
set_property(CACHE LIBRARY_BUILD_TYPE PROPERTY STRINGS ${SUPPORTED_LIBRARY_BUILD_TYPES})

set(ENABLE_CXX_LIBS ${ENABLE_CXX_LIBS_def} CACHE BOOL "Build CXX libs")
set(ENABLE_LIBC_TESTS ${ENABLE_LIBC_TESTS_def} CACHE BOOL "Enable libc tests (picolibc only).")
set(ENABLE_COMPILER_RT_TESTS ${ENABLE_COMPILER_RT_TESTS_def} CACHE BOOL "Enable compiler-rt tests.")
set(ENABLE_LIBCXX_TESTS ${ENABLE_LIBCXX_TESTS_def} CACHE BOOL "Enable libcxx tests.")
set(LLVM_BINARY_DIR "" CACHE PATH "Path to LLVM toolchain root to build libraries with")

# Set up a few arbitrary pass-through flags for MUSL. This probably isn't the best idea,
# but historically, our flag usage is such that it is a bit unclear how to do this in
# a more princicpled way. This should be revisited and probably clean up, but for now
# just mirror what we used to do.
set(EXTRA_MUSL_CONFIG_FLAGS ${EXTRA_MUSL_CONFIG_FLAGS_def} CACHE BOOL "Extra configure options for musl-embedded.")
set(EXTRA_MUSL_CFLAGS ${EXTRA_MUSL_CFLAGS_def} CACHE BOOL "Extra flags to be used when compiling musl-embedded.")

set(PROJECT_PREFIX "subproj" CACHE STRING "Directory to build subprojects in.")
set(VARIANT_BUILD_ID "${VARIANT}" CACHE STRING "Name to use to identify build directories." )

# A '.' character is used in junit xml to split classes/groups.
# Variants such as armv8m.main need to be renamed.
string(REPLACE "." "_" variant_xml_name ${VARIANT})

# Temporary location to collect the libraries as they are built.
set(TEMP_LIB_DIR "${CMAKE_CURRENT_BINARY_DIR}/tmp_install")

find_package(Python3 REQUIRED COMPONENTS Interpreter)

include(ExternalProject)

# If a compiler launcher such as ccache has been set, it should be
# passed down to each subproject build.
set(compiler_launcher_cmake_args "")
if(CMAKE_C_COMPILER_LAUNCHER)
    list(APPEND compiler_launcher_cmake_args "-DCMAKE_C_COMPILER_LAUNCHER=${CMAKE_C_COMPILER_LAUNCHER}")
endif()
if(CMAKE_CXX_COMPILER_LAUNCHER)
    list(APPEND compiler_launcher_cmake_args "-DCMAKE_CXX_COMPILER_LAUNCHER=${CMAKE_CXX_COMPILER_LAUNCHER}")
endif()

if(TARGET_ARCH MATCHES "^aarch64")
    set(target_triple "aarch64-none-elf")
    set(cpu_family aarch64)
else()
    # Choose the target triple so that compiler-rt will do the
    # right thing. We can't always put the exact target
    # architecture in the triple, because compiler-rt's cmake
    # system doesn't recognize every possible Arm architecture
    # version. So mostly we just say 'arm' and control the arch
    # version via -march=armv7m (or whatever).
    # Exceptions are architectures pre-armv7, which compiler-rt expects to
    # see in the triple because that's where it looks to decide whether to
    # use specific assembly sources.
    if(TARGET_ARCH MATCHES "^armv[4-6]")
        set(target_triple "${TARGET_ARCH}-none-eabi")
    else()
        set(target_triple "arm-none-eabi")
    endif()
    if(COMPILE_FLAGS MATCHES "-mfloat-abi=hard")
        # Also, compiler-rt looks in the ABI component of the
        # triple to decide whether to use the hard float ABI.
        set(target_triple "${target_triple}hf")
    endif()
    set(cpu_family arm)
endif()

# Create a single target for all testing. If no testing is enabled, this
# will simply do nothing.
add_custom_target(check-all)

# If any testing is enabled, prepare test executor settings.
if(ENABLE_LIBC_TESTS OR ENABLE_COMPILER_RT_TESTS OR ENABLE_LIBCXX_TESTS)
    # Flags required to link tests.
    if(C_LIBRARY STREQUAL picolibc)
        if(TEST_EXECUTOR STREQUAL qemu)
            set(picocrt "crt0-semihost")
        endif()
        set(test_link_flags "-nostartfiles -l${picocrt} -lsemihost -T picolibcpp.ld")
    else()
        message(FATAL_ERROR "Tests can only be enabled using picolibc.")
    endif()

    set(external_lit_path "${LLVM_BINARY_DIR}/bin/llvm-lit")
    set(default_lit_args "-sv --show-xfail --show-unsupported --show-excluded")
    if (MSVC OR XCODE)
        set(default_lit_args "${default_lit_args} --no-progress-bar")
    endif()
    set(LLVM_LIT_ARGS "${default_lit_args}" CACHE STRING "Default options for lit")

    if(TEST_EXECUTOR STREQUAL qemu)
        if(TARGET_ARCH MATCHES "^aarch64")
            find_program(QEMU_EXECUTABLE qemu-system-aarch64 REQUIRED)
        else()
            find_program(QEMU_EXECUTABLE qemu-system-arm REQUIRED)
        endif()

        # Use colon as a separator because comma and semicolon are used for
        # other purposes in CMake.
        string(REPLACE " " ":" qemu_params_list "${QEMU_PARAMS}")

        set(test_executor_params --qemu-command ${QEMU_EXECUTABLE} --qemu-machine ${QEMU_MACHINE})
        if(QEMU_CPU)
            list(APPEND test_executor_params --qemu-cpu ${QEMU_CPU})
        endif()
        if(qemu_params_list)
            list(APPEND test_executor_params "--qemu-params=${qemu_params_list}")
        endif()
        set(
            lit_test_executor
            ${CMAKE_CURRENT_SOURCE_DIR}/test-support/lit-exec-qemu.py
            ${test_executor_params}
        )
    endif()
    list(JOIN lit_test_executor " " lit_test_executor)
endif()

set(compile_arch_flags "--target=${target_triple} ${COMPILE_FLAGS} --sysroot ${TEMP_LIB_DIR}")
# Compiling the libraries benefits from some extra optimization
# flags, and requires a sysroot.
set(lib_compile_flags "${compile_arch_flags} -ffunction-sections -fdata-sections")

# Generic target names for the C library.
# Declare these now, since compiler-rt requires the 'install' dependency.
add_custom_target(clib-configure)
add_custom_target(clib-build)
add_custom_target(clib-install)

# At this point it's been asserted that LIBRARY_BUILD_TYPE value is valid.
if(LIBRARY_BUILD_TYPE STREQUAL minsizerelease)
    set(LIBRARY_CMAKE_BUILD_TYPE MinSizeRel)
    set(LIBRARY_MESON_BUILD_TYPE minsize)
elseif(LIBRARY_BUILD_TYPE STREQUAL release)
    set(LIBRARY_CMAKE_BUILD_TYPE Release)
    set(LIBRARY_MESON_BUILD_TYPE release)
elseif(LIBRARY_BUILD_TYPE STREQUAL releasewithdebuginfo)
    set(LIBRARY_CMAKE_BUILD_TYPE RelWithDebInfo)
    set(LIBRARY_MESON_BUILD_TYPE debugoptimized)
endif()

###############################################################################
# compiler-rt
###############################################################################

# We can't always put the exact target
# architecture in the triple, because compiler-rt's cmake
# system doesn't recognize every possible Arm architecture
# version. So mostly we just say 'arm' and control the arch
# version via -march=armv7m (or whatever).
# Exceptions are architectures pre-armv7, which compiler-rt expects to
# see in the triple because that's where it looks to decide whether to
# use specific assembly sources.
if(NOT target_triple MATCHES "^(aarch64-none-elf|arm-none-eabi|armv[4-6])")
    message(FATAL_ERROR "\
Target triple name \"${target_triple}\" not compatible with compiler-rt.
Use -march to specify the architecture.")
endif()
# Also, compiler-rt looks in the ABI component of the
# triple to decide whether to use the hard float ABI.
if(flags MATCHES "-mfloat-abi=hard" AND NOT target_triple MATCHES "-eabihf$")
    message(FATAL_ERROR "\
Hard-float library with target triple \"${target_triple}\" must end \"-eabihf\"")
endif()
string(REPLACE "-none-" "-unknown-none-" normalized_target_triple ${target_triple})

if(ENABLE_COMPILER_RT_TESTS)
    # Generate xfails for compiler-rt.
    set(compiler_rt_lit_xfails_path "${CMAKE_CURRENT_BINARY_DIR}/${VARIANT}_compiler-rt_lit_xfails.txt")
    set(compiler_rt_lit_args "--path=${LLVM_BINARY_DIR}/bin @${compiler_rt_lit_xfails_path} ${LLVM_LIT_ARGS}")
    add_custom_target(
        compiler-rt-xfail-lit-args
        COMMAND ${Python3_EXECUTABLE}
            ${CMAKE_CURRENT_SOURCE_DIR}/test-support/xfails.py
            --variant ${VARIANT}
            --project compiler-rt
            --libc ${C_LIBRARY}
            --output-args ${compiler_rt_lit_xfails_path}
    )

    set(compiler_rt_test_flags "${lib_compile_flags} ${test_link_flags}")
    set(
        compiler_rt_test_cmake_args
        -DCOMPILER_RT_INCLUDE_TESTS=ON
        -DCOMPILER_RT_EMULATOR=${lit_test_executor}
        -DCOMPILER_RT_TEST_COMPILER=${LLVM_BINARY_DIR}/bin/clang
        -DCOMPILER_RT_TEST_COMPILER_CFLAGS=${compiler_rt_test_flags}
        -DLLVM_INCLUDE_TESTS=ON
        -DLLVM_LIT_ARGS=${compiler_rt_lit_args}
        -DLLVM_EXTERNAL_LIT=${external_lit_path}
    )
endif()

ExternalProject_Add(
    compiler_rt
    STAMP_DIR ${PROJECT_PREFIX}/compiler_rt/${VARIANT_BUILD_ID}/stamp
    BINARY_DIR ${PROJECT_PREFIX}/compiler_rt/${VARIANT_BUILD_ID}/build
    DOWNLOAD_DIR ${PROJECT_PREFIX}/compiler_rt/${VARIANT_BUILD_ID}/dl
    TMP_DIR ${PROJECT_PREFIX}/compiler_rt/${VARIANT_BUILD_ID}/tmp
    SOURCE_DIR ${llvmproject_src_dir}/runtimes
    INSTALL_DIR compiler-rt/install
    CMAKE_ARGS
    ${compiler_launcher_cmake_args}
    -DCMAKE_AR=${LLVM_BINARY_DIR}/bin/llvm-ar${CMAKE_EXECUTABLE_SUFFIX}
    -DCMAKE_ASM_COMPILER_TARGET=${target_triple}
    -DCMAKE_ASM_FLAGS=${lib_compile_flags}
    -DCMAKE_BUILD_TYPE=${LIBRARY_CMAKE_BUILD_TYPE}
    -DCMAKE_CXX_COMPILER=${LLVM_BINARY_DIR}/bin/clang++${CMAKE_EXECUTABLE_SUFFIX}
    -DCMAKE_CXX_COMPILER_TARGET=${target_triple}
    -DCMAKE_CXX_FLAGS=${lib_compile_flags}
    -DCMAKE_C_COMPILER=${LLVM_BINARY_DIR}/bin/clang${CMAKE_EXECUTABLE_SUFFIX}
    -DCMAKE_C_COMPILER_TARGET=${target_triple}
    -DCMAKE_C_FLAGS=${lib_compile_flags}
    -DCMAKE_INSTALL_MESSAGE=${CMAKE_INSTALL_MESSAGE}
    -DCMAKE_INSTALL_PREFIX=<INSTALL_DIR>
    -DCMAKE_NM=${LLVM_BINARY_DIR}/bin/llvm-nm${CMAKE_EXECUTABLE_SUFFIX}
    -DCMAKE_RANLIB=${LLVM_BINARY_DIR}/bin/llvm-ranlib${CMAKE_EXECUTABLE_SUFFIX}
    -DCMAKE_SYSTEM_NAME=Generic
    -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY
    -DCOMPILER_RT_BAREMETAL_BUILD=ON
    -DCOMPILER_RT_BUILD_LIBFUZZER=OFF
    -DCOMPILER_RT_BUILD_PROFILE=OFF
    -DCOMPILER_RT_BUILD_SANITIZERS=OFF
    -DCOMPILER_RT_BUILD_XRAY=OFF
    -DCOMPILER_RT_DEFAULT_TARGET_ONLY=ON
    -DLLVM_ENABLE_RUNTIMES=compiler-rt
    -DRUNTIME_VARIANT_NAME=${VARIANT}
    -DLLVM_ENABLE_PER_TARGET_RUNTIME_DIR=ON
    ${compiler_rt_test_cmake_args}
    STEP_TARGETS configure build install
    USES_TERMINAL_CONFIGURE TRUE
    USES_TERMINAL_BUILD TRUE
    USES_TERMINAL_INSTALL TRUE
    LIST_SEPARATOR ,
    CONFIGURE_HANDLED_BY_BUILD TRUE
    INSTALL_COMMAND ${CMAKE_COMMAND} --install .
    # Copy compiler-rt lib directory, moving libraries out of their
    # target-specific subdirectory.
    COMMAND
        ${CMAKE_COMMAND}
        -E copy_directory
        <INSTALL_DIR>/lib/${normalized_target_triple}
        "${TEMP_LIB_DIR}/lib"
)

add_custom_target(check-compiler-rt)
add_dependencies(check-all check-compiler-rt)
if(ENABLE_COMPILER_RT_TESTS)
    ExternalProject_Add_Step(
        compiler_rt
        check-compiler-rt
        COMMAND "${CMAKE_COMMAND}" --build <BINARY_DIR> --target check-compiler-rt
        COMMAND ${Python3_EXECUTABLE}
        ${CMAKE_CURRENT_SOURCE_DIR}/test-support/modify-compiler-rt-xml.py
        --dir <BINARY_DIR>
        --variant ${variant_xml_name}
        USES_TERMINAL TRUE
        EXCLUDE_FROM_MAIN TRUE
        ALWAYS TRUE
    )
    ExternalProject_Add_StepTargets(compiler_rt check-compiler-rt)
    ExternalProject_Add_StepDependencies(
        compiler_rt
        check-compiler-rt
        compiler_rt-build
        clib-install
        compiler-rt-xfail-lit-args
    )
    add_dependencies(check-compiler-rt compiler_rt-check-compiler-rt)
endif()

###############################################################################
# picolibc
###############################################################################

if(C_LIBRARY STREQUAL picolibc)
    include(${TOOLCHAIN_SOURCE_DIR}/cmake/fetch_picolibc.cmake)
    include(${CMAKE_CURRENT_SOURCE_DIR}/to_meson_list.cmake)

    # For building picolibc use Meson.
    # Although picolibc has support for building with CMake, the Meson code
    # is more mature and works better with LLVM.
    find_program(MESON_EXECUTABLE meson REQUIRED)

    if(CMAKE_INSTALL_MESSAGE STREQUAL NEVER)
        set(MESON_INSTALL_QUIET "--quiet")
    endif()

    if(LIBRARY_BUILD_TYPE MATCHES "minsizerelease")
        # In the past we've built our size-optimized libraries at -Os but Meson
        # will set -Oz when the `minsize` buildtype is used. Override that.
        set(picolibc_opt_flags "-Os")
    endif()

    # Set meson_c_args to a comma-separated list of the clang path
    # and flags e.g. 'path/to/clang', '--target=armv6m-none-eabi',
    # '-march=armv6m'
    set(picolibc_flags "${LLVM_BINARY_DIR}/bin/clang${CMAKE_EXECUTABLE_SUFFIX} ${lib_compile_flags}")
    set(picolibcpp_flags "${LLVM_BINARY_DIR}/bin/clang++${CMAKE_EXECUTABLE_SUFFIX} ${lib_compile_flags}")
    if(CMAKE_C_COMPILER_LAUNCHER)
        set(picolibc_flags "${CMAKE_C_COMPILER_LAUNCHER} ${picolibc_flags}")
    endif()
    separate_arguments(picolibc_flags)
    separate_arguments(picolibcpp_flags)
    to_meson_list("${picolibc_flags}" picolibc_meson_flags)
    to_meson_list("${picolibcpp_flags}" picolibcpp_meson_flags)

    if(ENABLE_LIBC_TESTS)
        set(picolibc_test_executor_bin ${CMAKE_CURRENT_SOURCE_DIR}/test-support/picolibc-test-wrapper.py)
        to_meson_list("${test_executor_params}" meson_test_executor_params)
    endif()

    configure_file(${CMAKE_CURRENT_SOURCE_DIR}/meson-cross-build.txt.in ${CMAKE_CURRENT_BINARY_DIR}/meson-cross-build.txt @ONLY)

    ExternalProject_Add(
        picolibc
        STAMP_DIR ${PROJECT_PREFIX}/picolibc/${VARIANT_BUILD_ID}/stamp
        BINARY_DIR ${PROJECT_PREFIX}/picolibc/${VARIANT_BUILD_ID}/build
        DOWNLOAD_DIR ${PROJECT_PREFIX}/picolibc/${VARIANT_BUILD_ID}/dl
        TMP_DIR ${PROJECT_PREFIX}/picolibc/${VARIANT_BUILD_ID}/tmp
        SOURCE_DIR ${picolibc_SOURCE_DIR}
        INSTALL_DIR ${TEMP_LIB_DIR}
        DEPENDS compiler_rt-install
        CONFIGURE_COMMAND
            ${MESON_EXECUTABLE}
            setup
            -Dincludedir=include
            -Dlibdir=lib
            -Dspecsdir=none
            -Dmultilib=false
            -Ddebug=false
            # Pass opt flags through c/cpp_args rather than in the cross file as
            # we need them to override what Meson will set automatically.
            -Dc_args=${picolibc_opt_flags}
            -Dcpp_args=${picolibc_opt_flags}
            -Dtests-enable-stack-protector=false
            -Dtest-machine=${TEST_EXECUTOR}
            -Dtests=false
            --prefix <INSTALL_DIR>
            --cross-file ${CMAKE_CURRENT_BINARY_DIR}/meson-cross-build.txt
            --buildtype=${LIBRARY_MESON_BUILD_TYPE}
            <SOURCE_DIR>
        BUILD_COMMAND ${MESON_EXECUTABLE} compile
        INSTALL_COMMAND ${MESON_EXECUTABLE} install ${MESON_INSTALL_QUIET}
        USES_TERMINAL_CONFIGURE TRUE
        USES_TERMINAL_BUILD TRUE
        USES_TERMINAL_INSTALL TRUE
        LIST_SEPARATOR ,
        CONFIGURE_HANDLED_BY_BUILD TRUE
        TEST_EXCLUDE_FROM_MAIN TRUE
        STEP_TARGETS configure build install
    )

    add_custom_target(check-picolibc)
    add_dependencies(check-all check-picolibc)
    if(ENABLE_LIBC_TESTS)
        # meson builds the tests at the same time as the library.
        # So reconfigure to enable tests at a later point.
        ExternalProject_Add_Step(
            picolibc
            compile-tests
            COMMAND ${MESON_EXECUTABLE} setup -Dtests=true --reconfigure <BINARY_DIR> <SOURCE_DIR>
            COMMAND ${MESON_EXECUTABLE} compile -C <BINARY_DIR>
            USES_TERMINAL TRUE
            EXCLUDE_FROM_MAIN TRUE
        )
        ExternalProject_Add_StepTargets(picolibc compile-tests)
        ExternalProject_Add_StepDependencies(
            picolibc
            compile-tests
            picolibc-build
            compiler_rt-install
        )

        # Step target to run the picolibc test via meson.
        ExternalProject_Add_Step(
            picolibc
            check-meson
            COMMAND ${MESON_EXECUTABLE} test -C <BINARY_DIR> --no-rebuild
            USES_TERMINAL TRUE
            EXCLUDE_FROM_MAIN TRUE
            ALWAYS TRUE
            DEPENDEES compile-tests
        )
        ExternalProject_Add_StepTargets(picolibc check-meson)

        # Generate lit wrappers for the tests.
        set(picolibc_lit_dir ${CMAKE_CURRENT_BINARY_DIR}/picolibc_lit)
        ExternalProject_Add_Step(
            picolibc
            gen-lit-tests
            COMMAND ${Python3_EXECUTABLE} ${CMAKE_CURRENT_SOURCE_DIR}/test-support/gen-picolibc-lit-tests.py
                --meson ${MESON_EXECUTABLE}
                --build <BINARY_DIR>
                --output ${picolibc_lit_dir}
                --name picolibc-${variant_xml_name}
            USES_TERMINAL TRUE
            EXCLUDE_FROM_MAIN TRUE
            DEPENDEES compile-tests
        )
        ExternalProject_Add_StepTargets(picolibc gen-lit-tests)

        # Generate xfails for picolibc.
        set(picolibc_lit_xfails_path "${picolibc_lit_dir}/${VARIANT}_picolibc_lit_xfails.txt")
        add_custom_target(
            picolibc-xfail-lit-args
            COMMAND ${Python3_EXECUTABLE}
                ${CMAKE_CURRENT_SOURCE_DIR}/test-support/xfails.py
                --variant ${VARIANT}
                --project picolibc
                --libc ${C_LIBRARY}
                --output-args ${picolibc_lit_xfails_path}
        )

        set(check_lit_cmd "${Python3_EXECUTABLE} ${external_lit_path} ${picolibc_lit_dir} ${LLVM_LIT_ARGS} @${picolibc_lit_xfails_path}")
        # LLVM_LIT_ARGS has space separated flags, but the
        # step COMMAND needs a list of arguments.
        separate_arguments(check_lit_cmd)

        # Step target to run the picolibc test via lit.
        ExternalProject_Add_Step(
            picolibc
            check-lit
            COMMAND ${check_lit_cmd}
            USES_TERMINAL TRUE
            EXCLUDE_FROM_MAIN TRUE
            ALWAYS TRUE
            DEPENDEES gen-lit-tests
        )
        ExternalProject_Add_StepTargets(picolibc check-lit)
        ExternalProject_Add_StepDependencies(
            picolibc
            check-lit
            picolibc-xfail-lit-args
        )
        add_dependencies(check-picolibc picolibc-check-lit)
        add_dependencies(clib-build ${C_LIBRARY}-compile-tests)
    endif()

endif()

###############################################################################
# musl-embedded
###############################################################################
if(C_LIBRARY STREQUAL musl-embedded)
    if(ENABLE_LIBC_TESTS)
        message(FATAL_ERROR "Tests cannot be enabled using musl-embedded.")
    endif()

    if(WIN32)
        message(FATAL_ERROR "Building MUSL is not supported on Windows hosts")
    endif()

    include(${TOOLCHAIN_SOURCE_DIR}/cmake/fetch_musl-embedded.cmake)

    include(ProcessorCount)
    set(make_flags)
    ProcessorCount(nproc)
    if(NOT nproc EQUAL 0)
        set(make_flags -j${nproc})
    endif()

    if(LIBRARY_BUILD_TYPE STREQUAL minsizerelease)
        set(musl_opt_flags "-Os")
    elseif((LIBRARY_BUILD_TYPE STREQUAL release) OR (LIBRARY_BUILD_TYPE STREQUAL releasewithdebuginfo))
        set(musl_opt_flags "-O3")
    endif()

    # FIXME: if we need the extra `uselocks`/`standalone` variants, we
    # can add a passthrough here and make them separate variants.
    set(musl_embedded_flags
        --disable-wrapper
        --quic-arm-baremetal
        --disable-visibility
        ${EXTRA_MUSL_CONFIG_FLAGS}
        "CROSS_COMPILE=${LLVM_BINARY_DIR}/bin/llvm-"
        "CC=${LLVM_BINARY_DIR}/bin/clang --target=${target_triple} -fuse-ld=eld"
        "CFLAGS=${lib_compile_flags} ${musl_opt_flags} -fPIC -fvisibility=hidden -DVISIBILITY_HIDDEN -fno-rounding-math ${EXTRA_MUSL_CFLAGS}"
        "LIBCC=${TEMP_LIB_DIR}/libclang_rt.builtins.a")

    ExternalProject_Add(
        ${C_LIBRARY}
        STAMP_DIR ${PROJECT_PREFIX}/${C_LIBRARY}/${VARIANT_BUILD_ID}/stamp
        BINARY_DIR ${PROJECT_PREFIX}/${C_LIBRARY}/${VARIANT_BUILD_ID}/build
        DOWNLOAD_DIR ${PROJECT_PREFIX}/${C_LIBRARY}/${VARIANT_BUILD_ID}/dl
        TMP_DIR ${PROJECT_PREFIX}/${C_LIBRARY}/${VARIANT_BUILD_ID}/tmp
        SOURCE_DIR ${musl_SOURCE_DIR}
        INSTALL_DIR ${TEMP_LIB_DIR}
        DEPENDS compiler_rt-install
        CONFIGURE_COMMAND
            <SOURCE_DIR>/configure
            --prefix=${TEMP_LIB_DIR}
            ${musl_embedded_flags}
        BUILD_COMMAND
            make ${make_flags}
        INSTALL_COMMAND
            make install
        USES_TERMINAL_CONFIGURE TRUE
        USES_TERMINAL_BUILD TRUE
        USES_TERMINAL_INSTALL TRUE
        # Always run the build command so that incremental builds are correct.
        CONFIGURE_HANDLED_BY_BUILD TRUE
        TEST_EXCLUDE_FROM_MAIN TRUE
        STEP_TARGETS configure build install
    )
endif()


add_dependencies(clib-configure ${C_LIBRARY}-configure)
add_dependencies(clib-build ${C_LIBRARY}-build)
add_dependencies(clib-install ${C_LIBRARY}-install)

###############################################################################
# runtimes (libcxx, libcxxabi, libunwind)
###############################################################################

if(ENABLE_CXX_LIBS)
    if(C_LIBRARY STREQUAL picolibc)
        set(cxxlibs_extra_cmake_options
            -DLIBCXXABI_ENABLE_THREADS=OFF
            -DLIBCXX_ENABLE_MONOTONIC_CLOCK=OFF
            -DLIBCXX_ENABLE_RANDOM_DEVICE=OFF
            -DLIBCXX_ENABLE_THREADS=OFF
            -DLIBCXX_ENABLE_WIDE_CHARACTERS=OFF
            -DLIBUNWIND_ENABLE_THREADS=OFF
            -DLIBCXXABI_ENABLE_EXCEPTIONS=${ENABLE_EXCEPTIONS}
            -DLIBCXXABI_ENABLE_STATIC_UNWINDER=${ENABLE_EXCEPTIONS}
            -DLIBCXX_ENABLE_EXCEPTIONS=${ENABLE_EXCEPTIONS}
            -DLIBCXX_ENABLE_RTTI=${ENABLE_RTTI}
            -DRUNTIMES_USE_LIBC=picolibc
        )
        if(ENABLE_LIBCXX_TESTS)
            # Generate xfails for libxx.
            set(libcxx_lit_xfails_path "${CMAKE_CURRENT_BINARY_DIR}/${VARIANT}_libcxx_lit_xfails.txt")
            set(libcxx_lit_args "@${libcxx_lit_xfails_path} ${LLVM_LIT_ARGS}"
            )
            add_custom_target(
                libcxx-xfail-lit-args
                COMMAND ${Python3_EXECUTABLE}
                    ${CMAKE_CURRENT_SOURCE_DIR}/test-support/xfails.py
                    --variant ${VARIANT}
                    --project libcxx
                    --libc ${C_LIBRARY}
                    --output-arg ${libcxx_lit_xfails_path}
            )
            set(cxxlibs_test_cmake_options
                -DLIBCXX_TEST_CONFIG=${CMAKE_CURRENT_SOURCE_DIR}/test-support/llvm-libc++-picolibc.cfg.in
                -DLIBCXX_TEST_PARAMS=executor=${lit_test_executor}
                -DLIBCXXABI_TEST_CONFIG=${CMAKE_CURRENT_SOURCE_DIR}/test-support/llvm-libc++abi-picolibc.cfg.in
                -DLIBCXXABI_TEST_PARAMS=executor=${lit_test_executor}
                -DLIBUNWIND_TEST_CONFIG=${CMAKE_CURRENT_SOURCE_DIR}/test-support/llvm-libunwind-picolibc.cfg.in
                -DLIBUNWIND_TEST_PARAMS=executor=${lit_test_executor}
                -DRUNTIME_TEST_ARCH_FLAGS=${compile_arch_flags}
                -DRUNTIME_TEST_LINK_FLAGS=${test_link_flags}
                -DLLVM_LIT_ARGS=${libcxx_lit_args}
                -DLLVM_EXTERNAL_LIT=${external_lit_path}
            )
        endif()
    elseif(C_LIBRARY STREQUAL musl-embedded)
        set(cxxlibs_extra_cmake_options
            -DLIBCXX_HAS_MUSL_LIBC=ON
            -DLIBCXXABI_ENABLE_THREADS=OFF
            -DLIBCXX_ENABLE_RANDOM_DEVICE=OFF
            -DLIBCXX_ENABLE_THREADS=OFF
            -DLIBCXX_ENABLE_FILESYSTEM=OFF
            -DLIBCXX_ENABLE_LOCALIZATION=OFF
            -DLIBUNWIND_ENABLE_THREADS=OFF
            -DLIBCXXABI_ENABLE_EXCEPTIONS=${ENABLE_EXCEPTIONS}
            -DLIBCXXABI_ENABLE_STATIC_UNWINDER=${ENABLE_EXCEPTIONS}
            -DLIBCXX_ENABLE_EXCEPTIONS=${ENABLE_EXCEPTIONS}
            -DLIBCXX_ENABLE_RTTI=${ENABLE_RTTI}
            )
        set(lib_compile_flags "${lib_compile_flags} -fno-unroll-loops -fno-optimize-sibling-calls -D_GNU_SOURCE")
    endif()

    ExternalProject_Add(
        cxxlibs
        STAMP_DIR ${PROJECT_PREFIX}/cxxlibs/${VARIANT_BUILD_ID}/stamp
        BINARY_DIR ${PROJECT_PREFIX}/cxxlibs/${VARIANT_BUILD_ID}/build
        DOWNLOAD_DIR ${PROJECT_PREFIX}/cxxlibs/${VARIANT_BUILD_ID}/dl
        TMP_DIR ${PROJECT_PREFIX}/cxxlibs/${VARIANT_BUILD_ID}/tmp
        SOURCE_DIR ${llvmproject_src_dir}/runtimes
        INSTALL_DIR ${TEMP_LIB_DIR}
        DEPENDS compiler_rt-install clib-install
        CMAKE_ARGS
        ${compiler_launcher_cmake_args}
        -DCMAKE_AR=${LLVM_BINARY_DIR}/bin/llvm-ar${CMAKE_EXECUTABLE_SUFFIX}
        -DCMAKE_ASM_FLAGS=${lib_compile_flags}
        -DCMAKE_BUILD_TYPE=${LIBRARY_CMAKE_BUILD_TYPE}
        -DCMAKE_CXX_COMPILER=${LLVM_BINARY_DIR}/bin/clang++${CMAKE_EXECUTABLE_SUFFIX}
        -DCMAKE_CXX_COMPILER_TARGET=${target_triple}
        -DCMAKE_CXX_FLAGS=${lib_compile_flags}
        -DCMAKE_C_COMPILER=${LLVM_BINARY_DIR}/bin/clang${CMAKE_EXECUTABLE_SUFFIX}
        -DCMAKE_C_COMPILER_TARGET=${target_triple}
        -DCMAKE_C_FLAGS=${lib_compile_flags}
        -DCMAKE_INSTALL_MESSAGE=${CMAKE_INSTALL_MESSAGE}
        -DCMAKE_INSTALL_PREFIX=${TEMP_LIB_DIR}
        -DCMAKE_NM=${LLVM_BINARY_DIR}/bin/llvm-nm${CMAKE_EXECUTABLE_SUFFIX}
        -DCMAKE_RANLIB=${LLVM_BINARY_DIR}/bin/llvm-ranlib${CMAKE_EXECUTABLE_SUFFIX}
        # Let CMake know we're cross-compiling
        -DCMAKE_SYSTEM_NAME=Generic
        -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY
        -DLIBCXXABI_BAREMETAL=ON
        -DLIBCXXABI_ENABLE_ASSERTIONS=OFF
        -DLIBCXXABI_ENABLE_SHARED=OFF
        -DLIBCXXABI_ENABLE_STATIC=ON
        -DLIBCXXABI_USE_COMPILER_RT=ON
        -DLIBCXXABI_USE_LLVM_UNWINDER=ON
        -DLIBCXXABI_SHARED_OUTPUT_NAME="c++abi-shared"
        -DLIBCXX_CXX_ABI=libcxxabi
        -DLIBCXX_ENABLE_FILESYSTEM=OFF
        -DLIBCXX_ENABLE_SHARED=OFF
        -DLIBCXX_ENABLE_STATIC=ON
        -DLIBCXX_INCLUDE_BENCHMARKS=OFF
        -DLIBCXX_SHARED_OUTPUT_NAME="c++-shared"
        -DLIBUNWIND_ENABLE_ASSERTIONS=OFF
        -DLIBUNWIND_ENABLE_SHARED=OFF
        -DLIBUNWIND_ENABLE_STATIC=ON
        -DLIBUNWIND_IS_BAREMETAL=ON
        -DLIBUNWIND_REMEMBER_HEAP_ALLOC=ON
        -DLIBUNWIND_USE_COMPILER_RT=ON
        -DLIBUNWIND_SHARED_OUTPUT_NAME="unwind-shared"
        -DLLVM_LIT_ARGS=${LLVM_LIT_ARGS}
        -DLLVM_ENABLE_RUNTIMES=libcxxabi,libcxx,libunwind
        -DRUNTIME_VARIANT_NAME=${VARIANT}
        ${cxxlibs_extra_cmake_options}
        ${cxxlibs_test_cmake_options}
        STEP_TARGETS configure build install
        USES_TERMINAL_CONFIGURE TRUE
        USES_TERMINAL_BUILD TRUE
        USES_TERMINAL_INSTALL TRUE
        LIST_SEPARATOR ,
        CONFIGURE_HANDLED_BY_BUILD TRUE
    )
    add_custom_target(check-cxx)
    add_dependencies(check-all check-cxx)
    add_custom_target(check-cxxabi)
    add_dependencies(check-all check-cxxabi)
    add_custom_target(check-unwind)
    add_dependencies(check-all check-unwind)
    if(ENABLE_LIBCXX_TESTS)
        foreach(check_target check-cxx check-cxxabi check-unwind)
            ExternalProject_Add_Step(
                cxxlibs
                ${check_target}
                COMMAND "${CMAKE_COMMAND}" --build <BINARY_DIR> --target ${check_target}
                USES_TERMINAL TRUE
                EXCLUDE_FROM_MAIN TRUE
                ALWAYS TRUE
            )
            ExternalProject_Add_StepTargets(cxxlibs ${check_target})
            ExternalProject_Add_StepDependencies(
                cxxlibs
                ${check_target}
                cxxlibs-install
                libcxx-xfail-lit-args
            )
            add_dependencies(${check_target} cxxlibs-${check_target})
        endforeach()
    endif()

else() # if not ENABLE_CXX_LIBS

    # The parent embedded-multilib cmake script will still want to invoke
    # build targets like 'cxxlibs-configure', whether we actually have
    # C++ libraries or not. So we should define them, even if they
    # don't do anything.
    add_custom_target(cxxlibs-configure)
    add_custom_target(cxxlibs-build)
endif()

install(
    DIRECTORY ${TEMP_LIB_DIR}/
    DESTINATION .
)
