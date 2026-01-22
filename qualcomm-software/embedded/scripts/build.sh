#!/usr/bin/env bash

# Copyright (c) Qualcomm Technologies, Inc. and/or its subsidiaries.
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

# A bash script to build cpullvm toolchain
# The script automates cloning, patching, building LLVM, ELD linker and musl-embedded,
# and packaging artifacts for ARM and AArch64 targets.

# Note: Ensure that `ELD_BRANCH` and `MUSL_EMBEDDED_BRANCH` match the current repository branch
# to maintain consistency across all dependencies.

set -euo pipefail

log()  { echo -e "\033[1;34m[log]\033[0m $(date '+%F %T') $*"; }
warn() { echo -e "\033[1;33m[warn]\033[0m $(date '+%F %T') $*"; }
trap 'warn "Script failed at line $LINENO: \"$BASH_COMMAND\" (exit code: $?)"; exit 1' ERR

readonly ELD_REPO_URL="https://github.com/qualcomm/eld.git"
readonly ELD_BRANCH="release/22.x"

readonly MUSL_EMBEDDED_REPO_URL="https://github.com/qualcomm/musl-embedded.git"
readonly MUSL_EMBEDDED_BRANCH="main"

SCRIPT_DIR="$(
  cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" >/dev/null && pwd
)"
REPO_ROOT="$( git -C "${SCRIPT_DIR}" rev-parse --show-toplevel )"
WORKSPACE="${REPO_ROOT}/.."
SRC_DIR="${REPO_ROOT}"
BUILD_DIR="${WORKSPACE}/build"
INSTALL_DIR="${WORKSPACE}/install"
BUILD_DIR_AARCH64="${BUILD_DIR}/aarch64"
INSTALL_DIR_AARCH64="${INSTALL_DIR}/aarch64"
ARTIFACT_DIR=""
SKIP_TESTS="false"
JOBS="${JOBS:-$(nproc)}"
CLEAN="false"
AARCH64_BUILD="false"
NIGHTLY="false"


usage() {
  cat <<'EOF'
Usage:
  build.sh [options]

Options:
  --artifact-dir <path>       Directory to copy final tarball
  --skip-tests                Skip LLVM test steps
  --arm-sysroot <path>        Arm sysroot (default: /usr/arm-linux-gnueabi)
  --aarch64-sysroot <path>    AArch64 sysroot (default: /usr/aarch64-linux-gnu)
  --aarch64-build             AArch64 build
  --nightly                   Nightly build
  --clean                     Delete and recreate build/install dirs

Examples:
  ./build.sh --artifact-dir /tmp/artifacts
EOF
}

# --- Parse args ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    --artifact-dir) ARTIFACT_DIR="$2"; shift 2 ;;
    --skip-tests) SKIP_TESTS="true"; shift ;;
    --arm-sysroot) ARM32_SYSROOT_OPT="$2"; shift 2 ;;
    --aarch64-build) AARCH64_BUILD="true"; shift ;;
    --nightly) NIGHTLY="true"; shift ;;
    --aarch64-sysroot) AARCH64_SYSROOT_OPT="$2"; shift 2 ;;
    --clean) CLEAN="true"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) warn "Unknown arg: $1"; usage; exit 1 ;;
  esac
done

# --- Set the Build flags ---
BUILD_MODE="Release"
ASSERTION_MODE="OFF"
ARM32_LINUX_TRIPLE="arm-linux-gnueabi"
AARCH64_LINUX_TRIPLE="aarch64-linux-gnu"
ARM32_SYSROOT="${ARM32_SYSROOT_OPT:-/usr/arm-linux-gnueabi}"
AARCH64_SYSROOT="${AARCH64_SYSROOT_OPT:-/usr/aarch64-linux-gnu}"
COMPILER_RT_ARM32_LINUX_BUILDDIR="${WORKSPACE}/build/compiler-rt/arm32/linux"
COMPILER_RT_AARCH64_LINUX_BUILDDIR="${WORKSPACE}/build/compiler-rt/aarch64/linux"
COMPILER_RT_ARM32_LINUX_FLAGS="--target=arm-linux-gnueabi -mcpu=cortex-a9 -mfloat-abi=softfp -mfpu=neon"
COMPILER_RT_AARCH64_LINUX_FLAGS="--sysroot=${AARCH64_SYSROOT} --target=aarch64-linux-gnu -mcpu=cortex-a53"
ARM32_BM_TRIPLE="arm-none-eabi"
AARCH64_BM_TRIPLE="aarch64-none-elf"
COMPILER_RT_ARM32_BM_BUILDDIR="${WORKSPACE}/build/compiler-rt/arm32/baremetal"
COMPILER_RT_AARCH64_BM_BUILDDIR="${WORKSPACE}/build/compiler-rt/aarch64/baremetal"
COMPILER_RT_ARM32_BM_FLAGS="--target=arm-none-eabi -mcpu=cortex-a9 -ffunction-sections -fdata-sections -mfloat-abi=softfp -mfpu=neon -nostdlibinc"
COMPILER_RT_AARCH64_BM_FLAGS="--target=aarch64-none-elf -mcpu=cortex-a53 -ffunction-sections -fdata-sections -nostdlibinc"

