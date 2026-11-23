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
  Write-Host "Checking for MSVC $msvcToolset and ATL support."
  if (-not ((Test-Path $toolsetDir) -and (Test-Path $atlHeader) -and (Test-Path $atlLibrary))) {
    Write-Host "Installing MSVC $msvcToolset and ATL support."
    $vsInstaller = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\setup.exe'
    $installation = Start-Process -FilePath $vsInstaller -ArgumentList @(
      'modify', '--installPath', "`"$vsInstall`"",
      '--add', 'Microsoft.VisualStudio.Component.VC.14.51.x86.x64',
      # MFC installs the matching ATL headers and libraries required by LLVM DIA.
      '--add', 'Microsoft.VisualStudio.Component.VC.14.51.MFC',
      '--quiet', '--norestart'
    ) -Wait -PassThru
    if ($installation.ExitCode -notin @(0, 3010)) {
      throw "Installing MSVC $msvcToolset failed with exit code $($installation.ExitCode)."
    }
  } else {
    Write-Host "MSVC $msvcToolset and ATL support are already installed."
  }
  if (-not ((Test-Path $toolsetDir) -and (Test-Path $atlHeader) -and (Test-Path $atlLibrary))) {
    throw "MSVC $msvcToolset or its ATL headers and x64 libraries were not installed."
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
