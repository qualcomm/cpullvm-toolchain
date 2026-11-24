# Copyright (c) Qualcomm Technologies, Inc. and/or its subsidiaries.
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

#Requires -Version 7.4

param(
    [Parameter(Mandatory,
    HelpMessage="Path to directory to find Clang/LLVM tools")]
    [string]$ToolsPath,
    [Parameter(Mandatory,
    HelpMessage="Directory for the build")]
    [string]$BaseBuildDir,
    [Parameter(Mandatory,
    HelpMessage="Directory for the install")]
    [string]$BaseInstallDir,
    [Parameter(Mandatory,
    HelpMessage="Directory of the LLVM sources")]
    [string]$LLVMSrcDir
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

Write-Host "Options: -ToolsPath $ToolsPath -BaseBuildDir $BaseBuildDir -BaseInstallDir $BaseInstallDir -LLVMSrcDir $LLVMSrcDir"

$env:Path = $ToolsPath + ";" + $env:Path

$Variants= @("x86_64", "aarch64")
$VariantTargets = @{
    x86_64 = "x86_64-windows-msvc"
    aarch64 = "aarch64-windows-msvc"
}

# We link against Visual Studio libraries; make sure we can find them.

$vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
$hostArch = $env:PROCESSOR_ARCHITECTURE
$vcVarsTargets = $null
# We need to invoke vcvarsall.bat differently depending on the host.
if ($hostArch -eq 'ARM64') {
  $vcVarsTargets = @{
    x86_64 = "arm64_x64"
    aarch64 = "arm64"
  }
} else {
  $vcVarsTargets = @{
    x86_64 = "x64"
    aarch64 = "x64_arm64"
  }
}

# Find an appropriate VS install.
$VS_INSTALL = & $vswhere -latest -products * `
  -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
  -requires Microsoft.VisualStudio.Component.VC.Tools.ARM64 `
  -property installationPath

if (-not $VS_INSTALL) {
  throw "*** ERROR: Visual Studio installation missing components (need both x86 and arm64 compilers)"
}

$VCVARSALL = Join-PATH $VS_INSTALL "VC\Auxiliary\Build\vcvarsall.bat"
if (-not (Test-Path $VCVARSALL)) {
  throw "*** ERROR: vcvarsall.bat not found."
}
Write-Host "Visual Studio installation: $VS_INSTALL"
Write-Host "Requested MSVC toolset: $env:CPULLVM_MSVC_TOOLSET"

$vsEnvironmentVariables = @(
  'INCLUDE',
  'LIB',
  'LIBPATH',
  'VCINSTALLDIR',
  'VCToolsInstallDir',
  'VCToolsRedistDir',
  'VCToolsVersion',
  'VSCMD_ARG_HOST_ARCH',
  'VSCMD_ARG_TGT_ARCH',
  'VSCMD_VER'
)

foreach ($Variant in $Variants) {
  Write-Host "Windows runtime variant: $Variant"
  $VariantBaseBuildDir="$BaseBuildDir\$Variant"
  mkdir $VariantBaseBuildDir -ErrorAction SilentlyContinue

  # Switch environment to the current variant.
  foreach ($variable in $vsEnvironmentVariables) {
    Remove-Item "Env:$variable" -ErrorAction SilentlyContinue
  }
  $vcvarsTarget = $vcvarsTargets[$Variant]
  $vcvarsArgs = $vcvarsTarget
  if ($env:CPULLVM_MSVC_TOOLSET) {
    $toolsetDir = Join-Path $VS_INSTALL "VC\Tools\MSVC\$env:CPULLVM_MSVC_TOOLSET"
    if (-not (Test-Path $toolsetDir)) {
      throw "Requested MSVC toolset $env:CPULLVM_MSVC_TOOLSET is not installed at $toolsetDir."
    }
    $vcvarsArgs += " -vcvars_ver=$env:CPULLVM_MSVC_TOOLSET"
  }
  Write-Host "Initializing Visual Studio environment: $vcvarsArgs"
  $vcvarsEnvironment = cmd /c "call `"$VCVARSALL`" $vcvarsArgs && set"
  if ($LASTEXITCODE -ne 0) {
    throw "vcvarsall.bat failed for $Variant with exit code $LASTEXITCODE."
  }
  $vcvarsEnvironment | ForEach-Object {
    if ($_ -match '^(.*?)=(.*)$') {
      [System.Environment]::SetEnvironmentVariable($matches[1], $matches[2], 'Process')
    }
  }
  Write-Host "Selected MSVC toolset: $env:VCToolsVersion"
  Write-Host "MSVC tools directory: $env:VCToolsInstallDir"
  Write-Host "Selected Visual Studio target architecture: $env:VSCMD_ARG_TGT_ARCH"
  Write-Host "MSVC library path: $env:LIB"

  $VariantTarget = $VariantTargets[$Variant]
  $expectedTargetArch = if ($Variant -eq 'aarch64') { 'arm64' } else { 'x64' }
  if ($env:VSCMD_ARG_TGT_ARCH -ne $expectedTargetArch) {
    throw "Visual Studio environment selected $env:VSCMD_ARG_TGT_ARCH instead of $expectedTargetArch for $Variant."
  }
  if (-not $env:LIB -or $env:LIB -notmatch "(?i)\\lib\\$expectedTargetArch(?:;|$)") {
    throw "Visual Studio library path does not contain $expectedTargetArch libraries for $Variant."
  }
  $CompilerRtBuildDir="$VariantBaseBuildDir/compiler-rt"
  cmake -G Ninja `
      -DCMAKE_INSTALL_PREFIX="$BaseInstallDir" `
      -DCMAKE_BUILD_TYPE="Release" `
      -DCMAKE_C_COMPILER="clang-cl" `
      -DCMAKE_CXX_COMPILER="clang-cl" `
      -DCMAKE_SYSTEM_NAME="Windows" `
      -DCOMPILER_RT_DEFAULT_TARGET_ONLY=ON `
      -DCMAKE_ASM_COMPILER_TARGET="$VariantTarget" `
      -DCMAKE_C_COMPILER_TARGET="$VariantTarget" `
      -DCMAKE_CXX_COMPILER_TARGET="$VariantTarget" `
      -DLLVM_ENABLE_PER_TARGET_RUNTIME_DIR=ON `
      -DCOMPILER_RT_BUILD_BUILTINS=ON `
      -DCOMPILER_RT_BUILD_LIBFUZZER=OFF `
      -DCOMPILER_RT_SANITIZERS_TO_BUILD="" `
      -DCOMPILER_RT_BUILD_ORC=OFF `
      -DCOMPILER_RT_BUILD_XRAY=OFF `
      -DLLVM_ENABLE_RUNTIMES=compiler-rt `
      -DCMAKE_EXE_LINKER_FLAGS="-fuse-ld=lld" `
      -DCMAKE_SHARED_LINKER_FLAGS="-fuse-ld=lld" `
      -DCMAKE_MODULE_LINKER_FLAGS="-fuse-ld=lld" `
      -B "$CompilerRtBuildDir" `
      -S "$LLVMSrcDir/runtimes"
  if ($LASTEXITCODE -ne 0) {
    throw "CMake configuration failed for $Variant with exit code $LASTEXITCODE."
  }
  ninja -C "$CompilerRtBuildDir" install
  if ($LASTEXITCODE -ne 0) {
    throw "Runtime build failed for $Variant with exit code $LASTEXITCODE."
  }
}