GCC_ROOT_AARCH64="/usr"

# --- Prepare build/install dirs of aarch64 ---
if [[ "${CLEAN}" == "true" ]]; then
  log "Cleaning ${BUILD_DIR} ${INSTALL_DIR} ${BUILD_DIR_AARCH64} and ${INSTALL_DIR_AARCH64}"
  rm -rf "${BUILD_DIR}" "${INSTALL_DIR}" "${BUILD_DIR_AARCH64}" "${INSTALL_DIR_AARCH64}"
fi

# --- Workspace prep ---
log "Preparing workspace at: ${WORKSPACE}"
mkdir -p "${BUILD_DIR}" "${INSTALL_DIR}"

# --- Clone musl-embedded (if absent) ---
if [[ ! -d "${WORKSPACE}/musl-embedded/.git" ]]; then
  log "Cloning musl-embedded into ${WORKSPACE}/musl-embedded"
  git clone "${MUSL_EMBEDDED_REPO_URL}" "${WORKSPACE}/musl-embedded" -b "${MUSL_EMBEDDED_BRANCH}"
else
  log "musl-embedded already present, leaving as-is"
fi

# --- Clone ELD under llvm/tools (if absent) ---
if [[ ! -d "${REPO_ROOT}/llvm/tools/eld/.git" ]]; then
  log "Cloning ELD to ${REPO_ROOT}/llvm/tools/eld"
  git clone "${ELD_REPO_URL}" "${SRC_DIR}/llvm/tools/eld" -b "${ELD_BRANCH}"
  ELD_PINNED_COMMIT="${ELD_PINNED_COMMIT:-96a7dffdf65a68714c8311111d6a6d54a3a150db}"
  pushd "${SRC_DIR}/llvm/tools/eld" >/dev/null
  git checkout "${ELD_PINNED_COMMIT}"
  popd >/dev/null
else
  log "ELD already present under llvm/tools, leaving as-is"
fi

# --- Apply patches ---
log "Applying patches"
python3 "${SRC_DIR}/qualcomm-software/embedded/tools/patchctl.py" apply -f "${SRC_DIR}/qualcomm-software/embedded/patchsets.yml"

# --- Build LLVM (native) ---
log "Configuring LLVM"
mkdir -p "${BUILD_DIR}/llvm"
pushd "${BUILD_DIR}/llvm" >/dev/null
cmake -G Ninja -DCMAKE_INSTALL_PREFIX="${INSTALL_DIR}" \
  -DLLVM_TARGETS_TO_BUILD="ARM;AArch64;RISCV" \
  -DLLVM_EXTERNAL_PROJECTS="eld" \
  -DLLVM_EXTERNAL_ELD_SOURCE_DIR="llvm/tools/eld" \
  -DLLVM_DEFAULT_TARGET_TRIPLE="aarch64-unknown-linux-gnueabi" \
  -DLLVM_TARGET_ARCH="arm-linux-gnueabi" \
  -DLLVM_BUILD_RUNTIME="OFF" \
  -DLIBCLANG_BUILD_STATIC="ON" -DLLVM_POLLY_LINK_INTO_TOOLS="ON" \
  -DCMAKE_C_COMPILER="clang" -DCMAKE_CXX_COMPILER="clang++" \
  -DCMAKE_CXX_FLAGS="-stdlib=libc++" \
  -DCMAKE_BUILD_TYPE="${BUILD_MODE}" \
  -DLLVM_ENABLE_ASSERTIONS:BOOL="${ASSERTION_MODE}" \
  -DLLVM_ENABLE_PROJECTS="llvm;clang;polly;lld;mlir" \
  "${SRC_DIR}/llvm"

