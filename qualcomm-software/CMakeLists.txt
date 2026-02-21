#
# Copyright (c) 2022-2025, Arm Limited and affiliates.
#
# Part of the Arm Toolchain project, under the Apache License v2.0 with LLVM Exceptions.
# See https://llvm.org/LICENSE.txt for license information.
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#
# Changes from Qualcomm Technologies, Inc. are provided under the following license:
# Copyright (c) Qualcomm Technologies, Inc. and/or its subsidiaries.
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#

# How to use this file
#
# Recent versions of the following tools are pre-requisites:
# * A toolchain such as gcc & binutils
# * cmake
# * meson
# * ninja
# * python3
# * make and qemu to run tests
#
# Commands to build:
#   mkdir build
#   cd build
#   cmake .. -GNinja -DFETCHCONTENT_QUIET=OFF
#   ninja
#   ninja check-llvm-toolchain
#
# To make it easy to get started, the above command checks out
# the picolibc Git repos automatically.
#
# If the repos are checked out automatically then cmake will fetch the
# latest changes and check them out every time it runs. To disable this
# behaviour run:
#   cmake . -DFETCHCONTENT_FULLY_DISCONNECTED=ON
#
# If you prefer you can check out and patch the repos manually and use those:
#   mkdir repos
#   git -C repos clone https://github.com/picolibc/picolibc.git
#   git -C repos/picolibc am -k $PWD/patches/picolibc/*.patch
#   mkdir build
#   cd build
#   cmake .. -GNinja -DFETCHCONTENT_SOURCE_DIR_PICOLIBC=../repos/picolibc
#   ninja
#   ninja check-llvm-toolchain
#
# To install the toolchain run:
#   cmake . --install-prefix /absolute/path/to/install/directory
#   ninja install-llvm-toolchain
#
#
# This file is designed to be used in a way that will be familiar to
# LLVM developers. Targets like clang and check-all can be built as usual.
# In addition there are targets to build picolibc & runtimes variants.
#
#
# When building the toolchain repeatedly, the most time-consuming part
# can be building the libraries since each one is configured separately.
# To work around this, the variants that get built can be limited using
# the LLVM_TOOLCHAIN_LIBRARY_VARIANTS option e.g.:
#   cmake . '-DLLVM_TOOLCHAIN_LIBRARY_VARIANTS=aarch64;armv6m_soft_nofp'


# CONFIGURE_HANDLED_BY_BUILD was introduced in CMake 3.20 and it
# greatly speeds up incremental builds.
cmake_minimum_required(VERSION 3.20)

option(
    PREBUILT_TARGET_LIBRARIES
    "Target libraries are prebuilt so no need to build them"
)
set(TARGET_LIBRARIES_DIR
    "lib/clang-runtimes" CACHE STRING
    "Directory containing the target libraries."
)
set(LLVM_TOOLCHAIN_MULTILIB_JSON
    "${CMAKE_CURRENT_SOURCE_DIR}/embedded-multilib/json/multilib.json" CACHE STRING
    "JSON file defining the multilib."
)
set(LLVM_TOOLCHAIN_LIBRARY_VARIANTS
    "all" CACHE STRING
    "Build only the specified library variants, or \"all\"."
)
option(
    LIBS_DEPEND_ON_TOOLS
    "Automatically ensure tools like clang are up to date before building libraries.
    Set this to OFF if you're working on the libraries and want to avoid rebuilding
    the tools every time you update llvm-project."
    ON
)
option(
    LIBS_USE_COMPILER_LAUNCHER
    "Pass CMAKE_C_COMPILER_LAUNCHER and CMAKE_CXX_COMPILER_LAUNCHER
    down to the library builds, so that programs such as ccache can
    be used to speed up repeated builds. This is not done by default,
    as it can also make the inital build slower due to the cold cache."
)
option(
    ENABLE_PARALLEL_LIB_CONFIG
    "Run the library variant configuration steps in parallel."
    ON
)
option(
    ENABLE_PARALLEL_LIB_BUILD
    "Run the library variant build steps in parallel."
    OFF
)
set(PARALLEL_LIB_BUILD_LEVELS
    "1" CACHE STRING
    "If ENABLE_PARALLEL_LIB_BUILD is ON, this number of processes will be assigned to each variant built."
)
option(
    ENABLE_QEMU_TESTING
    "Enable tests that use QEMU. This option is ON by default."
    ON
)
set(LLVM_TOOLCHAIN_C_LIBRARY
    "picolibc" CACHE STRING
    "Which C library to use."
)
set_property(CACHE LLVM_TOOLCHAIN_C_LIBRARY
    PROPERTY STRINGS picolibc musl-embedded)

