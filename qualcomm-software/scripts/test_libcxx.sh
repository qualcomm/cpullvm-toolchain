#!/usr/bin/env bash

# Copyright (c) 2025, Arm Limited and affiliates.
# Part of the Arm Toolchain project, under the Apache License v2.0 with LLVM Exceptions.
# See https://llvm.org/LICENSE.txt for license information.
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#
# Changes from Qualcomm Technologies, Inc. are provided under the following license:
# Copyright (c) Qualcomm Technologies, Inc. and/or its subsidiaries. 
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

# A bash script to run the libc++ tests for the Qualcomm embedded toolchain.
#
# These tests are kept separate from test.sh because ninja check-cxx takes
# significantly longer to run than the rest of the test suite.  Run this
# script in addition to test.sh when libc++ test coverage is required.
#
# The script assumes a successful build of the toolchain exists in the 'build'
# directory inside the repository tree.

set -ex

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
REPO_ROOT=$( git -C "${SCRIPT_DIR}" rev-parse --show-toplevel )

cd "${REPO_ROOT}"/build
ninja check-cxx-aarch64a_tlsie
ninja check-cxx-armv7a_hard_vfpv3
ninja check-cxx-armv7a_soft_neon
ninja check-cxx-armv7a_soft_nofp
ninja check-cxx-armv7m_hard_fpv5_d16_nopic
ninja check-cxx-armv7m_soft_nofp
ninja check-cxx-armv7m_soft_nofp_nopic
ninja check-cxx-armv8_soft_neon
ninja check-cxx-riscv32gc_ilp32d
ninja check-cxx-riscv32imac_ilp32
ninja check-cxx-riscv32imac_zba_zbb_ilp32_nopic
ninja check-cxx-riscv32imafc_zcb_zcmp_zba_zbb_ilp32f
ninja check-cxx-riscv64gc_lp64_nopic
ninja check-cxx-riscv64gc_zba_zbb_lp64d_nopic
ninja check-cxx-riscv64imac_lp64_nopic
