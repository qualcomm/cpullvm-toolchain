# Copyright (c) Qualcomm Technologies, Inc. and/or its subsidiaries.
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

# Used by lldb
choco install swig

# Install pinned libxml2 for the host architecture. LLDB requires libxml2 2.8 or newer.
$vcpkgTriplet = if ($env:PROCESSOR_ARCHITECTURE -eq "ARM64") { "arm64-windows" } else { "x64-windows" }
$vcpkgRoot = $env:VCPKG_INSTALLATION_ROOT
$manifestRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
Push-Location $manifestRoot
try {
    & "$vcpkgRoot\vcpkg.exe" install "--triplet=$vcpkgTriplet"
    if ($LASTEXITCODE -ne 0) {
        throw "vcpkg failed to install libxml2"
    }
} finally {
    Pop-Location
}

$libxml2Prefix = Join-Path $manifestRoot "vcpkg_installed\$vcpkgTriplet"
Add-Content -Path $env:GITHUB_ENV -Value "CMAKE_PREFIX_PATH=$libxml2Prefix"
Add-Content -Path $env:GITHUB_PATH -Value (Join-Path $libxml2Prefix "bin")

# Install pyyaml
pip install pyyaml

# Install meson. eld support was added in v1.9.0, so we need at least that.
pip install meson==1.10.0

# Install psutil
python -m pip install psutil

# Install Clang 22.1.8 - only on Windows-x86_64 and AArch64 runner
$ClangVersion = "22.1.8"
$BaseUrl = "https://github.com/llvm/llvm-project/releases/download/llvmorg-$ClangVersion"

if ($env:PROCESSOR_ARCHITECTURE -eq "AMD64") {
    # x86_64 runner (windows-2025)
    $InstallerUrl = "$BaseUrl/LLVM-$ClangVersion-win64.exe"
} elseif ($env:PROCESSOR_ARCHITECTURE -eq "ARM64") {
    # AArch64 runner (windows-11-arm)
    $InstallerUrl = "$BaseUrl/LLVM-$ClangVersion-woa64.exe"
} else {
    Write-Host "Unsupported architecture: $env:PROCESSOR_ARCHITECTURE — skipping Clang install"
    exit 0
}

$InstallerPath = "$env:TEMP\LLVM-$ClangVersion-win64.exe"

Write-Host "Downloading LLVM $ClangVersion for $env:PROCESSOR_ARCHITECTURE ..."
Invoke-WebRequest -Uri $InstallerUrl -OutFile $InstallerPath -UseBasicParsing

Write-Host "Installing LLVM $ClangVersion to C:\Program Files\LLVM ..."
Start-Process -FilePath $InstallerPath `
              -ArgumentList "/S", "/D=C:\Program Files\LLVM" `
              -Wait -NoNewWindow

& "C:\Program Files\LLVM\bin\clang-cl.exe" --version