option(
    SHORT_BUILD_PATHS
    "Shorten the lengths of internal build paths, which may help with OS path
    length limits. This replaces the variant suffixes in build directories with
    index numbers, which is shorter but less descriptive."
    OFF
)
option(
    ENABLE_LINUX_LIBRARIES
    "Include additional library variants for use on Linux targets"
    OFF
)
if(ENABLE_LINUX_LIBRARIES AND WIN32)
    message(FATAL_ERROR "ENABLE_LINUX_LIBRARIES is not permitted on Windows")
endif()
option(LLVM_TOOLCHAIN_LIBRARY_OVERLAY_INSTALL
    "Make cpack build an overlay package that can be unpacked over the main toolchain to install a secondary set of libraries based on musl-embedded."
    ${overlay_install_default})
if(LLVM_TOOLCHAIN_LIBRARY_OVERLAY_INSTALL)
  if(LLVM_TOOLCHAIN_C_LIBRARY STREQUAL "picolibc")
    message(FATAL_ERROR "LLVM_TOOLCHAIN_LIBRARY_OVERLAY_INSTALL is only permitted for C libraries other than the default picolibc")
  endif()
  if(ENABLE_LINUX_LIBRARIES)
    message(FATAL_ERROR "ENABLE_LINUX_LIBRARIES is not permitted with LLVM_TOOLCHAIN_LIBRARY_OVERLAY_INSTALL")
  endif()
endif()

set(BUG_REPORT_URL "https://github.com/qualcomm/cpullvm-toolchain/issues" CACHE STRING "")
set(LLVM_DISTRIBUTION_COMPONENTS
    clang-resource-headers
    clang
    dsymutil
    lld
    ld.eld
    llvm-ar
    llvm-config
    llvm-cov
    llvm-cxxfilt
    llvm-dwarfdump
    llvm-mc
    llvm-nm
    llvm-objcopy
    llvm-objdump
    llvm-profdata
    llvm-ranlib
    llvm-readelf
    llvm-readobj
    llvm-size
    llvm-strings
    llvm-strip
    llvm-symbolizer
    LTO
    CACHE STRING ""
)
set(LLVM_TOOLCHAIN_DISTRIBUTION_COMPONENTS
    llvm-toolchain-docs
    llvm-toolchain-libs
    llvm-toolchain-third-party-licenses
    CACHE STRING "Components defined by this CMakeLists that should be
installed by the install-llvm-toolchain target"
)
set(LLVM_ENABLE_PROJECTS clang;lld;polly CACHE STRING "")
set(LLVM_TARGETS_TO_BUILD AArch64;ARM;RISCV;X86 CACHE STRING "")
# There's test failures when enabling x86 support and testing on native
# AArch64 Linux machines. Just disable x86 in eld until these are
# resolved.
set(ELD_TARGETS_TO_BUILD AArch64;ARM;RISCV CACHE STRING "")
set(ELD_INSTALL_LINKER_SCRIPT_TEMPLATES OFF CACHE BOOL "")
set(LLVM_DEFAULT_TARGET_TRIPLE aarch64-unknown-linux-gnu CACHE STRING "")
set(LLVM_BUILD_RUNTIME OFF CACHE BOOL "")
set(LIBCLANG_BUILD_STATIC ON CACHE BOOL "")
set(LLVM_POLLY_LINK_INTO_TOOLS ON CACHE BOOL "")
set(CLANG_DEFAULT_LINKER lld CACHE STRING "")
set(LLVM_LIT_ARGS "-sv" CACHE STRING "")

# Default to a release build
# (CMAKE_BUILD_TYPE is a special CMake variable so if you want to set
# it then you have to FORCE it).
if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release CACHE BOOL "" FORCE)
endif()

find_package(Python3 REQUIRED COMPONENTS Interpreter)

if(NOT CMAKE_C_COMPILER_LAUNCHER AND NOT CMAKE_CXX_COMPILER_LAUNCHER)
    # If ccache is available then use it by default.
    find_program(CCACHE_EXECUTABLE ccache)
    if(CCACHE_EXECUTABLE)
        set(CMAKE_C_COMPILER_LAUNCHER "${CCACHE_EXECUTABLE}" CACHE FILEPATH "" FORCE)
        set(CMAKE_CXX_COMPILER_LAUNCHER "${CCACHE_EXECUTABLE}" CACHE FILEPATH "" FORCE)
    endif()
endif()

# If lld is available then use it by default.
find_program(LLD_EXECUTABLE lld)
if(LLD_EXECUTABLE)
    set(LLVM_USE_LINKER lld CACHE STRING "")
endif()

# A lot of files get installed which makes the install messages too
# noisy to be useful so default to disabling them.
set(CMAKE_INSTALL_MESSAGE NEVER CACHE STRING "")

include(ExternalProject)
include(FetchContent)
include(ProcessorCount)

# Check out and patch eld
include(${CMAKE_CURRENT_SOURCE_DIR}/cmake/fetch_eld.cmake)

