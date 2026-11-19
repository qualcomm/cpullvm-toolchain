# Copyright (c) Qualcomm Technologies, Inc. and/or its subsidiaries.
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

param(
    [string]$BuildDir
)

function Build-StaticLibXml2 {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BuildDir
    )

    $libxmlVersion = '2.15.3'
    $libxmlArchive = Join-Path $BuildDir "libxml2-v$libxmlVersion.tar.gz"
    $libxmlSource = Join-Path $BuildDir "libxml2-v$libxmlVersion"
    $libxmlBuildDir = Join-Path $BuildDir 'libxml2-build'
    $libxmlInstallDir = Join-Path $libxmlBuildDir 'install'
    $libxmlExportsHeader = Join-Path $libxmlInstallDir 'include/libxml2/libxml/xmlexports.h'

    if ((Test-Path "$libxmlInstallDir/include/libxml2/libxml/xmlreader.h") -and
        (Test-Path "$libxmlInstallDir/lib/libxml2s.lib") -and
        (Test-Path $libxmlExportsHeader) -and
        (Get-Content -Raw $libxmlExportsHeader).Contains('#if 0 /* LIBXML_STATIC */')) {
        return
    }

    # Build static libxml2 without optional external dependencies.
    Invoke-WebRequest `
      -Uri "https://gitlab.gnome.org/GNOME/libxml2/-/archive/v$libxmlVersion/libxml2-v$libxmlVersion.tar.gz" `
      -OutFile $libxmlArchive
    if ((Get-FileHash $libxmlArchive -Algorithm SHA256).Hash -ne '0DA50C1415F4EC0364569D2119B1436BA837B31DF44AF28569D234272C23CF1F') {
        throw "Unexpected SHA256 for libxml2 $libxmlVersion"
    }
    & tar.exe -xzf $libxmlArchive -C $BuildDir
    if ($LASTEXITCODE -ne 0) {
        throw 'Failed to extract libxml2'
    }

    $libxmlCmakeArgs = @(
        '-DCMAKE_BUILD_TYPE=Release',
        "-DCMAKE_INSTALL_PREFIX=$libxmlInstallDir",
        '-DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreadedDLL',
        '-DBUILD_SHARED_LIBS=OFF',
        '-DLIBXML2_WITH_ICONV=OFF',
        '-DLIBXML2_WITH_ICU=OFF',
        '-DLIBXML2_WITH_READLINE=OFF',
        '-DLIBXML2_WITH_ZLIB=OFF',
        '-DLIBXML2_WITH_PROGRAMS=OFF',
        '-DLIBXML2_WITH_TESTS=OFF'
    )
    cmake -S $libxmlSource -B $libxmlBuildDir -GNinja @libxmlCmakeArgs
    if ($LASTEXITCODE -ne 0) {
        throw 'Failed to configure libxml2'
    }
    cmake --build $libxmlBuildDir --target install
    if ($LASTEXITCODE -ne 0) {
        throw 'Failed to build libxml2'
    }
    if (-not (Test-Path "$libxmlInstallDir/include/libxml2/libxml/xmlreader.h")) {
        throw 'libxml2 headers were not installed'
    }
    if (-not (Test-Path "$libxmlInstallDir/lib/libxml2s.lib")) {
        throw 'libxml2 static library was not installed'
    }
    $libxmlExportsContents = Get-Content -Raw $libxmlExportsHeader
    if (-not $libxmlExportsContents.Contains('#if (defined(_WIN32) || defined(__CYGWIN__)) && !defined(LIBXML_STATIC)')) {
        throw 'Unexpected libxml2 static-export guard'
    }
    # FindLibXml2 does not propagate LIBXML_STATIC to its configure checks on Windows.
    $libxmlExportsContents = $libxmlExportsContents.Replace(
        '#if (defined(_WIN32) || defined(__CYGWIN__)) && !defined(LIBXML_STATIC)',
        '#if 0 /* LIBXML_STATIC */'
    )
    Set-Content -Path $libxmlExportsHeader -Value $libxmlExportsContents -NoNewline -Encoding utf8
}

if ($BuildDir) {
    Build-StaticLibXml2 -BuildDir $BuildDir
}
