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
    --nightly) NIGHTLY="true"; shift ;;
    --clean) CLEAN="true"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) warn "Unknown arg: $1"; usage; exit 1 ;;
  esac
done

# --- Set the Build flags ---
BUILD_MODE="Release"
ASSERTION_MODE="OFF"
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
  MUSL_PINNED_COMMIT="${MUSL_PINNED_COMMIT:-a2bc89ab37e8691e300d7a7dd96bfac4917dc884}"
  pushd "${WORKSPACE}/musl-embedded" >/dev/null
  git checkout "${MUSL_PINNED_COMMIT}"
  popd >/dev/null
else
  log "musl-embedded already present, leaving as-is"
fi

# --- Clone ELD under llvm/tools (if absent) ---
if [[ ! -d "${REPO_ROOT}/llvm/tools/eld/.git" ]]; then
  log "Cloning ELD to ${REPO_ROOT}/llvm/tools/eld"
  git clone "${ELD_REPO_URL}" "${SRC_DIR}/llvm/tools/eld" -b "${ELD_BRANCH}"
  ELD_PINNED_COMMIT="${ELD_PINNED_COMMIT:-58e68232ef5f85b3a53b594975a195445e3ec8da}"
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

# Detect host arch and default triple for native builds on x86_64 or aarch64
HOST_ARCH="$(uname -m)"
DEFAULT_TRIPLE="$(clang -print-target-triple 2>/dev/null || true)"
if [[ -z "${DEFAULT_TRIPLE}" ]]; then
  case "${HOST_ARCH}" in
    aarch64) DEFAULT_TRIPLE="aarch64-linux-gnu" ;;
    x86_64)  DEFAULT_TRIPLE="x86_64-pc-linux-gnu" ;;
    *)       DEFAULT_TRIPLE="${HOST_ARCH}-unknown-linux-gnu" ;;
  esac
fi

cmake -G Ninja -DCMAKE_INSTALL_PREFIX="${INSTALL_DIR}" \
  -DLLVM_TARGETS_TO_BUILD="ARM;AArch64;RISCV;X86" \
  -DELD_TARGETS_TO_BUILD="AArch64;ARM;RISCV" \
  -DLLVM_EXTERNAL_PROJECTS="eld" \
  -DLLVM_EXTERNAL_ELD_SOURCE_DIR="llvm/tools/eld" \
  -DLLVM_DEFAULT_TARGET_TRIPLE="${DEFAULT_TRIPLE}" \
  -DLLVM_BUILD_RUNTIME="OFF" \
  -DLIBCLANG_BUILD_STATIC="ON" -DLLVM_POLLY_LINK_INTO_TOOLS="ON" \
  -DCMAKE_C_COMPILER="clang" -DCMAKE_CXX_COMPILER="clang++" \
  -DCMAKE_BUILD_TYPE="${BUILD_MODE}" \
  -DLLVM_ENABLE_ASSERTIONS:BOOL="${ASSERTION_MODE}" \
  -DLLVM_ENABLE_PROJECTS="llvm;clang;polly;lld;mlir" \
  "${SRC_DIR}/llvm"

log "Building LLVM"
ninja
log "Installing LLVM"
ninja install
popd >/dev/null

if [[ "${SKIP_TESTS}" != "true" ]]; then
  log "Running LLVM tests"
  (cd "${BUILD_DIR}/llvm" && ninja check-llvm check-lld check-polly check-eld check-clang)
else
  warn "Skipping tests"
fi

# --- Compute clang resource dir ---
RESOURCE_DIR="$("${INSTALL_DIR}/bin/clang" -print-resource-dir)"
log "RESOURCE_DIR=${RESOURCE_DIR}"

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

# Linux libraries
log "Install RISC-V Linux libraries"
"${SCRIPT_DIR}"/build_linux_runtimes.sh \
                    --base-build-dir "${BUILD_DIR}" \
                    --base-install-dir "${INSTALL_DIR}" \
                    --resource-dir "${RESOURCE_DIR}" \
                    --llvm-src-dir "${SRC_DIR}" \
                    --musl-emb-src-dir "${MUSL_BUILDDIR}" \
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

# Name the artifact according to host arch (native build)
ARCH_TAG="$(uname -m)"
case "${ARCH_TAG}" in
  x86_64) ARCH_TAG="x86_64" ;;
  aarch64|arm64) ARCH_TAG="AArch64" ;;
  *) ARCH_TAG="${ARCH_TAG}" ;;
esac

archive_name="cpullvm-toolchain-${ELD_BRANCH##*/}-Linux-${ARCH_TAG}-${short_sha}-${suffix}.${COMPRESS_EXT}"

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