# Check out and patch picolibc or musl-embedded if required.
#
# If you'd rather check out and patch manually then run cmake with
# -DFETCHCONTENT_SOURCE_DIR_PICOLIBC=/path/to/picolibc
# -DFETCHCONTENT_SOURCE_DIR_MUSL-EMBEDDED=/path/to/musl-embedded
#
# By default check out will be silent but this can be changed by running
# cmake with -DFETCHCONTENT_QUIET=OFF
#
# If you want to stop cmake updating the repos then run
# cmake . -DFETCHCONTENT_FULLY_DISCONNECTED=ON
if(LLVM_TOOLCHAIN_C_LIBRARY STREQUAL picolibc)
    include(${CMAKE_CURRENT_SOURCE_DIR}/cmake/fetch_picolibc.cmake)
endif()
if(LLVM_TOOLCHAIN_C_LIBRARY STREQUAL musl-embedded OR ENABLE_LINUX_LIBRARIES)
    include(${CMAKE_CURRENT_SOURCE_DIR}/cmake/fetch_musl-embedded.cmake)
endif()
if(ENABLE_LINUX_LIBRARIES)
    include(${CMAKE_CURRENT_SOURCE_DIR}/cmake/fetch_musl.cmake)
endif()

##################################################################################################
# We set all project properties later, this call is just to enable the
# CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT check
project(CPULLVMToolchain)
# We generally want to install to a local directory to see what the
# output will look like rather than install into the system, so change
# the default accordingly.
# See https://cmake.org/cmake/help/latest/variable/CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT.html
# Note that THIS CODE ONLY WORKS AFTER THE FIRST CALL TO PROJECT so it
# can't be moved after the add_subdirectory(<llvm>) command below as it will be too late -
# the llvm project will set it to the default system install directory.
if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
    set(CMAKE_INSTALL_PREFIX
        "${CMAKE_BINARY_DIR}/install"
        CACHE PATH "" FORCE
    )
endif()
##################################################################################################

if(LLVM_TOOLCHAIN_C_LIBRARY STREQUAL musl-embedded)
    install(
        FILES
        ${CMAKE_CURRENT_SOURCE_DIR}/${LLVM_TOOLCHAIN_C_LIBRARY}.cfg
        DESTINATION bin
        COMPONENT llvm-toolchain-${LLVM_TOOLCHAIN_C_LIBRARY}-configs
    )
endif()

# Include eld
set(LLVM_EXTERNAL_PROJECTS eld)
set(LLVM_EXTERNAL_ELD_SOURCE_DIR "${eld_SOURCE_DIR}")

# List of LLVM projects to generate xfails for. libc++ and compiler-rt tests
# should not be handled here.
set(llvm_xfail_projects clang)
foreach(project ${llvm_xfail_projects})
    set(${project}_lit_xfails_path "${CMAKE_CURRENT_BINARY_DIR}/${project}_lit_xfails.txt")
    string(APPEND LLVM_LIT_ARGS " @${${project}_lit_xfails_path}")
endforeach()

set(llvmproject_src_dir ${CMAKE_CURRENT_SOURCE_DIR}/..)
add_subdirectory(
    ${llvmproject_src_dir}/llvm llvm
)

add_dependencies(check-all check-eld)

# Update the xfail/xfail-not lists before running the tests.
foreach(project ${llvm_xfail_projects})
    add_custom_target(
        ${project}-xfail-lit-args
        COMMAND ${Python3_EXECUTABLE}
            ${CMAKE_CURRENT_SOURCE_DIR}/embedded-runtimes/test-support/xfails.py
            --project ${project}
            --clang ${LLVM_BINARY_DIR}/bin/clang
            --output-args ${${project}_lit_xfails_path}
        DEPENDS
            clang
    )
    add_dependencies(check-${project} ${project}-xfail-lit-args)
    add_dependencies(check-all ${project}-xfail-lit-args)
endforeach()

get_directory_property(LLVM_VERSION_MAJOR DIRECTORY ${llvmproject_src_dir}/llvm DEFINITION LLVM_VERSION_MAJOR)
get_directory_property(LLVM_VERSION_MINOR DIRECTORY ${llvmproject_src_dir}/llvm DEFINITION LLVM_VERSION_MINOR)
get_directory_property(LLVM_VERSION_PATCH DIRECTORY ${llvmproject_src_dir}/llvm DEFINITION LLVM_VERSION_PATCH)

project(
    CPULLVM
    VERSION ${LLVM_VERSION_MAJOR}.${LLVM_VERSION_MINOR}.${LLVM_VERSION_PATCH}
    DESCRIPTION "CPULLVM Toolchain"
    HOMEPAGE_URL "https://github.com/qualcomm/cpullvm-toolchain"
)

# Set package name for shorter archive file name
set(SHORT_PACKAGE_NAME "cpullvm")

# Set directory name containing CFI ignore file
set(TARGET_CFI_DIR
    "lib/clang/${LLVM_VERSION_MAJOR}/share" CACHE STRING
    "Directory containing the CFI ignore file."
)

