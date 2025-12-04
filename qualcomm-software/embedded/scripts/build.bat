@echo off
setlocal EnableExtensions EnableDelayedExpansion

REM === Derive directories ===
set "SCRIPT_DIR_RAW=%~dp0"
if "%SCRIPT_DIR_RAW:~-1%"=="\" (
    set "SCRIPT_DIR=%SCRIPT_DIR_RAW:~0,-1%"
) else (
    set "SCRIPT_DIR=%SCRIPT_DIR_RAW%"
)

for /f "delims=" %%I in ('git -C "%SCRIPT_DIR%" rev-parse --show-toplevel') do set "REPO_ROOT=%%I" || exit /b 1
for %%I in ("%REPO_ROOT%\..") do set "WORKSPACE=%%~fI"

set "SRC_DIR=%REPO_ROOT%"
set "BUILD_DIR=%WORKSPACE%\build"
set "INSTALL_DIR=%WORKSPACE%\install"
set "ELD_DIR=%REPO_ROOT%\llvm\tools\eld"

REM === Config defaults ===
if not defined CLEAN set "CLEAN=false"
if not defined JOBS  set "JOBS=%NUMBER_OF_PROCESSORS%"
if not defined BUILD_MODE set "BUILD_MODE=Release"
if not defined ASSERTION_MODE set "ASSERTION_MODE=OFF"

REM === Constants ===
set "ELD_REPO_URL=https://github.com/qualcomm/eld.git"
set "ELD_BRANCH=release/21.x"
set "ELD_COMMIT=25ea417cbb7525b1b02fd5d8cb6ec19dee3b9f13"

set "MUSL_EMBEDDED_REPO_URL=https://github.com/qualcomm/musl-embedded.git"
set "MUSL_EMBEDDED_BRANCH=main"

REM === Show derived paths ===
echo SCRIPT_DIR   = %SCRIPT_DIR%
echo REPO_ROOT    = %REPO_ROOT%
echo WORKSPACE    = %WORKSPACE%
echo SRC_DIR      = %SRC_DIR%
echo BUILD_DIR    = %BUILD_DIR%
echo INSTALL_DIR  = %INSTALL_DIR%
echo ELD_DIR      = %ELD_DIR%
echo BUILD_MODE   = %BUILD_MODE%
echo ASSERTIONS   = %ASSERTION_MODE%
echo JOBS         = %JOBS%
echo.

REM === Tool sanity checks ===
where git       >nul 2>nul || (echo *** ERROR: git not found on PATH *** & exit /b 1)
where python    >nul 2>nul || (echo *** ERROR: python not found on PATH *** & exit /b 1)
where cmake     >nul 2>nul || (echo *** ERROR: cmake not found on PATH *** & exit /b 1)
where ninja     >nul 2>nul || (echo *** ERROR: ninja not found on PATH *** & exit /b 1)
where clang-cl  >nul 2>nul || (echo *** ERROR: clang-cl not found on PATH *** & exit /b 1)

