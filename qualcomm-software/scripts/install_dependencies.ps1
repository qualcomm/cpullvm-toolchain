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
