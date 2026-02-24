# Copyright (c) 2025, Arm Limited and affiliates.
# Part of the Arm Toolchain project, under the Apache License v2.0 with LLVM Exceptions.
# See https://llvm.org/LICENSE.txt for license information.
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#
# Changes from Qualcomm Technologies, Inc. are provided under the following license:
# Copyright (c) Qualcomm Technologies, Inc. and/or its subsidiaries.
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

# A Powershell script to build the toolchain

# The script creates a build of the toolchain in the 'build' directory, inside
# the repository tree.

$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\init_win_env.ps1"
Set-VS-Env

$repoRoot = git -C $PSScriptRoot rev-parse --show-toplevel
$buildDir = (Join-Path $repoRoot build)

mkdir $buildDir
cd $buildDir

# Omit target runtimes on Windows builds.
cmake ..\qualcomm-software `
  -GNinja `
  -DFETCHCONTENT_QUIET=OFF `
  -DLLVM_TOOLCHAIN_DISTRIBUTION_COMPONENTS="llvm-toolchain-docs;llvm-toolchain-third-party-licenses" `
  -DPREBUILT_TARGET_LIBRARIES=ON `
  -DCMAKE_C_COMPILER=clang-cl `
  -DCMAKE_CXX_COMPILER=clang-cl

ninja package-llvm-toolchain
