# A Powershell script to find and call vcvarsall to setup the environment for
# building with Visual Studio tools and libraries.

# Run a native command and throw if it exits non-zero. $ErrorActionPreference
# does not apply to native commands, and Windows PowerShell 5.1 has no
# equivalent of $PSNativeCommandUseErrorActionPreference.
function Invoke-Checked {
  param([Parameter(Mandatory)][scriptblock]$Command)
  & $Command
  if ($LASTEXITCODE -ne 0) {
    throw "Command failed with exit code ${LASTEXITCODE}: $Command"
  }
}

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

  Invoke-Checked { cmd /c "call `"$VCVARSALL`" $vcvarsTarget && set" } | ForEach-Object {
    if ($_ -match '^(.*?)=(.*)$') {
      [System.Environment]::SetEnvironmentVariable($matches[1], $matches[2], 'Process')
    }
  }
}