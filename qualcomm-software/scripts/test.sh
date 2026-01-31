#!/usr/bin/env bash

# Copyright (c) 2025, Arm Limited and affiliates.
# Part of the Arm Toolchain project, under the Apache License v2.0 with LLVM Exceptions.
# See https://llvm.org/LICENSE.txt for license information.
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#
# ​​​​​Changes from Qualcomm Technologies, Inc. are provided under the following license:
# Copyright (c) Qualcomm Technologies, Inc. and/or its subsidiaries. 
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

# The script assumes a successful build of the toolchain exists in the 'build'
# directory inside the repository tree.

set -ex

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
REPO_ROOT=$( git -C "${SCRIPT_DIR}" rev-parse --show-toplevel )

# Run all relevant test targets. This might be too broad eventually,
# but while we have a limited number of variants (and no compiler-rt
# or libc++ testing enabled) we can run everything.
cd "${REPO_ROOT}"/build
ninja check-all-llvm-toolchain