REM === Resolve VS (vcvarsall) via vswhere ===
for /f "usebackq tokens=*" %%V in (`"%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set "VS_INSTALL=%%V"
if not defined VS_INSTALL (
    echo *** ERROR: Could not locate Visual Studio via vswhere. Ensure VS Build Tools are installed. ***
    exit /b 1
)
set "VCVARSALL=%VS_INSTALL%\VC\Auxiliary\Build\vcvarsall.bat"
if not exist "%VCVARSALL%" (
    echo *** ERROR: vcvarsall.bat not found at "%VCVARSALL%" ***
    exit /b 1
)

REM === Configure environment ===
call "%VCVARSALL%" x64 || exit /b %errorlevel%

REM === Clean (optional) ===
if /I "%CLEAN%"=="true" (
    echo [precheckin] Cleaning "%BUILD_DIR%" and "%INSTALL_DIR%"
    if exist "%BUILD_DIR%"   rmdir /S /Q "%BUILD_DIR%"   || exit /b %errorlevel%
    if exist "%INSTALL_DIR%" rmdir /S /Q "%INSTALL_DIR%" || exit /b %errorlevel%
)

REM === Prepare workspace ===
echo [precheckin] Preparing workspace at: "%WORKSPACE%"
mkdir "%BUILD_DIR%"   2>nul || exit /b %errorlevel%
mkdir "%INSTALL_DIR%" 2>nul || exit /b %errorlevel%

REM === Clone repos if missing ===
if not exist "%WORKSPACE%\musl-embedded\.git" (
    echo [precheckin] Cloning musl-embedded...
    git clone %MUSL_EMBEDDED_REPO_URL% "%WORKSPACE%\musl-embedded" -b %MUSL_EMBEDDED_BRANCH% || exit /b %errorlevel%
)

if not exist "%ELD_DIR%\.git" (
    echo [precheckin] Cloning ELD...
    git clone %ELD_REPO_URL% "%ELD_DIR%" || exit /b %errorlevel%
    pushd "%ELD_DIR%" || exit /b %errorlevel%
    git checkout %ELD_COMMIT% || (popd & exit /b %errorlevel%)
    popd
)

REM === Apply patches ===
pushd "%SRC_DIR%" || exit /b %errorlevel%
python "qualcomm-software/embedded/tools/patchctl.py" apply -f "qualcomm-software/embedded/patchsets.yml" || (popd & exit /b %errorlevel%)
popd

REM === Build ===
echo [precheckin] Configuring CMake...
cmake -G Ninja ^
  -S "%SRC_DIR%\llvm" ^
  -B "%BUILD_DIR%\llvm" ^
  -DCMAKE_INSTALL_PREFIX="%INSTALL_DIR%" ^
  -DLLVM_TARGETS_TO_BUILD="ARM;AArch64" ^
  -DLLVM_EXTERNAL_PROJECTS="eld" ^
  -DLLVM_EXTERNAL_ELD_SOURCE_DIR="%ELD_DIR%" ^
  -DLLVM_DEFAULT_TARGET_TRIPLE="aarch64-unknown-linux-gnu" ^
  -DLIBCLANG_BUILD_STATIC=ON ^
  -DLLVM_POLLY_LINK_INTO_TOOLS=ON ^
  -DCMAKE_C_COMPILER=clang-cl ^
  -DCMAKE_CXX_COMPILER=clang-cl ^
  -DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreadedDLL ^
  -DCMAKE_BUILD_TYPE="%BUILD_MODE%" ^
  -DLLVM_ENABLE_ASSERTIONS="%ASSERTION_MODE%" ^
  -DLLVM_ENABLE_PROJECTS="llvm;clang;polly;lld;mlir" || exit /b %errorlevel%

echo [precheckin] Building LLVM...
pushd "%BUILD_DIR%\llvm" || exit /b %errorlevel%
ninja                 || exit /b %errorlevel%

echo [precheckin] Installing LLVM...
ninja install         || exit /b %errorlevel%


REM === LIT / check targets ===
echo [precheckin] ===== BEGIN TEST SUITE [%DATE% %TIME%] =====

set "FAIL_COUNT=0"

echo [precheckin] Running LLVM tests...
ninja check-llvm || (
    echo [ERROR] LLVM tests failed!
    set /a FAIL_COUNT+=1
)

echo [precheckin] Running LLD tests...
ninja check-lld || (
    echo [ERROR] LLD tests failed!
    set /a FAIL_COUNT+=1
)

echo [precheckin] Running ELD tests...
ninja check-eld || (
    echo [ERROR] ELD tests failed!
    set /a FAIL_COUNT+=1
)

echo [precheckin] Running Clang tests...
ninja check-clang || (
    echo [ERROR] Clang tests failed!
    set /a FAIL_COUNT+=1
)

echo [precheckin] Running Polly tests...
ninja check-polly || (
    echo [ERROR] Polly tests failed!
    set /a FAIL_COUNT+=1
)

echo [precheckin] ===== END TEST SUITE [%DATE% %TIME%] =====

popd

REM === Summary ===
if %FAIL_COUNT% NEQ 0 (
    echo [precheckin] ? Build completed, but %FAIL_COUNT% test suite(s) failed.
    exit /b 1
) else (
    echo [precheckin] ? Build and all tests completed successfully!
    exit /b 0
)