# Set package name and version.
if(DEFINED LLVM_TOOLCHAIN_PACKAGE_NAME)
    set(PACKAGE_NAME ${LLVM_TOOLCHAIN_PACKAGE_NAME})
else()
    set(PACKAGE_NAME ${SHORT_PACKAGE_NAME})
endif()
set(CPACK_PACKAGE_NAME ${PACKAGE_NAME})
set(PACKAGE_VERSION "${LLVM_VERSION_MAJOR}.${LLVM_VERSION_MINOR}.${LLVM_VERSION_PATCH}")

# Restrict which LLVM components are installed.
if(LLVM_TOOLCHAIN_LIBRARY_OVERLAY_INSTALL)
    set(CPACK_COMPONENTS_ALL
        llvm-toolchain-libs
        llvm-toolchain-${LLVM_TOOLCHAIN_C_LIBRARY}-configs
        llvm-toolchain-third-party-licenses)
else()
    set(CPACK_COMPONENTS_ALL ${LLVM_TOOLCHAIN_DISTRIBUTION_COMPONENTS} ${LLVM_DISTRIBUTION_COMPONENTS})
endif()
# Enable limiting the installed components in TGZ and ZIP packages.
set(CPACK_ARCHIVE_COMPONENT_INSTALL TRUE)
# Don't create a separate archive for each component.
set(CPACK_COMPONENTS_GROUPING ALL_COMPONENTS_IN_ONE)
# When extracting the files put them in an ArmCompiler-.../ directory.
# Exception: the overlay packages do not do this, because they have
# to be able to unpack over the top of an existing installation on all
# platforms, and each platform has a different top-level directory name.
if(LLVM_TOOLCHAIN_LIBRARY_OVERLAY_INSTALL)
    set(CPACK_COMPONENT_INCLUDE_TOPLEVEL_DIRECTORY FALSE)
else()
    set(CPACK_COMPONENT_INCLUDE_TOPLEVEL_DIRECTORY TRUE)
endif()
# Compress package in parallel.
set(CPACK_THREADS 0 CACHE STRING "")

# set processor_name
string(TOLOWER ${CMAKE_SYSTEM_PROCESSOR} processor_name)
string(REGEX MATCH "amd64|x64|x86" x86_match ${processor_name})
if(x86_match)
    set(processor_name "x86_64")
else()
    set(processor_name "AArch64")
endif()

# If a specific system name is supplied, use that instead.
if (PACKAGE_SYSTEM_NAME)
    set(CPACK_SYSTEM_NAME "${PACKAGE_SYSTEM_NAME}-${processor_name}")
else()
    set(CPACK_SYSTEM_NAME "${CMAKE_SYSTEM_NAME}-${processor_name}")
endif()

set(CPACK_PACKAGE_VERSION ${PACKAGE_VERSION})

if(LLVM_TOOLCHAIN_LIBRARY_OVERLAY_INSTALL)
    set(PACKAGE_FILE_NAME ${PACKAGE_NAME}-${LLVM_TOOLCHAIN_C_LIBRARY}-overlay-${PACKAGE_VERSION})
else()
    if(LLVM_TOOLCHAIN_C_LIBRARY STREQUAL "picolibc")
        set(PACKAGE_FILE_NAME ${PACKAGE_NAME}-${PACKAGE_VERSION}-${CPACK_SYSTEM_NAME})
    else()
        set(PACKAGE_FILE_NAME ${PACKAGE_NAME}_${LLVM_TOOLCHAIN_C_LIBRARY}-${PACKAGE_VERSION}-${CPACK_SYSTEM_NAME})
    endif()
endif()
set(CPACK_PACKAGE_FILE_NAME ${PACKAGE_FILE_NAME})

# Including CPack again after llvm CMakeLists.txt included it
# resets CPACK_PACKAGE_VERSION to the default MAJOR.MINOR.PATCH format.
include(CPack)

# Ensure LLVM tool symlinks are installed.
list(APPEND CMAKE_MODULE_PATH ${llvmproject_src_dir}/llvm/cmake/modules)
llvm_install_symlink(LLVM llvm-ranlib llvm-ar ALWAYS_GENERATE)
llvm_install_symlink(LLVM llvm-readelf llvm-readobj ALWAYS_GENERATE)
llvm_install_symlink(LLVM llvm-strip llvm-objcopy ALWAYS_GENERATE)

