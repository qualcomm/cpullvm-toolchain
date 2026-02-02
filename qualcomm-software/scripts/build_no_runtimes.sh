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
# the repository tree *excluding* all of the target runtime libraries.
#
# FIXME: This is intended as a convenience script while dependencies on various
# builders are sorted out. This probably should be removed.

set -ex

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
REPO_ROOT=$( git -C "${SCRIPT_DIR}" rev-parse --show-toplevel )

clang --version

export CC=clang
export CXX=clang++

mkdir -p "${REPO_ROOT}"/build
cd "${REPO_ROOT}"/build

cmake ../qualcomm-software \
 -GNinja \
 -DFETCHCONTENT_QUIET=OFF \
 -DLLVM_TOOLCHAIN_DISTRIBUTION_COMPONENTS="llvm-toolchain-docs;llvm-toolchain-third-party-licenses" \
 -DPREBUILT_TARGET_LIBRARIES=ON \
 ${EXTRA_CMAKE_ARGS}

ninja package-llvm-toolchain
