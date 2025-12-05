
# build.ps1

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

# === Config defaults ===
if (-not $env:CLEAN)          { $env:CLEAN          = "false" }
if (-not $env:JOBS)           { $env:JOBS           = $env:NUMBER_OF_PROCESSORS }
if (-not $env:BUILD_MODE)     { $env:BUILD_MODE     = "Release" }
if (-not $env:ASSERTION_MODE) { $env:ASSERTION_MODE = "OFF" }

# === Constants ===
$ELD_REPO_URL = "https://github.com/qualcomm/eld.git"
$ELD_BRANCH   = "release/21.x"
$ELD_COMMIT   = "25ea417cbb7525b1b02fd5d8cb6ec19dee3b9f13"

$MUSL_EMBEDDED_REPO_URL = "https://github.com/qualcomm/musl-embedded.git"
$MUSL_EMBEDDED_BRANCH   = "main"

Write-Host "[log] SCRIPT_DIR   = $SCRIPT_DIR"
Write-Host "[log] REPO_ROOT    = $REPO_ROOT"
Write-Host "[log] WORKSPACE    = $WORKSPACE"
Write-Host "[log] BUILD_DIR    = $BUILD_DIR"
Write-Host "[log] INSTALL_DIR  = $INSTALL_DIR"
Write-Host "[log] ELD_DIR      = $ELD_DIR"
Write-Host "[log] BUILD_MODE   = $env:BUILD_MODE"
Write-Host "[log] ASSERTIONS   = $env:ASSERTION_MODE"
Write-Host "[log] JOBS         = $env:JOBS"

# === Resolve Visual Studio (vcvarsall.bat) ===
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

# 2) Query the latest VS with VC tools component
$VS_INSTALL = & $vswhere -latest -products * `
    -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
    -property installationPath
if (-not $VS_INSTALL) {
    Write-Error "*** ERROR: Visual Studio installation not found via vswhere ***"
    exit 1
}

# 3) Get vcvarsall.bat and import the environment for x64
$VCVARSALL = Join-Path $VS_INSTALL "VC\Auxiliary\Build\vcvarsall.bat"
if (-not (Test-Path $VCVARSALL)) {
    Write-Error "*** ERROR: vcvarsall.bat not found at $VCVARSALL ***"
    exit 1
}

# Load VS environment into the current PowerShell process (use 'call' to be safe)
cmd /c "call `"$VCVARSALL`" x64 && set" | ForEach-Object {
    if ($_ -match '^(.*?)=(.*)$') {
        [System.Environment]::SetEnvironmentVariable($matches[1], $matches[2], 'Process')
    }
}

# === Tool sanity checks (after VS env is loaded) ===
foreach ($tool in @("git","python","cmake","ninja","clang-cl")) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        Write-Error "*** ERROR: $tool not found on PATH ***"
        exit 1
    }
}

# === Clean ===
if ($env:CLEAN -eq "true") {
    Write-Host "[log] Cleaning $BUILD_DIR and $INSTALL_DIR"
    Remove-Item -Recurse -Force $BUILD_DIR,$INSTALL_DIR -ErrorAction SilentlyContinue
}

# === Prepare workspace ===
Write-Host "[log] Preparing workspace at: $WORKSPACE"
New-Item -ItemType Directory -Force -Path $BUILD_DIR,$INSTALL_DIR | Out-Null

# === Clone repos ===
if (-not (Test-Path "$WORKSPACE\musl-embedded\.git")) {
    Write-Host "[log] Cloning musl-embedded..."
    git clone $MUSL_EMBEDDED_REPO_URL "$WORKSPACE\musl-embedded" -b $MUSL_EMBEDDED_BRANCH
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
Pop-Location

# === Build ===
Write-Host "[log] Configuring CMake..."

# Provide Python to CMake/lit if available
$pythonExe = (Get-Command python -ErrorAction SilentlyContinue).Source
if ($pythonExe) { Write-Host "[log] Using Python: $pythonExe" } else { Write-Host "[warn] Python not found via Get-Command; relying on PATH" }

cmake -G Ninja `
  -S "$SRC_DIR\llvm" `
  -B "$BUILD_DIR\llvm" `
  -DCMAKE_INSTALL_PREFIX="$INSTALL_DIR" `
  -DLLVM_TARGETS_TO_BUILD="ARM;AArch64" `
  -DLLVM_EXTERNAL_PROJECTS="eld" `
  -DLLVM_EXTERNAL_ELD_SOURCE_DIR="$ELD_DIR" `
  -DLLVM_DEFAULT_TARGET_TRIPLE="aarch64-unknown-linux-gnu" `
  -DLIBCLANG_BUILD_STATIC=ON `
  -DLLVM_POLLY_LINK_INTO_TOOLS=ON `
  -DCMAKE_C_COMPILER=clang-cl `
  -DCMAKE_CXX_COMPILER=clang-cl `
  -DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreadedDLL `
  -DCMAKE_BUILD_TYPE="$env:BUILD_MODE" `
  -DLLVM_ENABLE_ASSERTIONS="$env:ASSERTION_MODE" `
  -DLLVM_ENABLE_PROJECTS="llvm;clang;polly;lld;mlir" `
  -DLLVM_INCLUDE_TESTS=ON `
  -DLLVM_INSTALL_UTILS=ON `
  -DLLVM_LIT_ARGS="-v -j $env:JOBS --time-tests" `
  $(if ($pythonExe) { "-DPython3_EXECUTABLE=`"$pythonExe`"" } else { "" })

Write-Host "[log] Building LLVM..."
Push-Location "$BUILD_DIR\llvm"
& ninja
if ($LASTEXITCODE -ne 0) { Write-Error "*** ERROR: ninja build failed (exit=$LASTEXITCODE) ***"; exit $LASTEXITCODE }

& ninja install
if ($LASTEXITCODE -ne 0) { Write-Error "*** ERROR: ninja install failed (exit=$LASTEXITCODE) ***"; exit $LASTEXITCODE }

# === Ensure test utilities exist (ELD/lit depend on these tools) ===
Write-Host "[log] Building test utilities required by lit/ELD..."
& ninja FileCheck not opt llvm-ar llvm-nm llvm-objdump llvm-readelf llvm-dwarfdump `
       llvm-addr2line llvm-strip obj2yaml yaml2obj
if ($LASTEXITCODE -ne 0) { Write-Error "*** ERROR: building test utilities failed (exit=$LASTEXITCODE) ***"; exit $LASTEXITCODE }

# === Prefer our build bin and avoid Git usr\bin shadowing during tests ===
$env:PATH = "$BUILD_DIR\llvm\bin;$env:PATH"
$env:PATH = ($env:PATH -split ';' | Where-Object { $_ -notlike '*\Git\usr\bin*' }) -join ';'

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
} else {
    Write-Host "[log] Build and all tests completed successfully!"
    exit 0
}