log "Building LLVM"
ninja
log "Installing LLVM"
ninja install
popd >/dev/null

if [[ "${AARCH64_BUILD}" == "true" ]]; then
  log "[Stage 2] Configuring Cross-compiling LLVM for AArch64..."
  mkdir -p "${BUILD_DIR_AARCH64}" "${INSTALL_DIR_AARCH64}"

  pushd "${BUILD_DIR_AARCH64}" >/dev/null
  cmake -G Ninja \
    -S "${SRC_DIR}/llvm" \
    -DCMAKE_INSTALL_PREFIX="${INSTALL_DIR_AARCH64}" \
    -DLLVM_ENABLE_PROJECTS="llvm;clang;polly;lld;mlir" \
    -DLLVM_TARGETS_TO_BUILD="ARM;AArch64;RISCV" \
    -DLLVM_HOST_TRIPLE="aarch64-linux-gnu" \
    -DLLVM_EXTERNAL_PROJECTS="eld" \
    -DLLVM_EXTERNAL_ELD_SOURCE_DIR="${SRC_DIR}/llvm/tools/eld" \
    -DLLVM_DEFAULT_TARGET_TRIPLE="${AARCH64_LINUX_TRIPLE}" \
    -DLLVM_BUILD_RUNTIME="OFF" \
    -DLIBCLANG_BUILD_STATIC="ON" \
    -DLLVM_POLLY_LINK_INTO_TOOLS="ON" \
    -DCMAKE_SYSTEM_NAME="Linux" \
    -DCMAKE_SYSTEM_PROCESSOR="aarch64" \
    -DCMAKE_C_COMPILER="clang" \
    -DCMAKE_CXX_COMPILER="clang++" \
    -DCMAKE_C_FLAGS="--target=aarch64-linux-gnu \
                     --gcc-toolchain=${GCC_ROOT_AARCH64}" \
    -DCMAKE_CXX_FLAGS="--target=aarch64-linux-gnu \
                       --gcc-toolchain=${GCC_ROOT_AARCH64}" \
    -DCMAKE_BUILD_TYPE="${BUILD_MODE}" \
    -DLLVM_TABLEGEN="${INSTALL_DIR}/bin/llvm-tblgen" \
    -DCLANG_TABLEGEN="${INSTALL_DIR}/bin/clang-tblgen" \
    -DLLVM_ENABLE_ASSERTIONS:BOOL="${ASSERTION_MODE}"

  log "Building LLVM and Installing"
  ninja install
  popd >/dev/null
fi

if [[ "${SKIP_TESTS}" != "true" && "${AARCH64_BUILD}" != "true" ]]; then
  log "Running LLVM tests"
  (cd "${BUILD_DIR}/llvm" && ninja check-llvm check-lld check-polly check-eld check-clang)
else
  warn "Skipping tests"
fi

# --- Compute clang resource dir ---
RESOURCE_DIR="$("${INSTALL_DIR}/bin/clang" -print-resource-dir)"
log "RESOURCE_DIR=${RESOURCE_DIR}"

