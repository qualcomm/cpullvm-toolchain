# Copyright (c) 2025, Arm Limited and affiliates.
# Part of the Arm Toolchain project, under the Apache License v2.0 with LLVM Exceptions.
# See https://llvm.org/LICENSE.txt for license information.
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#
# Changes from Qualcomm Technologies, Inc. are provided under the following license:
# Copyright (c) Qualcomm Technologies, Inc. and/or its subsidiaries. 
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception


# A Powershell script to run the tests for the toolchain. The script assumes a
# successful build of the toolchain exists in the 'build' directory inside the
# repository tree.

$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\init_win_env.ps1"
Set-VS-Env

$repoRoot = git -C $PSScriptRoot rev-parse --show-toplevel
$buildDir = (Join-Path $repoRoot build)

cd $buildDir

ninja check-llvm-toolchain