# Generate VERSION.txt
# Use add_custom_target instead of add_custom_command so that the target
# is always considered out-of-date, ensuring that VERSION.txt will be
# updated when the git revision changes.
add_custom_target(
    version_txt
    COMMAND
    "${CMAKE_COMMAND}"
    -DCPULLVMToolchain_VERSION=${CPULLVMToolchain_VERSION}
    -DCPULLVMToolchain_SOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}
    -Dllvmproject_src_dir=${llvmproject_src_dir}
    -Deld_SOURCE_DIR=${eld_SOURCE_DIR}
    # at most one of picolibc and musl options is needed, but easiest to
    # specify both definitions
    -Dpicolibc_SOURCE_DIR=${picolibc_SOURCE_DIR}
    -Dpicolibc_URL=${picolibc_URL}
    -Dmusl-embedded_SOURCE_DIR=${musl-embedded_SOURCE_DIR}
    -Dmusl-embedded_URL=${musl-embedded_URL}
    # but we do tell the script which library we're actually using
    -DLLVM_TOOLCHAIN_C_LIBRARY=${LLVM_TOOLCHAIN_C_LIBRARY}
    -Dmusl_SOURCE_DIR=${musl_SOURCE_DIR}
    -Dmusl_URL=${musl_URL}
    -DENABLE_LINUX_LIBRARIES=${ENABLE_LINUX_LIBRARIES}
    -P ${CMAKE_CURRENT_SOURCE_DIR}/cmake/generate_version_txt.cmake
    BYPRODUCTS ${CMAKE_CURRENT_BINARY_DIR}/VERSION.txt
)
if(NOT (LLVM_TOOLCHAIN_C_LIBRARY STREQUAL picolibc))
    install(
        FILES "${CMAKE_CURRENT_BINARY_DIR}/VERSION.txt"
        DESTINATION .
        RENAME VERSION_${LLVM_TOOLCHAIN_C_LIBRARY}.txt
        COMPONENT llvm-toolchain-third-party-licenses
    )
else()
    install(
        FILES "${CMAKE_CURRENT_BINARY_DIR}/VERSION.txt"
        DESTINATION .
        COMPONENT llvm-toolchain-third-party-licenses
    )
endif()


# Groups all the targets that comprise the toolchain.
add_custom_target(llvm-toolchain ALL)

# Groups all the runtime targets
add_custom_target(llvm-toolchain-runtimes)

add_dependencies(
    llvm-toolchain
    ${LLVM_DISTRIBUTION_COMPONENTS}
)

add_dependencies(
    llvm-toolchain
    llvm-toolchain-runtimes
    version_txt
)

# Set LLVM_DEFAULT_EXTERNAL_LIT to the directory of clang
# which was build in previous step. This path is not exported
# by add_subdirectory of llvm project
set(lit_file_name "llvm-lit")
if (CMAKE_HOST_WIN32)
  set(lit_file_name "${lit_file_name}.py")
endif ()
set(LLVM_DEFAULT_EXTERNAL_LIT "${LLVM_BINARY_DIR}/bin/${lit_file_name}")

add_custom_target(check-llvm-toolchain-runtimes)
add_custom_target(check-${LLVM_TOOLCHAIN_C_LIBRARY})
add_custom_target(check-compiler-rt)
add_custom_target(check-cxx)
add_custom_target(check-cxxabi)
add_custom_target(check-unwind)

