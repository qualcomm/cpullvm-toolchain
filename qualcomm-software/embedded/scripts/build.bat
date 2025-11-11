@echo off
setlocal EnableExtensions EnableDelayedExpansion

REM =========================
REM :: Main Entry
REM =========================
goto :main

REM =========================
REM :: Subroutines
REM =========================
:check_status
if %errorlevel% neq 0 (
    echo.
    echo *** ERROR: %~1 ***
    echo *** Previous command failed with exit code %errorlevel% ***
    exit /b %errorlevel%
)
goto :eof

REM =========================
REM :: Main
REM =========================
:main
REM === Derive directories ===
set "SCRIPT_DIR_RAW=%~dp0"
if "%SCRIPT_DIR_RAW:~-1%"=="\" (
    set "SCRIPT_DIR=%SCRIPT_DIR_RAW:~0,-1%"
) else (
    set "SCRIPT_DIR=%SCRIPT_DIR_RAW%"
)

for /f "delims=" %%I in ('git -C "%SCRIPT_DIR%" rev-parse --show-toplevel') do set "REPO_ROOT=%%I"
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
set "ELD_BRANCH=main"
set "ELD_COMMIT=65ea860802c41ef5c0becff9750a350495de27b0"

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
where git    >nul 2>nul || (echo *** ERROR: git not found on PATH *** & exit /b 1)
where python >nul 2>nul || (echo *** ERROR: python not found on PATH *** & exit /b 1)
where cmake  >nul 2>nul || (echo *** ERROR: cmake not found on PATH *** & exit /b 1)
where ninja  >nul 2>nul || (echo *** ERROR: ninja not found on PATH *** & exit /b 1)
where clang-cl >nul 2>nul || (echo *** ERROR: clang-cl not found on PATH *** & exit /b 1)

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
call "%VCVARSALL%" x64
call :check_status "vcvarsall failed"

REM === Clean (optional) ===
if /I "%CLEAN%"=="true" (
    echo [precheckin] Cleaning "%BUILD_DIR%" and "%INSTALL_DIR%"
    if exist "%BUILD_DIR%"   rmdir /S /Q "%BUILD_DIR%"
    if exist "%INSTALL_DIR%" rmdir /S /Q "%INSTALL_DIR%"
)

REM === Prepare workspace ===
echo [precheckin] Preparing workspace at: "%WORKSPACE%"
mkdir "%BUILD_DIR%"   2>nul
mkdir "%INSTALL_DIR%" 2>nul

REM === Clone repos if missing ===
if not exist "%REPO_ROOT%\musl-embedded\.git" (
    echo [precheckin] Cloning musl-embedded...
    git clone %MUSL_EMBEDDED_REPO_URL% "%REPO_ROOT%\musl-embedded" -b %MUSL_EMBEDDED_BRANCH%
    call :check_status "clone musl-embedded failed"
)

if not exist "%ELD_DIR%\.git" (
    echo [precheckin] Cloning ELD...
    git clone %ELD_REPO_URL% "%ELD_DIR%"
    cd "%ELD_DIR%"
    git fetch --all
    git checkout %ELD_COMMIT%
    call :check_status "clone ELD failed"
)

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
  -DLLVM_ENABLE_PROJECTS="llvm;clang;polly;lld;mlir"
call :check_status "cmake configure failed"

echo [precheckin] Building LLVM...
pushd "%BUILD_DIR%\llvm"
ninja -j %JOBS%
call :check_status "ninja build failed"

echo [precheckin] Installing LLVM...
ninja install
call :check_status "ninja install failed"

REM === LIT / check targets ===
ninja check-llvm
call :check_status "check-llvm failed"
 
ninja check-lld
call :check_status "check-lld failed"

ninja check-eld
call :check_status "check-eld failed"
 
ninja check-clang
call :check_status "check-clang failed"
 
ninja check-polly
call :check_status "check-polly failed"
popd

echo [precheckin] Build completed successfully!

exit /b 0