# --- Build compiler-rt for ARM ---
log "Building compiler-rt for ARM"
mkdir -p "${COMPILER_RT_ARM32_LINUX_BUILDDIR}"
pushd "${COMPILER_RT_ARM32_LINUX_BUILDDIR}" >/dev/null
cmake -G Ninja \
  -DCMAKE_INSTALL_PREFIX="${RESOURCE_DIR}" \
  -DCMAKE_TRY_COMPILE_TARGET_TYPE="STATIC_LIBRARY" \
  -DCMAKE_ASM_COMPILER_TARGET="${ARM32_LINUX_TRIPLE}" \
  -DCMAKE_C_COMPILER_TARGET="${ARM32_LINUX_TRIPLE}" \
  -DCMAKE_CXX_COMPILER_TARGET="${ARM32_LINUX_TRIPLE}" \
  -DCMAKE_C_COMPILER="${INSTALL_DIR}/bin/clang" \
  -DCMAKE_CXX_COMPILER="${INSTALL_DIR}/bin/clang++" \
  -DCMAKE_PREFIX_PATH="${INSTALL_DIR}" \
  -DCMAKE_C_FLAGS="${COMPILER_RT_ARM32_LINUX_FLAGS}" \
  -DCMAKE_CXX_FLAGS="${COMPILER_RT_ARM32_LINUX_FLAGS}" \
  -DCMAKE_ASM_FLAGS="${COMPILER_RT_ARM32_LINUX_FLAGS}" \
  -DCMAKE_SYSTEM_NAME="Generic" \
  -DCOMPILER_RT_BUILD_BUILTINS="ON" \
  -DCOMPILER_RT_BUILD_LIBFUZZER="OFF" \
  -DCOMPILER_RT_DEFAULT_TARGET_ONLY="ON" \
  -DCOMPILER_RT_OS_DIR="linux" \
  -DCOMPILER_RT_TEST_TARGET_TRIPLE="${ARM32_LINUX_TRIPLE}" \
  -DCOMPILER_RT_TEST_COMPILER_CFLAGS="${COMPILER_RT_ARM32_LINUX_FLAGS}" \
  -DCOMPILER_RT_TEST_COMPILER="${INSTALL_DIR}/bin/clang" \
  -DCMAKE_BUILD_TYPE="${BUILD_MODE}" \
  -DLLVM_ENABLE_ASSERTIONS:BOOL="${ASSERTION_MODE}" \
  -DCXX_SUPPORTS_UNWINDLIB_NONE_FLAG:BOOL="OFF" \
  "${SRC_DIR}/compiler-rt"
ninja install
popd >/dev/null

# --- Build compiler-rt for ARM baremetal ---
log "Building compiler-rt for ARM baremetal"
mkdir -p "${BUILD_DIR}/compiler-rt/arm32/baremetal"
pushd "${BUILD_DIR}/compiler-rt/arm32/baremetal" >/dev/null
cmake -G Ninja \
    -DCMAKE_INSTALL_PREFIX="${RESOURCE_DIR}" \
    -DCMAKE_TRY_COMPILE_TARGET_TYPE="STATIC_LIBRARY" \
    -DCMAKE_ASM_COMPILER_TARGET="${ARM32_BM_TRIPLE}" \
    -DCMAKE_C_COMPILER_TARGET="${ARM32_BM_TRIPLE}" \
    -DCMAKE_CXX_COMPILER_TARGET="${ARM32_BM_TRIPLE}" \
    -DCMAKE_C_COMPILER="${INSTALL_DIR}/bin/clang" \
    -DCMAKE_CXX_COMPILER="${INSTALL_DIR}/bin/clang++" \
    -DCMAKE_PREFIX_PATH="${INSTALL_DIR}" \
    -DCMAKE_C_FLAGS="${COMPILER_RT_ARM32_BM_FLAGS}" \
    -DCMAKE_CXX_FLAGS="${COMPILER_RT_ARM32_BM_FLAGS}" \
    -DCMAKE_ASM_FLAGS="${COMPILER_RT_ARM32_BM_FLAGS}" \
    -DCMAKE_SYSTEM_NAME="Generic" \
    -DCOMPILER_RT_BAREMETAL_BUILD="ON" \
    -DCOMPILER_RT_BUILD_BUILTINS="ON" \
    -DCOMPILER_RT_BUILD_LIBFUZZER="OFF" \
    -DCOMPILER_RT_BUILD_PROFILE="OFF" \
    -DCOMPILER_RT_BUILD_SANITIZERS="OFF" \
    -DCOMPILER_RT_BUILD_XRAY="OFF" \
    -DCOMPILER_RT_DEFAULT_TARGET_TRIPLE="${ARM32_BM_TRIPLE}" \
    -DCOMPILER_RT_OS_DIR="baremetal" \
    -DCOMPILER_RT_TEST_TARGET_TRIPLE="${ARM32_BM_TRIPLE}" \
    -DCOMPILER_RT_TEST_COMPILER="${INSTALL_DIR}/bin/clang" \
    -DCOMPILER_RT_TEST_COMPILER_CFLAGS="${COMPILER_RT_ARM32_BM_FLAGS}" \
    -DCMAKE_BUILD_TYPE="${BUILD_MODE}" \
    -DLLVM_ENABLE_ASSERTIONS:BOOL="${ASSERTION_MODE}" \
    -DCXX_SUPPORTS_UNWINDLIB_NONE_FLAG:BOOL="OFF" \
    "${SRC_DIR}/compiler-rt"
