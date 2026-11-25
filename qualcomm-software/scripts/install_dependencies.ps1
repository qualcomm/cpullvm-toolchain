# Copyright (c) Qualcomm Technologies, Inc. and/or its subsidiaries.
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

# Pin the x64 MSVC STL to the known Clang 20-compatible toolset.
if ($env:PROCESSOR_ARCHITECTURE -eq 'AMD64') {
  $msvcToolset = '14.51.36231'
  $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
  $vsInstall = & $vswhere -latest -products * -property installationPath
  if (-not $vsInstall) {
    throw 'Could not find a Visual Studio installation.'
  }

  $toolsetDir = Join-Path $vsInstall "VC\Tools\MSVC\$msvcToolset"
  $atlHeader = Join-Path $toolsetDir 'atlmfc\include\atlbase.h'
  $atlLibrary = Join-Path $toolsetDir 'atlmfc\lib\x64\atls.lib'
  $arm64CrtLibrary = Join-Path $toolsetDir 'lib\arm64\msvcrtd.lib'
  Write-Host "Checking for MSVC $msvcToolset, ATL, and ARM64 runtime support."
  if (-not ((Test-Path $toolsetDir) -and (Test-Path $atlHeader) -and (Test-Path $atlLibrary) -and (Test-Path $arm64CrtLibrary))) {
    Write-Host "Installing MSVC $msvcToolset, ATL, and ARM64 runtime support."
    $vsInstaller = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\setup.exe'
    $installation = Start-Process -FilePath $vsInstaller -ArgumentList @(
      'modify', '--installPath', "`"$vsInstall`"",
      '--add', 'Microsoft.VisualStudio.Component.VC.14.51.x86.x64',
      '--add', 'Microsoft.VisualStudio.Component.VC.14.51.ARM64',
      # MFC installs the matching ATL headers and libraries required by LLVM DIA.
      '--add', 'Microsoft.VisualStudio.Component.VC.14.51.MFC',
      '--quiet', '--norestart'
    ) -Wait -PassThru
    if ($installation.ExitCode -notin @(0, 3010)) {
      throw "Installing MSVC $msvcToolset failed with exit code $($installation.ExitCode)."
    }
  } else {
    Write-Host "MSVC $msvcToolset, ATL, and ARM64 runtime support are already installed."
  }
  if (-not ((Test-Path $toolsetDir) -and (Test-Path $atlHeader) -and (Test-Path $atlLibrary) -and (Test-Path $arm64CrtLibrary))) {
    throw "MSVC $msvcToolset or its required ATL and ARM64 runtime libraries were not installed."
  }

  $env:CPULLVM_MSVC_TOOLSET = $msvcToolset
  Write-Host "Using MSVC $msvcToolset from $toolsetDir."
  if ($env:GITHUB_ENV) {
    "CPULLVM_MSVC_TOOLSET=$msvcToolset" >> $env:GITHUB_ENV
  }
}

# Used by lldb
choco install swig

# Install pyyaml
pip install pyyaml

# Install meson. eld support was added in v1.9.0, so we need at least that.
pip install meson==1.10.0