if(NOT PREBUILT_TARGET_LIBRARIES)
    if(LIBS_DEPEND_ON_TOOLS)
        set(lib_tool_dependencies
            clang
            lld
            ld.eld
            llvm-ar
            llvm-config
            llvm-nm
            llvm-ranlib
            llvm-strip
        )
    endif()


    add_dependencies(
        check-llvm-toolchain-runtimes
        check-${LLVM_TOOLCHAIN_C_LIBRARY}
        check-compiler-rt
        check-cxx
        check-cxxabi
        check-unwind
    )

    if(LLVM_TOOLCHAIN_LIBRARY_OVERLAY_INSTALL)
        # If we're building a non-default libc with the intention of
        # installing it as an overlay on the main package archive, then
        # all of its includes, libraries and multilib.yaml go in a
        # subdirectory of lib/clang-runtimes. Configuration files in the
        # bin directory will make it easy to reset the sysroot to point at
        # that subdir.
        set(library_subdir "/${LLVM_TOOLCHAIN_C_LIBRARY}")
    else()
        set(library_subdir "")
    endif()

    if(LIBS_USE_COMPILER_LAUNCHER)
        if(CMAKE_C_COMPILER_LAUNCHER)
            list(APPEND compiler_launcher_cmake_args "-DCMAKE_C_COMPILER_LAUNCHER=${CMAKE_C_COMPILER_LAUNCHER}")
        endif()
        if(CMAKE_CXX_COMPILER_LAUNCHER)
            list(APPEND compiler_launcher_cmake_args "-DCMAKE_CXX_COMPILER_LAUNCHER=${CMAKE_CXX_COMPILER_LAUNCHER}")
        endif()
    endif()

    # ENABLE_VARIANTS expects a semi-colon separated list.
    # To prevent CMake expanding it automatically while passing it
    # down, switch to comma separated. Enabling the ExternalProject
    # LIST_SEPARATOR option will handle switching it back.
    string(REPLACE ";" "," ENABLE_VARIANTS_PASSTHROUGH "${LLVM_TOOLCHAIN_LIBRARY_VARIANTS}")

    set(multilib_prefix ${CMAKE_BINARY_DIR}/multilib-builds)

    ExternalProject_Add(
        multilib-${LLVM_TOOLCHAIN_C_LIBRARY}
        SOURCE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/embedded-multilib
        STAMP_DIR ${multilib_prefix}/multilib/${LLVM_TOOLCHAIN_C_LIBRARY}-stamp
        BINARY_DIR ${multilib_prefix}/multilib/${LLVM_TOOLCHAIN_C_LIBRARY}-build
        DOWNLOAD_DIR ${multilib_prefix}/multilib/${LLVM_TOOLCHAIN_C_LIBRARY}-dl
        TMP_DIR ${multilib_prefix}/multilib/${LLVM_TOOLCHAIN_C_LIBRARY}-tmp
        INSTALL_DIR ${CMAKE_CURRENT_BINARY_DIR}/llvm/${TARGET_LIBRARIES_DIR}${library_subdir}
        DEPENDS ${lib_tool_dependencies}
        CMAKE_ARGS
        ${compiler_launcher_cmake_args}
        -DC_LIBRARY=${LLVM_TOOLCHAIN_C_LIBRARY}
        -DLLVM_BINARY_DIR=${CMAKE_CURRENT_BINARY_DIR}/llvm
        -DMULTILIB_JSON=${LLVM_TOOLCHAIN_MULTILIB_JSON}
        -DENABLE_VARIANTS=${ENABLE_VARIANTS_PASSTHROUGH}
        -DENABLE_PARALLEL_LIB_CONFIG=${ENABLE_PARALLEL_LIB_CONFIG}
        -DENABLE_PARALLEL_LIB_BUILD=${ENABLE_PARALLEL_LIB_BUILD}
        -DPARALLEL_LIB_BUILD_LEVELS=${PARALLEL_LIB_BUILD_LEVELS}
        -DENABLE_QEMU_TESTING=${ENABLE_QEMU_TESTING}
        -DFETCHCONTENT_SOURCE_DIR_PICOLIBC=${FETCHCONTENT_SOURCE_DIR_PICOLIBC}
        -DFETCHCONTENT_SOURCE_DIR_MUSL-EMBEDDED=${FETCHCONTENT_SOURCE_DIR_MUSL-EMBEDDED}
        -DCMAKE_INSTALL_PREFIX=<INSTALL_DIR>
        -DPROJECT_PREFIX=${multilib_prefix}
        -DNUMERICAL_BUILD_NAMES=${SHORT_BUILD_PATHS}
        USES_TERMINAL_CONFIGURE TRUE
        USES_TERMINAL_BUILD TRUE
        LIST_SEPARATOR ,
        CONFIGURE_HANDLED_BY_BUILD TRUE
        TEST_EXCLUDE_FROM_MAIN TRUE
        STEP_TARGETS build install
    )

    add_dependencies(
        llvm-toolchain-runtimes
        multilib-${LLVM_TOOLCHAIN_C_LIBRARY}-install
    )

    foreach(check_target check-${LLVM_TOOLCHAIN_C_LIBRARY} check-compiler-rt check-cxx check-cxxabi check-unwind)
        ExternalProject_Add_Step(
            multilib-${LLVM_TOOLCHAIN_C_LIBRARY}
            ${check_target}
            COMMAND "${CMAKE_COMMAND}" --build <BINARY_DIR> --target ${check_target}
            USES_TERMINAL TRUE
            EXCLUDE_FROM_MAIN TRUE
            ALWAYS TRUE
        )
        ExternalProject_Add_StepTargets(multilib-${LLVM_TOOLCHAIN_C_LIBRARY} ${check_target})
        ExternalProject_Add_StepDependencies(
            multilib-${LLVM_TOOLCHAIN_C_LIBRARY}
            ${check_target}
            multilib-${LLVM_TOOLCHAIN_C_LIBRARY}-install
        )
        add_dependencies(${check_target} multilib-${LLVM_TOOLCHAIN_C_LIBRARY}-${check_target})
    endforeach()

    # Read the json to generate variant specific target names for convenience.
    file(READ ${LLVM_TOOLCHAIN_MULTILIB_JSON} multilib_json_str)
    string(JSON multilib_defs GET ${multilib_json_str} "libs")

    string(JSON lib_count LENGTH ${multilib_defs})
    math(EXPR lib_count_dec "${lib_count} - 1")

    foreach(lib_idx RANGE ${lib_count_dec})
        string(JSON lib_def GET ${multilib_defs} ${lib_idx})
        string(JSON variant GET ${lib_def} "variant")
        foreach(check_target check-${LLVM_TOOLCHAIN_C_LIBRARY} check-compiler-rt check-cxx check-cxxabi check-unwind)
            ExternalProject_Add_Step(
                multilib-${LLVM_TOOLCHAIN_C_LIBRARY}
                ${check_target}-${variant}
                COMMAND "${CMAKE_COMMAND}" --build <BINARY_DIR> --target ${check_target}-${variant}
                USES_TERMINAL TRUE
                EXCLUDE_FROM_MAIN TRUE
                ALWAYS TRUE
            )
            ExternalProject_Add_StepTargets(multilib-${LLVM_TOOLCHAIN_C_LIBRARY} ${check_target}-${variant})
            ExternalProject_Add_StepDependencies(
                multilib-${LLVM_TOOLCHAIN_C_LIBRARY}
                ${check_target}-${variant}
                multilib-${LLVM_TOOLCHAIN_C_LIBRARY}-install
            )
            add_custom_target(${check_target}-${variant})
            add_dependencies(${check_target}-${variant} multilib-${LLVM_TOOLCHAIN_C_LIBRARY}-${check_target}-${variant})
        endforeach()
    endforeach()

    # Linux
    if(ENABLE_LINUX_LIBRARIES)
        set(linux_library_prefix ${CMAKE_BINARY_DIR}/linux-library-builds)
        ExternalProject_Add(
            linux-libraries
            STAMP_DIR ${linux_library_prefix}/stamp
            BINARY_DIR ${linux_library_prefix}/build
            DOWNLOAD_DIR ${linux_library_prefix}/dl
            TMP_DIR ${linux_library_prefix}/tmp
            SOURCE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/scripts
            INSTALL_DIR ${CMAKE_CURRENT_BINARY_DIR}/llvm/linux-libraries
            DEPENDS ${lib_tool_dependencies}
            CONFIGURE_COMMAND ""
            BUILD_COMMAND
                <SOURCE_DIR>/build_linux_runtimes.sh
                    --tools-path ${CMAKE_CURRENT_BINARY_DIR}/llvm/bin
                    --base-build-dir <BINARY_DIR>
                    --base-install-dir <INSTALL_DIR>
                    --llvm-src-dir ${llvmproject_src_dir}
                    --musl-src-dir ${musl_SOURCE_DIR}
                    --musl-emb-src-dir ${musl-embedded_SOURCE_DIR}
                    --download-dir <DOWNLOAD_DIR>
            INSTALL_COMMAND ""
            USES_TERMINAL_CONFIGURE TRUE
            USES_TERMINAL_BUILD TRUE
            USES_TERMINAL_INSTALL TRUE
            STEP_TARGETS build install
        )

        add_dependencies(
            llvm-toolchain-runtimes
            linux-libraries-install
        )
    endif()
