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

#Requires -Version 7.4

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

. "$PSScriptRoot\init_win_env.ps1"
Set-VS-Env
. "$PSScriptRoot\build_static_libxml2.ps1"

$repoRoot = git -C $PSScriptRoot rev-parse --show-toplevel
$buildDir = (Join-Path $repoRoot build)

$env:CC = 'clang-cl'
$env:CXX = 'clang-cl'

mkdir $buildDir
Build-StaticLibXml2 -BuildDir $buildDir

cd $buildDir

# Omit Linux runtimes, QEMU testing on Windows builds.
$extraCmakeArgs = @()
if ($env:EXTRA_CMAKE_ARGS) {
    $extraCmakeArgs = $env:EXTRA_CMAKE_ARGS -split '\s+'
}
$extraCmakeArgs += Get-StaticLibXml2CMakeArgs -BuildDir $buildDir

cmake ..\qualcomm-software `
  -GNinja `
  -DFETCHCONTENT_QUIET=OFF `
  -DENABLE_QEMU_TESTING=OFF `
  @extraCmakeArgs

ninja package-llvm-toolchain
