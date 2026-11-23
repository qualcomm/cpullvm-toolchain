# A Powershell script to find and call vcvarsall to setup the environment for
# building with Visual Studio tools and libraries.
function Set-VS-Env {
  # Host architecture detection
  $hostArch = $env:PROCESSOR_ARCHITECTURE
  switch -Regex ($hostArch) {
    'ARM64' { $hostArch = 'ARM64' }
    'AMD64' { $hostArch = 'x64' }
    default {
        Write-Error "*** ERROR: unrecognized PROCESSOR_ARCHITECTURE ***"
        exit 1
    }
  }

  $vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"

  # Choose VS component and vcvars target
  $vsRequires  = $null
  $vcvarsTarget = $null
  if ($hostArch -eq 'ARM64') {
      $vsRequires   = 'Microsoft.VisualStudio.Component.VC.Tools.ARM64'
      $vcvarsTarget = 'arm64'
  } else {
      $vsRequires   = 'Microsoft.VisualStudio.Component.VC.Tools.x86.x64'
      $vcvarsTarget = 'x64'
  }

  # Query the latest VS with required component
  $VS_INSTALL = & $vswhere -latest -products * `
    -requires $vsRequires `
    -property installationPath
  if (-not $VS_INSTALL) {
    Write-Error "*** ERROR: Visual Studio installation with '$vsRequires' not found via vswhere ***"
    exit 1
  }

  # Get vcvarsall.bat and import the environment for selected host
  $VCVARSALL = Join-Path $VS_INSTALL "VC\Auxiliary\Build\vcvarsall.bat"
  if (-not (Test-Path $VCVARSALL)) {
    Write-Error "*** ERROR: vcvarsall.bat not found at $VCVARSALL ***"
    exit 1
  }

  $vcvarsArgs = $vcvarsTarget
  if ($env:CPULLVM_MSVC_TOOLSET) {
    $toolsetDir = Join-Path $VS_INSTALL "VC\Tools\MSVC\$env:CPULLVM_MSVC_TOOLSET"
    if (-not (Test-Path $toolsetDir)) {
      throw "Requested MSVC toolset $env:CPULLVM_MSVC_TOOLSET is not installed at $toolsetDir."
    }
    $vcvarsArgs += " -vcvars_ver=$env:CPULLVM_MSVC_TOOLSET"
  }

  cmd /c "call `"$VCVARSALL`" $vcvarsArgs && set" | ForEach-Object {
    if ($_ -match '^(.*?)=(.*)$') {
      [System.Environment]::SetEnvironmentVariable($matches[1], $matches[2], 'Process')
    }
  }
  Write-Host "Selected MSVC toolset: $env:VCToolsVersion"
}