ninja install
popd >/dev/null

# --- Build compiler-rt for AArch64 ---
log "Building compiler-rt for AArch64"
mkdir -p "${COMPILER_RT_AARCH64_LINUX_BUILDDIR}"
pushd "${COMPILER_RT_AARCH64_LINUX_BUILDDIR}" >/dev/null
cmake -G Ninja \
    -DCMAKE_INSTALL_PREFIX="${RESOURCE_DIR}" \
    -DCMAKE_TRY_COMPILE_TARGET_TYPE="STATIC_LIBRARY" \
    -DCMAKE_C_COMPILER="${INSTALL_DIR}/bin/clang" \
    -DCMAKE_CXX_COMPILER="${INSTALL_DIR}/bin/clang++" \
    -DCMAKE_PREFIX_PATH="${INSTALL_DIR}" \
    -DCMAKE_C_FLAGS="${COMPILER_RT_AARCH64_LINUX_FLAGS}" \
    -DCMAKE_CXX_FLAGS="${COMPILER_RT_AARCH64_LINUX_FLAGS}" \
    -DCMAKE_ASM_FLAGS="${COMPILER_RT_AARCH64_LINUX_FLAGS}" \
    -DCMAKE_SYSTEM_NAME="Generic" \
    -DCOMPILER_RT_DEFAULT_TARGET_TRIPLE="${AARCH64_LINUX_TRIPLE}" \
    -DCOMPILER_RT_OS_DIR="linux" \
    -DCOMPILER_RT_TEST_COMPILER_CFLAGS="${COMPILER_RT_AARCH64_LINUX_FLAGS}" \
    -DCOMPILER_RT_TEST_COMPILER="${INSTALL_DIR}/bin/clang" \
    -DCMAKE_BUILD_TYPE="${BUILD_MODE}" \
    -DLLVM_ENABLE_ASSERTIONS:BOOL="${ASSERTION_MODE}" \
    "${SRC_DIR}/compiler-rt"
ninja install
popd >/dev/null

# --- Build compiler-rt for AArch64 baremetal ---
log "Building compiler-rt for AArch64 baremetal"
mkdir -p "${BUILD_DIR}/compiler-rt/aarch64/baremetal"
pushd "${BUILD_DIR}/compiler-rt/aarch64/baremetal" >/dev/null
cmake -G Ninja \
    -DCMAKE_INSTALL_PREFIX="${RESOURCE_DIR}" \
    -DCMAKE_TRY_COMPILE_TARGET_TYPE="STATIC_LIBRARY" \
    -DCMAKE_C_COMPILER="${INSTALL_DIR}/bin/clang" \
    -DCMAKE_CXX_COMPILER="${INSTALL_DIR}/bin/clang++" \
    -DCMAKE_PREFIX_PATH="${INSTALL_DIR}" \
    -DCMAKE_C_FLAGS="${COMPILER_RT_AARCH64_BM_FLAGS}" \
    -DCMAKE_CXX_FLAGS="${COMPILER_RT_AARCH64_BM_FLAGS}" \
    -DCMAKE_ASM_FLAGS="${COMPILER_RT_AARCH64_BM_FLAGS}" \
    -DCMAKE_SYSTEM_NAME="Generic" \
    -DCOMPILER_RT_BAREMETAL_BUILD="ON" \
    -DCOMPILER_RT_BUILD_BUILTINS="ON" \
    -DCOMPILER_RT_BUILD_LIBFUZZER="OFF" \
    -DCOMPILER_RT_BUILD_PROFILE="OFF" \
    -DCOMPILER_RT_BUILD_SANITIZERS="OFF" \
    -DCOMPILER_RT_BUILD_XRAY="OFF" \
    -DCOMPILER_RT_DEFAULT_TARGET_TRIPLE="${AARCH64_BM_TRIPLE}" \
    -DCOMPILER_RT_OS_DIR="baremetal" \
    -DCOMPILER_RT_TEST_TARGET_TRIPLE="${AARCH64_BM_TRIPLE}" \
    -DCOMPILER_RT_TEST_COMPILER="${INSTALL_DIR}/bin/clang" \
    -DCOMPILER_RT_TEST_COMPILER_CFLAGS="${COMPILER_RT_AARCH64_BM_FLAGS}" \
    -DCMAKE_BUILD_TYPE="${BUILD_MODE}" \
    -DLLVM_ENABLE_ASSERTIONS:BOOL="${ASSERTION_MODE}" \
    "${SRC_DIR}/compiler-rt"
