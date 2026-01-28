# Fail fast on errors thrown by PowerShell cmdlets
$ErrorActionPreference = "Stop"

# === Derive directories ===
$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Definition
$REPO_ROOT  = (git -C $SCRIPT_DIR rev-parse --show-toplevel).Trim()
$WORKSPACE  = (Resolve-Path "$REPO_ROOT\..").Path

$SRC_DIR     = $REPO_ROOT
$BUILD_DIR   = "$WORKSPACE\build"
$INSTALL_DIR = "$WORKSPACE\install"
$ELD_DIR     = "$REPO_ROOT\llvm\tools\eld"
$MUSL_EMBEDDED_DIR = "$WORKSPACE\musl-embedded"

# === Config defaults ===
if (-not $env:JOBS)           { $env:JOBS           = $env:NUMBER_OF_PROCESSORS }
if (-not $env:BUILD_MODE)     { $env:BUILD_MODE     = "Release" }
if (-not $env:ASSERTION_MODE) { $env:ASSERTION_MODE = "OFF" }

# === Constants ===
$ELD_REPO_URL = "https://github.com/qualcomm/eld.git"
$ELD_BRANCH   = "release/22.x"
$ELD_COMMIT   = "58e68232ef5f85b3a53b594975a195445e3ec8da"

$MUSL_EMBEDDED_REPO_URL = "https://github.com/qualcomm/musl-embedded.git"
$MUSL_EMBEDDED_BRANCH   = "main"
$MUSL_EMBEDDED_COMMIT   = "a2bc89ab37e8691e300d7a7dd96bfac4917dc884"

Write-Host "[log] SCRIPT_DIR   = $SCRIPT_DIR"
Write-Host "[log] REPO_ROOT    = $REPO_ROOT"
Write-Host "[log] WORKSPACE    = $WORKSPACE"
Write-Host "[log] BUILD_DIR    = $BUILD_DIR"
Write-Host "[log] INSTALL_DIR  = $INSTALL_DIR"
Write-Host "[log] ELD_DIR      = $ELD_DIR"
Write-Host "[log] BUILD_MODE   = $env:BUILD_MODE"
Write-Host "[log] ASSERTIONS   = $env:ASSERTION_MODE"
Write-Host "[log] JOBS         = $env:JOBS"

# === Host architecture detection ===
$hostArch = $env:PROCESSOR_ARCHITECTURE
switch -Regex ($hostArch) {
  'ARM64' { $hostArch = 'ARM64' }
  'AMD64' { $hostArch = 'x64' }
  default { $hostArch = 'x64' } # safe default
}
Write-Host "[log] Host architecture detected: $hostArch"

# Allow overriding to x64 tools on WoA via emulation (optional)
$useX64Tools = ($env:USE_X64_TOOLS -eq '1')
if ($hostArch -eq 'ARM64' -and $useX64Tools) {
    Write-Warning "[warn] Forcing x64 toolchain under emulation on Windows on Arm (USE_X64_TOOLS=1). Expect slower builds."
}

# === Resolve Visual Studio (vswhere) ===
$vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
if (-not (Test-Path $vswhere)) {
    $vswhere = Join-Path ${env:ProgramFiles} "Microsoft Visual Studio\Installer\vswhere.exe"
}
if (-not (Test-Path $vswhere)) {
    $cmd = Get-Command vswhere -ErrorAction Ignore
    if ($cmd) { $vswhere = $cmd.Source }
}
if (-not (Test-Path $vswhere)) {
    Write-Error "*** ERROR: vswhere.exe not found in Program Files (x86), Program Files, or PATH ***"
    exit 1
}

