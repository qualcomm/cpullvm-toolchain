#!/usr/bin/env bash

# Copyright (c) 2025, Arm Limited and affiliates.
# Part of the Arm Toolchain project, under the Apache License v2.0 with LLVM Exceptions.
# See https://llvm.org/LICENSE.txt for license information.
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#
# Changes from Qualcomm Technologies, Inc. are provided under the following license:
# Copyright (c) Qualcomm Technologies, Inc. and/or its subsidiaries.
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

# The script assumes a successful build of the toolchain exists in the
# 'build_picolibc-v1812_overlay' directory inside the repository tree.

set -ex

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
REPO_ROOT=$( git -C "${SCRIPT_DIR}" rev-parse --show-toplevel )

# Run only the library and multilib lit tests. Run libc++ tests for only a few
# variants to keep the runtime acceptable.
cd "${REPO_ROOT}"/build_picolibc-v1812_overlay
ninja check-llvm-toolchain
ninja check-cxxabi
ninja check-unwind
ninja check-cxx-aarch64a_tlsie
ninja check-cxx-armv7a_soft_nofp
ninja check-cxx-riscv32imac_ilp32
ninja check-cxx-riscv64gc_lp64_nopic