ninja
ninja install
popd >/dev/null

# --- Build musl-embedded ---
export PATH="${INSTALL_DIR}/bin:${PATH}"
log "Building musl-embedded"
MUSL_BUILDDIR="${WORKSPACE}/musl-embedded"
source "${MUSL_BUILDDIR}/qualcomm-software/config/component_list.sh"
for lib in "${musl_components[@]}"; do
  libName="$(echo "${lib}" | awk -F".sh," '{print $1}')"
  dirName="$(echo "${lib}" | awk -F"," '{print $2}')"
  pushd "${MUSL_BUILDDIR}" >/dev/null
  make distclean
  bash -x "${MUSL_BUILDDIR}/qualcomm-software/config/linux/arm/${libName}.sh" --prefix="${INSTALL_DIR}/${dirName}/libc"
  make -j"${JOBS}"
  make install
  popd >/dev/null
done

# --- c++ libs ---
log "Build c++ libs ..."

declare -A Triples
Triples["aarch64-none-elf"]="aarch64-none-elf"
Triples["aarch64-pacret-b-key-bti-none-elf"]="aarch64-none-elf"
Triples["armv7-none-eabi"]="armv7-none-eabi"
declare -A CFLAGS
CFLAGS["aarch64-none-elf"]="-mcpu=cortex-a53 -nostartfiles"
CFLAGS["aarch64-pacret-b-key-bti-none-elf"]="-mcpu=cortex-a53 -nostartfiles -march=armv8.5-a -mbranch-protection=pac-ret+leaf+b-key+bti"
CFLAGS["armv7-none-eabi"]="-mcpu=cortex-a9 -mthumb -specs=nosys.specs"
CFLAGS_RELEASE="-Os -DNDEBUG"
for VARIANT in "aarch64-none-elf" "aarch64-pacret-b-key-bti-none-elf" "armv7-none-eabi"; do
    TRIPLE="${Triples[$VARIANT]}"
    MUSL_INC="${INSTALL_DIR}/${TRIPLE}/libc/include"
    CMAKE_CFLAGS="-target ${TRIPLE} -nostdinc -isystem ${MUSL_INC} -ccc-gcc-name ${TRIPLE}-g++ -fno-unroll-loops -fno-optimize-sibling-calls -ffunction-sections -fdata-sections -fno-exceptions -D_GNU_SOURCE ${CFLAGS[$VARIANT]}"
    mkdir -p "${BUILD_DIR}/${VARIANT}"
    pushd "${BUILD_DIR}/${VARIANT}" >/dev/null
    cmake -G Ninja -DCMAKE_INSTALL_PREFIX="${INSTALL_DIR}/${VARIANT}" -DCMAKE_BUILD_TYPE="Release" -DCMAKE_C_COMPILER="clang" -DCMAKE_CXX_COMPILER="clang++" \
        -DHAVE_LIBCXXABI="True" -DCMAKE_SYSTEM_NAME="Generic" \
        -DCMAKE_C_FLAGS_RELEASE="${CFLAGS_RELEASE}" \
        -DCMAKE_CXX_FLAGS_RELEASE="${CFLAGS_RELEASE}" \
        -DCMAKE_C_FLAGS="${CMAKE_CFLAGS}" \
        -DCMAKE_CXX_FLAGS="${CMAKE_CFLAGS}" \
        -DCMAKE_ASM_FLAGS="${CMAKE_CFLAGS}" \
        -DCMAKE_TRY_COMPILE_TARGET_TYPE="STATIC_LIBRARY" \
        -DLIBCXX_ENABLE_SHARED="False" \
        -DLIBCXX_SHARED_OUTPUT_NAME="c++-shared" \
        -DLIBCXX_ENABLE_EXCEPTIONS="False" \
        -DLIBCXX_HAS_MUSL_LIBC="True" \
        -DLIBCXX_ENABLE_ABI_LINKER_SCRIPT="False" \
        -DLIBCXX_ENABLE_THREADS="False" \
        -DLIBCXX_ENABLE_FILESYSTEM="False" \
        -DLIBCXX_ENABLE_RANDOM_DEVICE="False" \
        -DLIBCXX_ENABLE_LOCALIZATION="False" \
        -DLIBCXX_SUPPORTS_STD_EQ_CXX11_FLAG="ON" \
        -DLIBCXX_SUPPORTS_STD_EQ_CXX14_FLAG="ON" \
        -DLIBCXX_SUPPORTS_STD_EQ_CXX17_FLAG="ON" \
        -DLIBCXX_QUIC_BAREMETAL="ON" \
        -DLIBCXXABI_USE_LLVM_UNWINDER="True" \
        -DLIBCXXABI_BAREMETAL="True" \
        -DLIBCXXABI_ENABLE_SHARED="False" \
        -DLIBCXXABI_SHARED_OUTPUT_NAME="c++abi-shared" \
        -DLIBCXXABI_ENABLE_WERROR="True" \
        -DLIBCXXABI_ENABLE_THREADS="False" \
        -DLIBCXXABI_ENABLE_ASSERTIONS="False" \
        -DLIBCXXABI_ENABLE_EXCEPTIONS="False" \
        -DLIBUNWIND_IS_BAREMETAL="True" \
        -DLIBUNWIND_ENABLE_SHARED="False" \
        -DLIBUNWIND_SHARED_OUTPUT_NAME="unwind-shared" \
        -DUNIX="True" \
        -S "${SRC_DIR}/runtimes" "-DLLVM_ENABLE_RUNTIMES=libcxx;libcxxabi;libunwind"
    ninja
    ninja install
    popd >/dev/null
    log "c++ libs install ..."