endif()

FILE(WRITE "${CMAKE_BINARY_DIR}/llvm/${TARGET_CFI_DIR}/cfi_ignorelist.txt" "")
install(
    FILES
    ${CMAKE_BINARY_DIR}/llvm/${TARGET_CFI_DIR}/cfi_ignorelist.txt
    DESTINATION ${TARGET_CFI_DIR}
    COMPONENT llvm-toolchain-libs
)

install(
    DIRECTORY ${LLVM_BINARY_DIR}/${TARGET_LIBRARIES_DIR}/.
    DESTINATION ${TARGET_LIBRARIES_DIR}
    COMPONENT llvm-toolchain-libs
)

if(ENABLE_LINUX_LIBRARIES)
    # libc, libc++/libc++abi/libunwind only
    install(
        DIRECTORY ${LLVM_BINARY_DIR}/linux-libraries/.
        DESTINATION .
        COMPONENT llvm-toolchain-libs
        REGEX "resource-dir" EXCLUDE
    )
    # compiler-rt
    install(
        DIRECTORY ${LLVM_BINARY_DIR}/linux-libraries/resource-dir/.
        DESTINATION lib/clang/${LLVM_VERSION_MAJOR}
        COMPONENT llvm-toolchain-libs
    )
endif()

install(
    FILES CHANGELOG.md LICENSE.txt README.md
    DESTINATION .
    COMPONENT llvm-toolchain-docs
)

configure_file(cmake/THIRD-PARTY-LICENSES.txt.in THIRD-PARTY-LICENSES.txt)

if(NOT LLVM_TOOLCHAIN_LIBRARY_OVERLAY_INSTALL)
    set(third_party_license_summary_install_dir .)
    set(third_party_license_files_install_dir third-party-licenses)
else()
    # If we're building an overlay archive, put all the license files
    # one level down in third-party-licenses/<library type>, so that
    # COPYING.NEWLIB doesn't collide with the file of the same name
    # from picolibc, and the LLVM license files are also duplicated
    # (in case the overlay archive is used with a non-matching version
    # of the main toolchain).
    set(third_party_license_summary_install_dir third-party-licenses/${LLVM_TOOLCHAIN_C_LIBRARY})
    set(third_party_license_files_install_dir third-party-licenses/${LLVM_TOOLCHAIN_C_LIBRARY})