# === Choose VS component and vcvars target ===
$vsRequires  = $null
$vcvarsTarget = $null
if ($hostArch -eq 'ARM64' -and -not $useX64Tools) {
    $vsRequires   = 'Microsoft.VisualStudio.Component.VC.Tools.ARM64'
    $vcvarsTarget = 'arm64'
    Write-Host "[log] Using native ARM64 MSVC toolset"
} else {
    $vsRequires   = 'Microsoft.VisualStudio.Component.VC.Tools.x86.x64'
    $vcvarsTarget = 'x64'
    Write-Host "[log] Using x64 MSVC toolset"
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

Write-Host "[log] Loading VS environment: vcvarsall $vcvarsTarget"
cmd /c "call `"$VCVARSALL`" $vcvarsTarget && set" | ForEach-Object {
    if ($_ -match '^(.*?)=(.*)$') {
        [System.Environment]::SetEnvironmentVariable($matches[1], $matches[2], 'Process')
    }
}

# Tool sanity checks
foreach ($tool in @("git","python","cmake","ninja","clang-cl")) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        Write-Error "*** ERROR: $tool not found on PATH ***"
        exit 1
    }
}

# === Clean ===
Write-Host "[log] Cleaning $BUILD_DIR and $INSTALL_DIR"
Remove-Item -Recurse -Force $BUILD_DIR,$INSTALL_DIR -ErrorAction SilentlyContinue

# === Prepare workspace ===
Write-Host "[log] Preparing workspace at: $WORKSPACE"
New-Item -ItemType Directory -Force -Path $BUILD_DIR,$INSTALL_DIR | Out-Null

# === Clone repos ===
if (-not (Test-Path "$MUSL_EMBEDDED_DIR\.git")) {
    Write-Host "[log] Cloning musl-embedded..."
    git clone $MUSL_EMBEDDED_REPO_URL $MUSL_EMBEDDED_DIR
    Push-Location $MUSL_EMBEDDED_DIR
    git checkout $MUSL_EMBEDDED_COMMIT
    Pop-Location
}

if (-not (Test-Path "$ELD_DIR\.git")) {
    Write-Host "[log] Cloning ELD..."
    git clone $ELD_REPO_URL $ELD_DIR
    Push-Location $ELD_DIR
    git checkout $ELD_COMMIT
    Pop-Location
}

# === Apply patches ===
Push-Location $SRC_DIR
python "qualcomm-software/embedded/tools/patchctl.py" apply -f "qualcomm-software/embedded/patchsets.yml"

if ($LASTEXITCODE -ne 0) {
    Write-Error "*** ERROR: Patch apply failed (exit=$LASTEXITCODE) ***"
    exit $LASTEXITCODE
}

Pop-Location

# === Build ===
Write-Host "[log] Configuring CMake..."

# Provide Python to CMake/lit if available
$pythonExe = (Get-Command python -ErrorAction SilentlyContinue).Source
if ($pythonExe) { Write-Host "[log] Using Python: $pythonExe" } else { Write-Host "[warn] Python not found via Get-Command; relying on PATH" }

# --- Resource compiler selection (prefer llvm-rc) ---
$llvmRcCandidates = @(
  (Join-Path $VS_INSTALL 'VC\Tools\Llvm\{0}\bin\llvm-rc.exe' -f $vcvarsTarget), # ...\Llvm\arm64\bin or ...\Llvm\x64\bin
  (Join-Path $VS_INSTALL 'VC\Tools\Llvm\bin\llvm-rc.exe'),                      # generic bin in some layouts
  'C:\Program Files\LLVM\bin\llvm-rc.exe'                                       # Standalone LLVM
) | Where-Object { Test-Path $_ }

$llvmRc = $llvmRcCandidates | Select-Object -First 1

$cmakeRcArg = ''
if ($llvmRc) {
    Write-Host "[log] Using llvm-rc: $llvmRc"
    # Normalize to forward slashes to keep CMake from parsing backslash escapes
    $llvmRcForCMake = $llvmRc -replace '\\','/'
    # FILEPATH type prevents quoting glitches in the generated CMakeRCCompiler.cmake
    $cmakeRcArg = "-DCMAKE_RC_COMPILER:FILEPATH=$llvmRcForCMake"
    Write-Host "[diag] CMAKE_RC_COMPILER = $llvmRcForCMake"
} else {
    Write-Warning "[warn] llvm-rc.exe not found; falling back to Windows rc.exe (may hang)."
}

# --- Generation ---
cmake -G "Ninja" `
  -S "$SRC_DIR\llvm" `
  -B "$BUILD_DIR\llvm" `
  -DCMAKE_INSTALL_PREFIX="$INSTALL_DIR" `
  -DLLVM_TARGETS_TO_BUILD="ARM;AArch64;RISCV" `
  -DLLVM_EXTERNAL_PROJECTS="eld" `
  -DLLVM_EXTERNAL_ELD_SOURCE_DIR="$ELD_DIR" `
  -DLLVM_DEFAULT_TARGET_TRIPLE="aarch64-unknown-linux-gnu" `
  -DLIBCLANG_BUILD_STATIC=ON `
  -DLLVM_POLLY_LINK_INTO_TOOLS=ON `
  -DCMAKE_C_COMPILER=clang-cl `
  -DCMAKE_CXX_COMPILER=clang-cl `
  -DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreadedDLL `
  -DLLVM_ENABLE_ASSERTIONS="$env:ASSERTION_MODE" `
  -DLLVM_ENABLE_PROJECTS="llvm;clang;polly;lld;mlir" `
  $(if ($pythonExe) { "-DPython3_EXECUTABLE=`"$pythonExe`"" } else { "" }) `
  $cmakeRcArg `
  -DCMAKE_BUILD_TYPE="$env:BUILD_MODE"

Push-Location "$BUILD_DIR\llvm"

# --- Build (Ninja) ---
Write-Host "[log] Building LLVM with Ninja..."
& ninja
if ($LASTEXITCODE -ne 0) { Write-Error "*** ERROR: build failed (exit=$LASTEXITCODE) ***"; exit $LASTEXITCODE }

# --- Install (Ninja) ---
Write-Host "[log] Install target..."
& ninja install
if ($LASTEXITCODE -ne 0) { Write-Error "*** ERROR: install failed (exit=$LASTEXITCODE) ***"; exit $LASTEXITCODE }

# === Prefer our build bin and ensure Git Unix tools are available ===
$env:PATH = "$BUILD_DIR\llvm\bin;$env:PATH"
$gitUsr = Join-Path ${env:ProgramFiles} "Git\usr\bin"
if (Test-Path $gitUsr) {
    $env:PATH = "$env:PATH;$gitUsr"
    Write-Host "[log] Added Git Unix tools to PATH: $gitUsr"
} else {
    Write-Warning "[warn] Git usr\bin not found; polly-check-format may fail (missing diff)."
}

# === Tests ===
Write-Host "[log] ===== BEGIN TEST SUITE ====="
$FAIL_COUNT = 0
foreach ($test in @("llvm","lld","eld","clang","polly")) {
    Write-Host "[log] Running $test tests..."
    & ninja -v "check-$test"
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[ERROR] $test tests failed! (exit=$LASTEXITCODE)"
        $FAIL_COUNT++
    } else {
        Write-Host "[log] $test tests completed."
    }
}

Write-Host "[log] ===== END TEST SUITE ====="
Pop-Location

if ($FAIL_COUNT -ne 0) {
    Write-Host "[log] Build completed, but $FAIL_COUNT test suite(s) failed."
    exit 1
}
Write-Host "[log] Build and all tests completed successfully!"

# --- Create artifact (PowerShell) ---

# Simple local log helpers
$__w_log  = { param($m) Write-Host    "[log] $m" }
$__w_warn = { param($m) Write-Warning "[warn] $m" }

# Compute identifiers
$short_sha = (git -C $SRC_DIR rev-parse --short HEAD).Trim()
$suffix    = Get-Date -Format "yyyyMMdd"

# Artifact roots and name
$archive_root = "$WORKSPACE\artifacts"
$archive_dir  = $INSTALL_DIR

# === select artifact arch label by host/toolset ===
$artifactArch = if ($hostArch -eq 'ARM64' -and -not $useX64Tools) { 'arm64' } else { 'x86_64' }

$base_name    = "cpullvm-toolchain-$($ELD_BRANCH.Split('/')[-1])-Windows-$artifactArch-$short_sha-$suffix"

& $__w_log "Applying NIGHTLY compression settings"
$COMPRESS_EXT = "txz"
$archive_name = "${base_name}_nightly.$COMPRESS_EXT"

$env:XZ_OPT   = "--threads=$JOBS"

# Ensure output directory exists
if (-not (Test-Path $archive_root)) { New-Item -ItemType Directory -Force -Path $archive_root | Out-Null }

$tar_file = Join-Path $archive_root $archive_name
& $__w_log "Compressing '$archive_dir' into '$tar_file'"

function Test-TarSupportsXz {
    try {
        $help = & tar --help 2>&1
        if ($LASTEXITCODE -ne 0) { return $false }
        return ($help -match '-J' -or $help -match 'xz')
    } catch { return $false }
}

function Get-7ZipPath {
    $candidates = @(
        (Get-Command 7z -ErrorAction SilentlyContinue | ForEach-Object { $_.Source }),
        "C:\Program Files\7-Zip\7z.exe",
        "C:\Program Files (x86)\7-Zip\7z.exe"
    ) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
    return $candidates
}

$usedTool = $null

# Preferred: tar with xz support (Git for Windows ships bsdtar)
$tarCmd = Get-Command tar -ErrorAction SilentlyContinue
if ($tarCmd) {
    if (Test-TarSupportsXz) {
        & tar -cJf "$tar_file" -C "$archive_dir" .
        if ($LASTEXITCODE -ne 0) { throw "tar failed with exit code $LASTEXITCODE" }
        $usedTool = "tar -cJf"
    } else {
        & $__w_warn "tar found but XZ (-J) not supported; falling back to 7‑Zip."
    }
} else {
    & $__w_warn "tar not found; attempting 7‑Zip fallback."
}

# Fallback: 7‑Zip (create .tar, then compress to .xz -> .txz)
if (-not $usedTool) {
    $sevenZip = Get-7ZipPath
    if (-not $sevenZip) {
        throw "No tar with xz support and no 7‑Zip found. Install Git for Windows (bsdtar) or 7‑Zip."
    }

    $tempTar = [System.IO.Path]::ChangeExtension($tar_file, ".tar")
    $tempXz  = [System.IO.Path]::ChangeExtension($tar_file, ".xz")
    if (Test-Path $tempTar) { Remove-Item -Force $tempTar }
    if (Test-Path $tempXz)  { Remove-Item -Force $tempXz  }

    & $__w_log "7‑Zip: creating tar archive '$tempTar'"
    Push-Location $archive_dir
    try {
        & "$sevenZip" a -bso0 -bse1 -ttar "$tempTar" "."
        if ($LASTEXITCODE -ne 0) { throw "7z (create tar) failed with exit code $LASTEXITCODE" }
    } finally {
        Pop-Location
    }

    & $__w_log "7‑Zip: compressing to XZ '$tempXz' (threads=$JOBS)"
    & "$sevenZip" a -bso0 -bse1 -txz -mx=9 -mmt=$JOBS "$tempXz" "$tempTar"
    if ($LASTEXITCODE -ne 0) { throw "7z (xz compress) failed with exit code $LASTEXITCODE" }

    Move-Item -Force "$tempXz" "$tar_file"
    Remove-Item -Force "$tempTar"
    $usedTool = "7z (tar + xz)"
}

& $__w_log "Artifact created with: $usedTool"
& $__w_log "Artifact path: $tar_file"

# copy to ARTIFACT_DIR
if ($env:ARTIFACT_DIR -and $env:ARTIFACT_DIR.Trim().Length -gt 0) {
    $destDir = $env:ARTIFACT_DIR
    if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Force -Path $destDir | Out-Null }
    $destFile = Join-Path $destDir (Split-Path -Leaf $tar_file)
    Copy-Item -Force "$tar_file" "$destFile"
    & $__w_log "Artifact copied to $destFile"
} else {
    & $__w_warn "Artifact left at $tar_file"
}