done

# Linux libc++ configs
declare -A LINUX_TRIPLES
LINUX_TRIPLES["aarch64-linux-gnu"]="aarch64-linux-gnu"
LINUX_TRIPLES["aarch64-pacret-linux-gnu"]="aarch64-linux-gnu"
LINUX_TRIPLES["aarch64-pacret-bti-linux-gnu"]="aarch64-linux-gnu"
LINUX_TRIPLES["armv7-linux-gnueabi"]="armv7-linux-gnueabi"
declare -A LINUX_CFLAGS
LINUX_CFLAGS["aarch64-linux-gnu"]="-mcpu=cortex-a53"
LINUX_CFLAGS["aarch64-pacret-linux-gnu"]="-mcpu=cortex-a53 -march=armv8.3a -mbranch-protection=pac-ret+leaf"
LINUX_CFLAGS["aarch64-pacret-bti-linux-gnu"]="-mcpu=cortex-a53 -march=armv8.3a -mbranch-protection=pac-ret+leaf+bti"
LINUX_CFLAGS["armv7-linux-gnueabi"]="-mcpu=cortex-a9 -mfloat-abi=softfp -mfpu=neon"
for VARIANT in "${!LINUX_TRIPLES[@]}"; do
    TRIPLE="${LINUX_TRIPLES[${VARIANT}]}"
    SYSROOT="${AARCH64_SYSROOT}"
    if [[ "${TRIPLE}" = "armv7-linux-gnueabi" ]]; then
      SYSROOT="${ARM32_SYSROOT}"
    fi
    MUSL_INC="${INSTALL_DIR}/${TRIPLE}/libc/include"
    CMAKE_CFLAGS="--target=${TRIPLE} -nostdlib -nostdinc -isystem ${MUSL_INC} -isystem ${SYSROOT}/include -ccc-gcc-name ${TRIPLE}-g++ -ffunction-sections -fdata-sections -D_GNU_SOURCE ${LINUX_CFLAGS[${VARIANT}]}"
    mkdir -p "${BUILD_DIR}/${VARIANT}"
    pushd "${BUILD_DIR}/${VARIANT}" >/dev/null
    cmake -G Ninja -S "${SRC_DIR}/runtimes" \
        -DCMAKE_INSTALL_PREFIX="${INSTALL_DIR}/${VARIANT}" \
        -DCMAKE_BUILD_TYPE="Release" \
        -DCMAKE_C_COMPILER="clang" \
        -DCMAKE_CXX_COMPILER="clang++" \
        -DCMAKE_SYSTEM_NAME="Linux" \
        -DCMAKE_C_FLAGS_RELEASE="${CFLAGS_RELEASE}" \
        -DCMAKE_CXX_FLAGS_RELEASE="${CFLAGS_RELEASE}" \
        -DCMAKE_C_FLAGS="${CMAKE_CFLAGS}" \
        -DCMAKE_CXX_FLAGS="${CMAKE_CFLAGS}" \
        -DCMAKE_ASM_FLAGS="${CMAKE_CFLAGS}" \
        -DLIBCXX_ENABLE_SHARED="False" \
        -DLIBCXX_HAS_MUSL_LIBC="True" \
        -DLIBCXX_ENABLE_ABI_LINKER_SCRIPT="False" \
        -DLIBCXXABI_USE_LLVM_UNWINDER="True" \
        -DLIBCXXABI_ENABLE_SHARED="False" \
        -DLIBCXXABI_ENABLE_WERROR="True" \
        -DLIBUNWIND_ENABLE_SHARED="False" \
        -DLLVM_ENABLE_RUNTIMES="libcxx;libcxxabi;libunwind"
    ninja install
    popd >/dev/null
    log "Linux C++ libs install ..."