endif()

install(
    FILES ${CMAKE_CURRENT_BINARY_DIR}/THIRD-PARTY-LICENSES.txt
    DESTINATION ${third_party_license_summary_install_dir}
    COMPONENT llvm-toolchain-third-party-licenses
)

set(third_party_license_files
    ${llvmproject_src_dir}/llvm/LICENSE.TXT          LLVM-LICENSE.txt
    ${llvmproject_src_dir}/clang/LICENSE.TXT         CLANG-LICENSE.txt
    ${llvmproject_src_dir}/lld/LICENSE.TXT           LLD-LICENSE.txt
    ${llvmproject_src_dir}/compiler-rt/LICENSE.TXT   COMPILER-RT-LICENSE.txt
    ${llvmproject_src_dir}/libcxx/LICENSE.TXT        LIBCXX-LICENSE.txt
    ${llvmproject_src_dir}/libcxxabi/LICENSE.TXT     LIBCXXABI-LICENSE.txt
    ${llvmproject_src_dir}/libunwind/LICENSE.TXT     LIBUNWIND-LICENSE.txt
)

list(APPEND third_party_license_files ${eld_SOURCE_DIR}/LICENSE eld-LICENSE.txt)
list(APPEND third_party_license_files
    ${CMAKE_CURRENT_LIST_DIR}/ATfE-LICENSE.txt ATfE-LICENSE.txt
)

if(LLVM_TOOLCHAIN_C_LIBRARY STREQUAL picolibc)
    list(APPEND third_party_license_files
        ${picolibc_SOURCE_DIR}/COPYING.NEWLIB           COPYING.NEWLIB
        ${picolibc_SOURCE_DIR}/COPYING.picolibc         COPYING.picolibc
    )
elseif(LLVM_TOOLCHAIN_C_LIBRARY STREQUAL musl-embedded)
    list(APPEND third_party_license_files
        ${musl-embedded_SOURCE_DIR}/COPYRIGHT musl-embedded-COPYRIGHT.txt
    )
endif()
if(ENABLE_LINUX_LIBRARIES)
    list(APPEND third_party_license_files
        ${musl_SOURCE_DIR}/COPYRIGHT musl-COPYRIGHT.txt)

    # We added this above if musl-embedded was selected.
    if(NOT LLVM_TOOLCHAIN_C_LIBRARY STREQUAL musl-embedded)
        list(APPEND third_party_license_files
             ${musl-embedded_SOURCE_DIR}/COPYRIGHT musl-embedded-COPYRIGHT.txt)
    endif()
endif()

while(third_party_license_files)
    list(POP_FRONT third_party_license_files source_file destination_name)
    install(
        FILES ${source_file}
        DESTINATION ${third_party_license_files_install_dir}
        COMPONENT llvm-toolchain-third-party-licenses
        RENAME ${destination_name}
    )
endwhile()

# LLVM-style install
# To use it:
#   ninja install-llvm-toolchain
add_custom_target(
    install-llvm-toolchain
)
foreach(component ${LLVM_TOOLCHAIN_DISTRIBUTION_COMPONENTS})
    add_custom_target(
        install-${component}
        COMMAND
            "${CMAKE_COMMAND}"
            --install ${CMAKE_BINARY_DIR}
            --component ${component}
        USES_TERMINAL
    )
    add_dependencies(
        install-${component}
        llvm-toolchain
    )
    add_dependencies(
        install-llvm-toolchain
        install-${component}
    )
endforeach()
# Also run install-distribution to install the LLVM
# binaries.
add_dependencies(
    install-llvm-toolchain
    install-distribution
)

# package-llvm-toolchain - target to create package
if(WIN32)
    set(cpack_generator ZIP)
    set(package_filename_extension ".zip")
else()
    set(cpack_generator TXZ)
    set(package_filename_extension ".tar.xz")
endif()
set(package_filepath ${CMAKE_BINARY_DIR}/${PACKAGE_FILE_NAME}${package_filename_extension})
add_custom_command(
    OUTPUT ${package_filepath}
    COMMAND "${CMAKE_COMMAND}" -E rm -f ${package_filepath}
    COMMAND cpack -G ${cpack_generator}
    DEPENDS llvm-toolchain
    USES_TERMINAL
    WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
)
add_custom_target(
    package-llvm-toolchain
    DEPENDS ${package_filepath}
)

add_custom_target(check-llvm-toolchain)
add_dependencies(check-llvm-toolchain check-${LLVM_TOOLCHAIN_C_LIBRARY})
add_dependencies(check-llvm-toolchain check-compiler-rt)
add_subdirectory(test)
add_dependencies(check-llvm-toolchain check-llvm-toolchain-lit)

add_custom_target(check-all-llvm-toolchain)

add_dependencies(
    check-all-llvm-toolchain
    check-all
    check-llvm-toolchain
    check-llvm-toolchain-runtimes
)
