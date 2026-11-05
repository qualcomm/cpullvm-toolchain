# Copyright (c) Qualcomm Technologies, Inc. and/or its subsidiaries.
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

# Used by lldb
choco install swig

# Install libxml2 for the host architecture. LLDB requires libxml2 2.8 or newer,
# so use the current vcpkg port rather than the older Chocolatey package.
$vcpkgTriplet = if ($env:PROCESSOR_ARCHITECTURE -eq "ARM64") { "arm64-windows" } else { "x64-windows" }
$vcpkgRoot = $env:VCPKG_INSTALLATION_ROOT
& "$vcpkgRoot\vcpkg.exe" install "libxml2:$vcpkgTriplet"
if ($LASTEXITCODE -ne 0) {
    throw "vcpkg failed to install libxml2"
}

$libxml2Prefix = Join-Path $vcpkgRoot "installed\$vcpkgTriplet"
Add-Content -Path $env:GITHUB_ENV -Value "CMAKE_PREFIX_PATH=$libxml2Prefix"
Add-Content -Path $env:GITHUB_PATH -Value (Join-Path $libxml2Prefix "bin")

# Install pyyaml
pip install pyyaml

# Install meson. eld support was added in v1.9.0, so we need at least that.
pip install meson==1.10.0

# Install psutil
python -m pip install psutil