#!/bin/bash

# Copyright (c) 2025, Arm Limited and affiliates.
# Part of the Arm Toolchain project, under the Apache License v2.0 with LLVM Exceptions.
# See https://llvm.org/LICENSE.txt for license information.
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#
# ​​​​​Changes from Qualcomm Technologies, Inc. are provided under the following license:
# Copyright (c) Qualcomm Technologies, Inc. and/or its subsidiaries. 
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

# A bash script to build the musl-embedded overlay.

# The script creates a build of the toolchain in the 'build_musl-embedded_overlay'
# directory, inside the repository tree.

set -ex

export CC=clang
export CXX=clang++

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
REPO_ROOT=$( git -C "${SCRIPT_DIR}" rev-parse --show-toplevel )
BUILD_DIR=${REPO_ROOT}/build_musl-embedded_overlay

mkdir -p "${BUILD_DIR}"
cd "${BUILD_DIR}"

cmake ../qualcomm-software -GNinja -DFETCHCONTENT_QUIET=OFF -DLLVM_TOOLCHAIN_C_LIBRARY=musl-embedded -DLLVM_TOOLCHAIN_LIBRARY_OVERLAY_INSTALL=on
ninja package-llvm-toolchain

# The package-llvm-toolchain target will produce a .tar.xz package, but we also
# want a zip version for Windows users
cpack -G ZIP
