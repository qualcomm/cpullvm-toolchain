#!/usr/bin/env bash

# Copyright (c) 2025, Arm Limited and affiliates.
# Part of the Arm Toolchain project, under the Apache License v2.0 with LLVM Exceptions.
# See https://llvm.org/LICENSE.txt for license information.
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#
# ​​​​​Changes from Qualcomm Technologies, Inc. are provided under the following license:
# Copyright (c) Qualcomm Technologies, Inc. and/or its subsidiaries. 
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

# The script creates a build of the toolchain in the 'build' directory, inside
# the repository tree.

# FIXME: Eventually this should be common between x86/AArch64. But, there's
# dependencies that need to be sorted out on the AArch64 builders and it is more
# convenient to have separate scripts until that happens.

set -ex

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
REPO_ROOT=$( git -C "${SCRIPT_DIR}" rev-parse --show-toplevel )

clang --version

export CC=clang
export CXX=clang++

mkdir -p "${REPO_ROOT}"/build
cd "${REPO_ROOT}"/build

AARCH64_CMAKE_ARGS="-DLLVM_TOOLCHAIN_DISTRIBUTION_COMPONENTS='llvm-toolchain-docs;llvm-toolchain-third-party-licenses' -DPREBUILT_TARGET_LIBRARIES=ON"
EXTRA_CMAKE_ARGS="${AARCH64_CMAKE_ARGS} ${EXTRA_CMAKE_ARGS}"

cmake ../qualcomm-software -GNinja -DFETCHCONTENT_QUIET=OFF ${EXTRA_CMAKE_ARGS}

ninja package-llvm-toolchain