done

# RISC-V Linux libraries
log "Install RISC-V Linux libraries"
"${SCRIPT_DIR}"/build_riscv_linux_runtimes.sh \
                    --base-build-dir "${BUILD_DIR}" \
                    --base-install-dir "${INSTALL_DIR}" \
                    --resource-dir "${RESOURCE_DIR}" \
                    --llvm-src-dir "${SRC_DIR}" \
                    --download-dir "${WORKSPACE}"

log "Build and installation complete."

# --- Create artifact ---
log "Creating artifact tarball"

short_sha="$(git -C "${SRC_DIR}" rev-parse --short HEAD)"
suffix="$(date +%Y%m%d)"
archive_root="${BUILD_DIR}"
archive_dir="${INSTALL_DIR}"
COMPRESS_EXT="tgz"
COMPRESS_FLAG="-czvf"
archive_name="cpullvm-toolchain-${ELD_BRANCH##*/}-Linux-x86_64-${short_sha}-${suffix}.${COMPRESS_EXT}"

if [[ "${AARCH64_BUILD}" == "true" ]]; then
    log "Preparing AARCH64 build"
    mkdir -p "${INSTALL_DIR_AARCH64}"
    cp -r "${INSTALL_DIR}"/aarch64-* "${INSTALL_DIR}"/armv7-* "${INSTALL_DIR_AARCH64}/"
    cp -r "${INSTALL_DIR}"/lib/clang/[0-9]*/lib "${INSTALL_DIR_AARCH64}/lib/clang/[0-9]*/"
    archive_root="${BUILD_DIR_AARCH64}"
    archive_dir="${INSTALL_DIR_AARCH64}"
    archive_name="cpullvm-toolchain-${ELD_BRANCH##*/}-Linux-AArch64-${short_sha}-${suffix}.${COMPRESS_EXT}"
fi

if [[ "${NIGHTLY}" == "true" ]]; then
    log "Applying NIGHTLY compression settings"
    COMPRESS_EXT="txz"
    COMPRESS_FLAG="-cJvf"
    archive_name="${archive_name%.tgz}_nightly.${COMPRESS_EXT}"
    XZ_THREADS="${JOBS:-$(nproc)}"
    export XZ_OPT="--threads=${XZ_THREADS}"
fi

# Create tarball
tar_file="${archive_root}/${archive_name}"
log "Compressing ${archive_dir} into ${tar_file}"
tar ${COMPRESS_FLAG} "${tar_file}" -C "${archive_dir}" .

# Copy artifact if destination provided
if [[ -n "${ARTIFACT_DIR}" ]]; then
    mkdir -p "${ARTIFACT_DIR}"
    cp "${tar_file}" "${ARTIFACT_DIR}/"
    log "Artifact copied to ${ARTIFACT_DIR}/${archive_name}"
else
    warn "Artifact left at ${tar_file}"
fi
