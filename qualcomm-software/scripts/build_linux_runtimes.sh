#!/usr/bin/env bash

# Copyright (c) Qualcomm Technologies, Inc. and/or its subsidiaries.
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  build_riscv_linux_runtimes.sh [options]

  !!!! Note that all options must be specified

Options:
  --tools-path <path>         Path to directory to find Clang/LLVM tools
  --base-build-dir <path>     Directory for the build
  --base-install-dir <path>   Directory for the install
  --llvm-src-dir <path>       Directory of the LLVM sources
  --musl-src-dir <path>       Directory of the musl source dir
  --musl-emb-src-dir <path>   Directory of the musl-embedded source dir
  --download-dir <path>       Directory where extra projects are downloaded into
EOF
}

# Given a string containing compile flags (hopefully containing a
# `--target=<triple>`), echo the `<triple>` or exit if not found.
get_target_from_flags() {
  local target_flag_regex="--target=([a-z0-9-]+)"
  [[ "$1" =~ ${target_flag_regex} ]]
  local target="${BASH_REMATCH[1]}"
  if [ -z "${target}" ]; then
    echo "Could not parse target from string ${1}!"
    exit 1
  fi
  echo "${target}"
}

# Given a string containing compile flags (hopefully containing a
# `--target=<triple>`), echo the arch or exit if not found.
get_arch_from_flags() {
  local target=$(get_target_from_flags "$1")
  local arch="$(echo ${target} | cut -d '-' -f1)"
  if [ -z "${arch[0]}" ]; then
    echo "Could not parse arch from string $1!"
    exit 1
  fi
  echo "${arch[0]}"
}

# Given an arch appropriate for clang (from something like
# `--target=<arch>-linux-gnu`), echo the appropriate arch for installing
# kernel headers.
get_kernel_arch() {
  if [[ "$1" == "aarch64" ]]; then
    echo "arm64"
  elif [[ "$1" == "arm" ]]; then
    echo "arm"
  # Seems riscv is the only supported RISC-V ARCH?
  elif [[ "$1" =~ riscv ]]; then
    echo "riscv"
  else
    echo "UNKNOWN_ARCH"
    exit 1
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tools-path) TOOLS_PATH="$2"; shift 2 ;;
    --base-build-dir) BASE_BUILD_DIR="$2"; shift 2 ;;
    --base-install-dir) BASE_INSTALL_DIR="$2"; shift 2;;
    --llvm-src-dir) LLVM_BASE_DIR="$2"; shift 2 ;;
    --musl-src-dir) MUSL_SRC_DIR="$2"; shift 2 ;;
    --musl-emb-src-dir) MUSL_EMB_SRC_DIR="$2"; shift 2 ;;
    --download-dir) DOWNLOAD_DIR="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1"; usage; exit 1 ;;
  esac
done

# Require all flags be passed.
if [ -z "${TOOLS_PATH}" ] ||
   [ -z "${BASE_BUILD_DIR}" ] ||
   [ -z "${BASE_INSTALL_DIR}" ] ||
   [ -z "${LLVM_BASE_DIR}" ] ||
   [ -z "${MUSL_SRC_DIR}" ] ||
   [ -z "${MUSL_EMB_SRC_DIR}" ] ||
   [ -z "${DOWNLOAD_DIR}" ]; then
  echo "All options must be specified"; usage; exit 1
fi

export PATH="${TOOLS_PATH}:${PATH}"

JOBS=$(nproc)

pushd "${DOWNLOAD_DIR}" >/dev/null
# Source kernel headers. This version was chosen as it is the closest, still
# supported, longterm version compared to what we've used historically.
KERNEL_SOURCE_BASE="linux-5.10.247"
KERNEL_SOURCE_BASE_DIR="${DOWNLOAD_DIR}/${KERNEL_SOURCE_BASE}"
if [[ ! -d "${KERNEL_SOURCE_BASE_DIR}" ]]; then
  wget https://cdn.kernel.org/pub/linux/kernel/v5.x/${KERNEL_SOURCE_BASE}.tar.xz
  tar xvf "${KERNEL_SOURCE_BASE}.tar.xz"
  rm "${KERNEL_SOURCE_BASE}.tar.xz"
fi

CLANG_RESOURCE_DIR="$(clang --print-resource-dir)"

# Variants to build and the basic set of compile flags to use for each. There's
# surely more elegant ways of doing this, but this doesn't require any extra
# dependencies and is intended as temporary code.
VARIANTS=(
  "rv32imac_ilp32"
  "rv32imafc_ilp32f"
  "rv32ima_xqci_ilp32"
  "rv64imac_lp64"
  "rv64gc_lp64d"
  "aarch64a"
  "aarch64a_pacret"
  "aarch64a_pacret_bti"
  "aarch64a_pacret_bkey_bti"
  "armv7_softfp_neon"
)

# We place things into folders based on the target here (which maybe isn't
# ideal) so prefer the mostly-normalized form that clang seems to search for
# builtins, default libs, etc.
declare -A VARIANT_BUILD_FLAGS
VARIANT_BUILD_FLAGS["rv32imac_ilp32"]="--target=riscv32-unknown-linux-gnu -march=rv32imac -mabi=ilp32"
VARIANT_BUILD_FLAGS["rv32imafc_ilp32f"]="--target=riscv32-unknown-linux-gnu -march=rv32imafc -mabi=ilp32f"
VARIANT_BUILD_FLAGS["rv32ima_xqci_ilp32"]="--target=riscv32-unknown-linux-gnu -march=rv32ima_zba_zbb_zbs_zca_zcb_zilsd_zclsd_xqcia_xqciac_xqcibi_xqcibm_xqcicli_xqcicm_xqcics_xqcicsr_xqciint_xqciio_xqcilb_xqcili_xqcilia_xqcilo_xqcilsm_xqcisim_xqcisls_xqcisync_xqccmp -mabi=ilp32"
VARIANT_BUILD_FLAGS["rv64imac_lp64"]="--target=riscv64-unknown-linux-gnu -march=rv64imac -mabi=lp64"
VARIANT_BUILD_FLAGS["rv64gc_lp64d"]="--target=riscv64-unknown-linux-gnu -march=rv64gc -mabi=lp64d"
# Note that there's minor devations in the flags here--in the past, only musl
# either was not built with -mcpu=cortex-a53 (aarch64) or was built with
# ex: -mcpu=krait (arm). There was also some odd mixing of armv8.3 vs armv8.5
# across libraries. Intentionally aligning these across libraries for each
# variant.
VARIANT_BUILD_FLAGS["aarch64a"]="--target=aarch64-unknown-linux-gnu -mcpu=cortex-a53"
VARIANT_BUILD_FLAGS["aarch64a_pacret"]="--target=aarch64-unknown-linux-gnu -mcpu=cortex-a53 -march=armv8.3a -mbranch-protection=pac-ret+leaf"
VARIANT_BUILD_FLAGS["aarch64a_pacret_bti"]="--target=aarch64-unknown-linux-gnu -mcpu=cortex-a53 -march=armv8.5a -mbranch-protection=pac-ret+leaf+bti"
VARIANT_BUILD_FLAGS["aarch64a_pacret_bkey_bti"]="--target=aarch64-unknown-linux-gnu -mcpu=cortex-a53 -march=armv8.5a -mbranch-protection=pac-ret+leaf+b-key+bti"
# The full normalized form here seems to be "thumbv7-unknown-linux-gnueabi" but
# that doesn't seem to be what clang searches--use "arm-unknown-linux-gnueabi"
# instead.
VARIANT_BUILD_FLAGS["armv7_softfp_neon"]="--target=arm-unknown-linux-gnueabi -mcpu=cortex-a9 -mfloat-abi=softfp -mfpu=neon"

# Our musl builds in the past have used different "base" sets of compile flags
# for each target arch. Build out that mapping here.
declare -A ARCH_MUSL_CFLAGS
ARCH_MUSL_CFLAGS["riscv32"]="-Os"
ARCH_MUSL_CFLAGS["riscv64"]="-Os"
ARCH_MUSL_CFLAGS["aarch64"]="-mstrict-align -fPIC -fno-rounding-math -O3"
ARCH_MUSL_CFLAGS["arm"]="-mno-unaligned-access -fPIC -fno-rounding-math -O3"

# We also have some new variant-specific configuration going on. Map that out
# as well. Just list all variants--it'll be cleaned up later.
declare -A VARIANT_MUSL_CONFIGS
VARIANT_MUSL_CONFIGS["rv32imac_ilp32"]=""
VARIANT_MUSL_CONFIGS["rv32imafc_ilp32f"]=""
VARIANT_MUSL_CONFIGS["rv32ima_xqci_ilp32"]=""
VARIANT_MUSL_CONFIGS["rv64imac_lp64"]=""
VARIANT_MUSL_CONFIGS["rv64gc_lp64d"]=""
VARIANT_MUSL_CONFIGS["aarch64a"]="--quic-aarch64-optmem"
VARIANT_MUSL_CONFIGS["aarch64a_pacret"]="--quic-aarch64-optmem"
VARIANT_MUSL_CONFIGS["aarch64a_pacret_bti"]="--quic-aarch64-optmem \
                                             --quic-aarch64-mark-bti"
VARIANT_MUSL_CONFIGS["aarch64a_pacret_bkey_bti"]="--quic-aarch64-optmem \
                                                  --quic-aarch64-mark-bti"
VARIANT_MUSL_CONFIGS["armv7_softfp_neon"]=""

for VARIANT in "${VARIANTS[@]}"; do
  echo "Building libraries for ${VARIANT}"
  VARIANT_BASE_BUILD_DIR="${BASE_BUILD_DIR}/${VARIANT}"
  mkdir -p "${VARIANT_BASE_BUILD_DIR}"

  BUILD_FLAGS="${VARIANT_BUILD_FLAGS[$VARIANT]}"

  # Create a temporary sysroot to dump our libraries into--we'll sort out the
  # final install location later.
  VARIANT_TMP_SYSROOT="${VARIANT_BASE_BUILD_DIR}/sysroot"
  mkdir -p "${VARIANT_TMP_SYSROOT}"

  # We have an issue in that we want to build/install/distribute
  # multiple, possibly conficting (different ABIs, etc.) variants. Parts of the
  # subsequent build steps need to be able to find the correct set of libraries
  # for the given variant being built out--basically, we need multilib or to
  # be able to manually point to the correct set of libraries. There's two
  # situations where this causes issues (assuming conflicting variants of the
  # same triple):
  #   1. Basic "can we compile/link a simple thing" tests (roughly) of the form:
  #      `clang --target=<arch>-linux-gnu test.c <extra flags>`
  #   2. Locating the builtins through `--print-libgcc-file-name`. This can
  #      happen in ex: `add_compiler_rt_runtime`.
  # We have lots of options to work around the first case. For the second,
  # `-resource-dir` seems to be the only option. So, setup a temporary
  # resource dir per variant that we can build out and point to using
  # `-resource-dir` in subsequent steps. We'll copy libraries to the appropriate
  # places at the end.
  VARIANT_TMP_RESOURCE_DIR="${VARIANT_TMP_SYSROOT}/resource-dir"
  cp -r "${CLANG_RESOURCE_DIR}" "${VARIANT_TMP_RESOURCE_DIR}"

  VARIANT_TARGET="$(get_target_from_flags ${BUILD_FLAGS})"
  VARIANT_ARCH="$(get_arch_from_flags ${VARIANT_BUILD_FLAGS[$VARIANT]})"
  VARIANT_KERNEL_ARCH="$(get_kernel_arch ${VARIANT_ARCH})"

  # Historically, our RISC-V and Arm/AArch64 builds use slightly different
  # flags, sources, etc. Sort that all out here so we can treat the two
  # consistently below.
  MUSL_DIR="${MUSL_EMB_SRC_DIR}"
  EXTRA_MUSL_CONFIGS="${VARIANT_MUSL_CONFIGS[$VARIANT]}"
  CMAKE_OPT_LEVEL="Release"
  if [[ "${VARIANT_ARCH}" =~ riscv ]]; then
    MUSL_DIR="${MUSL_SRC_DIR}"
    EXTRA_MUSL_CONFIGS="${EXTRA_MUSL_CONFIGS} \
                        --disable-shared"
    CMAKE_OPT_LEVEL="MinSizeRel"
  fi

  # Install kernel headers. They get their own folder so they aren't added to
  # the distribution
  echo "Installing kernel headers for ${VARIANT}"
  KERNEL_BUILD_BASE="${VARIANT_BASE_BUILD_DIR}/kernel"
  make -C "${KERNEL_SOURCE_BASE_DIR}" clean
  make -C "${KERNEL_SOURCE_BASE_DIR}" \
          headers_install \
          INSTALL_HDR_PATH="${KERNEL_BUILD_BASE}" \
          ARCH="${VARIANT_KERNEL_ARCH}"

  # Flags common to all libraries.
  LIB_BUILD_FLAGS="${BUILD_FLAGS} -isystem${KERNEL_BUILD_BASE}/include -resource-dir ${VARIANT_TMP_RESOURCE_DIR} --sysroot=${VARIANT_TMP_SYSROOT}"
  LIB_BUILD_FLAGS="${LIB_BUILD_FLAGS} -ffunction-sections -fdata-sections"

  # Install musl headers
  # This is probably overkill for headers-only (nothing should be compiled)
  # but just use our normal configure step, minus the builtins (as they
  # don't exist yet anyway)
  echo "Installing musl headers for ${VARIANT}"
  VARIANT_MUSL_BUILD_DIR="${VARIANT_BASE_BUILD_DIR}"/musl
  mkdir -p "${VARIANT_MUSL_BUILD_DIR}"
  pushd "${VARIANT_MUSL_BUILD_DIR}" >/dev/null
  "${MUSL_DIR}"/configure \
                            ${EXTRA_MUSL_CONFIGS} \
                            --disable-wrapper \
                            --prefix="${VARIANT_TMP_SYSROOT}" \
                            CROSS_COMPILE="llvm-" \
                            CC="clang --target=${VARIANT_TARGET} -fuse-ld=eld" \
                            CFLAGS="${LIB_BUILD_FLAGS} ${ARCH_MUSL_CFLAGS[$VARIANT_ARCH]}"
  make install-headers
  popd >/dev/null

  # Install *only* the builtins
  echo "Installing builtins for ${VARIANT}"
  BUILTINS_BUILD_DIR="${VARIANT_BASE_BUILD_DIR}/builtins"
  # Setting CMAKE_TRY_COMPILE_TARGET_TYPE as we have no other libraries
  # at the moment so test links won't end well. And, we're only building
  # the builtins.
  cmake -G Ninja \
      -DCMAKE_INSTALL_PREFIX="${VARIANT_TMP_RESOURCE_DIR}" \
      -DCMAKE_SYSROOT="${VARIANT_TMP_SYSROOT}" \
      -DCMAKE_BUILD_TYPE="${CMAKE_OPT_LEVEL}" \
      -DCMAKE_C_COMPILER="clang" \
      -DCMAKE_CXX_COMPILER="clang++" \
      -DCMAKE_TRY_COMPILE_TARGET_TYPE="STATIC_LIBRARY" \
      -DCMAKE_SYSTEM_NAME=Linux \
      -DCOMPILER_RT_DEFAULT_TARGET_ONLY=ON \
      -DCMAKE_ASM_COMPILER_TARGET="${VARIANT_TARGET}" \
      -DCMAKE_C_COMPILER_TARGET="${VARIANT_TARGET}" \
      -DCMAKE_CXX_COMPILER_TARGET="${VARIANT_TARGET}" \
      -DCMAKE_ASM_FLAGS="${LIB_BUILD_FLAGS}" \
      -DCMAKE_C_FLAGS="${LIB_BUILD_FLAGS}" \
      -DCMAKE_CXX_FLAGS="${LIB_BUILD_FLAGS}" \
      -DLLVM_ENABLE_PER_TARGET_RUNTIME_DIR=ON \
      -DCOMPILER_RT_BUILD_BUILTINS=ON \
      -DCOMPILER_RT_BUILD_LIBFUZZER=OFF \
      -DCOMPILER_RT_BUILD_MEMPROF=OFF \
      -DCOMPILER_RT_BUILD_PROFILE=OFF \
      -DCOMPILER_RT_BUILD_CTX_PROFILE=OFF \
      -DCOMPILER_RT_BUILD_SANITIZERS=OFF \
      -DCOMPILER_RT_BUILD_XRAY=OFF \
      -DCOMPILER_RT_BUILD_ORC=OFF \
      -DLLVM_ENABLE_RUNTIMES=compiler-rt \
      -B "${BUILTINS_BUILD_DIR}" \
      -S "${LLVM_BASE_DIR}/runtimes"
  ninja -C "${BUILTINS_BUILD_DIR}" install

  # Install musl, including the libraries this time.
  echo "Installing musl libraries for ${VARIANT}"
  pushd "${VARIANT_MUSL_BUILD_DIR}" >/dev/null
  make distclean
  "${MUSL_DIR}"/configure \
      ${EXTRA_MUSL_CONFIGS} \
      --disable-wrapper \
      --prefix="${VARIANT_TMP_SYSROOT}" \
      CROSS_COMPILE="llvm-" \
      CC="clang --target=${VARIANT_TARGET} -fuse-ld=eld" \
      CFLAGS="${LIB_BUILD_FLAGS} ${ARCH_MUSL_CFLAGS[$VARIANT_ARCH]}" \
      LIBCC="${VARIANT_TMP_RESOURCE_DIR}/lib/${VARIANT_TARGET}/libclang_rt.builtins.a"
  make -j"${JOBS}"
  make install
  popd >/dev/null

  # Install libc++
  echo "Installing libc++ for ${VARIANT}"
  LIBCXX_BUILD_DIR="${VARIANT_BASE_BUILD_DIR}/libcxx"
  LIBCXX_COMPILE_FLAGS="${LIB_BUILD_FLAGS} -D_GNU_SOURCE"
  # Setting CMAKE_TRY_COMPILE_TARGET_TYPE here as we explicitly disable
  # shared libraries and CMake link checks fail since we can't find
  # -lc++.
  cmake -G Ninja \
      -DCMAKE_INSTALL_PREFIX="${VARIANT_TMP_SYSROOT}" \
      -DCMAKE_SYSROOT="${VARIANT_TMP_SYSROOT}" \
      -DCMAKE_BUILD_TYPE="${CMAKE_OPT_LEVEL}" \
      -DCMAKE_C_COMPILER="clang" \
      -DCMAKE_CXX_COMPILER="clang++" \
      -DCMAKE_SYSTEM_NAME="Linux" \
      -DCMAKE_TRY_COMPILE_TARGET_TYPE="STATIC_LIBRARY" \
      -DCMAKE_ASM_COMPILER_TARGET="${VARIANT_TARGET}" \
      -DCMAKE_C_COMPILER_TARGET="${VARIANT_TARGET}" \
      -DCMAKE_CXX_COMPILER_TARGET="${VARIANT_TARGET}" \
      -DCMAKE_ASM_FLAGS="${LIBCXX_COMPILE_FLAGS}" \
      -DCMAKE_C_FLAGS="${LIBCXX_COMPILE_FLAGS}" \
      -DCMAKE_CXX_FLAGS="${LIBCXX_COMPILE_FLAGS}" \
      -DLIBCXX_ENABLE_SHARED="False" \
      -DLIBCXX_HAS_MUSL_LIBC="True" \
      -DLIBCXXABI_USE_LLVM_UNWINDER="True" \
      -DLIBCXXABI_ENABLE_SHARED="False" \
      -DLIBCXXABI_ENABLE_WERROR="True" \
      -DLIBCXX_USE_COMPILER_RT="ON" \
      -DLIBUNWIND_ENABLE_SHARED="False" \
      -DLIBCXXABI_USE_COMPILER_RT="ON" \
      -DLIBCXXABI_USE_LLVM_UNWINDER="ON" \
      -DLIBUNWIND_USE_COMPILER_RT="ON" \
      -DLLVM_ENABLE_RUNTIMES="libcxx;libcxxabi;libunwind" \
      -B "${LIBCXX_BUILD_DIR}" \
      -S "${LLVM_BASE_DIR}/runtimes"
  ninja -C "${LIBCXX_BUILD_DIR}" install

  # Install the rest of compiler-rt now.

  # The goal here is to disable rtsan and gwp_asan:
  #   * For rtsan, our musl-embedded is too old to support the fopencookie
  #     extension, which rtsan relies on.
  #   * For gwp_asan, it requires execinfo.h which is a glibc-specific
  #     header--no musl version ships this (or an equivalent).
  # The actual list corresponds to `ALL_SANITIZERS` in LLVM, minus rtsan and
  # gwp_asan. Just do this for all targets since aarch64 is the only arch that
  # rtsan supports that we care about and gwp_asan seems to be generally broken
  # when building against musl. Might be worth trying to pull the list out of
  # LLVM sources, but for now this should be sufficient.
  SAN_TO_BUILD="asan;dfsan;msan;hwasan;tsan;tysan;safestack;cfi;scudo_standalone;ubsan_minimal;nsan;asan_abi"

  # For Arm specifically, we need to disable anything that touches sanitizer
  # common. Our musl-embedded is old enough that time_t is 32bits and the
  # sanitizer common code thinks we should have a 64bit time_t (see
  # https://github.com/llvm/llvm-project/blob/c94739a5d523883663d237ad9072275ff6c847b1/compiler-rt/lib/sanitizer_common/sanitizer_platform_limits_posix.h#L393-L398)
  # and this disagreement causes issues down the line in ex:
  # https://github.com/llvm/llvm-project/blob/c94739a5d523883663d237ad9072275ff6c847b1/compiler-rt/lib/sanitizer_common/sanitizer_platform_limits_posix.cpp#L1292
  # and we fail the static asserts.
  EXTRA_CRT_CONFIGS=""
  if [[ "${VARIANT_ARCH}" =~ arm ]]; then
    EXTRA_CRT_CONFIGS="-DCOMPILER_RT_BUILD_SANITIZERS=OFF \
                       -DCOMPILER_RT_BUILD_CTX_PROFILE=OFF \
                       -DCOMPILER_RT_BUILD_MEMPROF=OFF"
  fi

  # FIXME: Disable fuzzers as well to work around (seemingly) an upstream bug.
  # `partially_link_libcxx` in fuzzer/CMakeLists.txt has a custom command that
  # invokes the linker, but it just uses the toolchain default. So, we get
  # errors as it picks up the host ld.bfd when linking for riscv64 rather than
  # our just-built eld/lld with no way to override this. Note that re-enabling
  # this also requires messing with some libc++ configuration similar to
  # above.
  # FIXME: Investigate if we can merge this with the libc++ build above as
  # it'd simplify things a bit. Not sure how that works with install dirs
  echo "Installing compiler-rt for ${VARIANT}"

  COMPILER_RT_BUILD_DIR="${VARIANT_BASE_BUILD_DIR}/compiler-rt"
  cmake -G Ninja \
      -DCMAKE_INSTALL_PREFIX="${VARIANT_TMP_RESOURCE_DIR}" \
      -DCMAKE_SYSROOT="${VARIANT_TMP_SYSROOT}" \
      -DCMAKE_BUILD_TYPE="${CMAKE_OPT_LEVEL}" \
      -DCMAKE_C_COMPILER="clang" \
      -DCMAKE_CXX_COMPILER="clang++" \
      -DCMAKE_SYSTEM_NAME="Linux" \
      -DCOMPILER_RT_DEFAULT_TARGET_ONLY=ON \
      -DCMAKE_ASM_COMPILER_TARGET="${VARIANT_TARGET}" \
      -DCMAKE_C_COMPILER_TARGET="${VARIANT_TARGET}" \
      -DCMAKE_CXX_COMPILER_TARGET="${VARIANT_TARGET}" \
      -DCMAKE_ASM_FLAGS="${LIB_BUILD_FLAGS}" \
      -DCMAKE_C_FLAGS="${LIB_BUILD_FLAGS}" \
      -DCMAKE_CXX_FLAGS="${LIB_BUILD_FLAGS}" \
      -DLLVM_ENABLE_PER_TARGET_RUNTIME_DIR=ON \
      -DCOMPILER_RT_CXX_LIBRARY="libcxx" \
      -DCOMPILER_RT_USE_BUILTINS_LIBRARY=ON \
      -DCOMPILER_RT_BUILD_BUILTINS=OFF \
      -DCOMPILER_RT_BUILD_LIBFUZZER=OFF \
      -DCOMPILER_RT_SANITIZERS_TO_BUILD="${SAN_TO_BUILD}" \
      -DCOMPILER_RT_BUILD_ORC=OFF \
      -DCOMPILER_RT_BUILD_XRAY=OFF \
      -DLLVM_ENABLE_RUNTIMES=compiler-rt \
      -DCMAKE_EXE_LINKER_FLAGS="-fuse-ld=eld --rtlib=compiler-rt -stdlib=libc++" \
      -DCMAKE_SHARED_LINKER_FLAGS="-fuse-ld=eld --rtlib=compiler-rt -stdlib=libc++" \
      -DCMAKE_MODULE_LINKER_FLAGS="-fuse-ld=eld --rtlib=compiler-rt -stdlib=libc++" \
      ${EXTRA_CRT_CONFIGS} \
      -B "${COMPILER_RT_BUILD_DIR}" \
      -S "${LLVM_BASE_DIR}/runtimes"
  ninja -C "${COMPILER_RT_BUILD_DIR}" install
done

# Move libraries into the final layout/install. The layout looks something
# like this:
#   - libc/libc++: <install>/<target>/<variant>
#   - compiler-rt: <resource dir>/lib/<target>/<variant>
# This layout isn't ideal, but it is close to what we had in the
# past. When we know what to do with the installed libc++ module files
# and sanitizer binaries we can revisit this.
echo "Copying libraries to their final locations"
for VARIANT in "${VARIANTS[@]}"; do
  VARIANT_TMP_SYSROOT="${BASE_BUILD_DIR}/${VARIANT}/sysroot"
  VARIANT_TARGET="$(get_target_from_flags ${VARIANT_BUILD_FLAGS[$VARIANT]})"
  mkdir -p "${BASE_INSTALL_DIR}/${VARIANT_TARGET}/${VARIANT}"
  cp -r "${VARIANT_TMP_SYSROOT}"/include \
        "${VARIANT_TMP_SYSROOT}"/lib \
        -t "${BASE_INSTALL_DIR}/${VARIANT_TARGET}/${VARIANT}"

  mv "${VARIANT_TMP_SYSROOT}/resource-dir/lib/${VARIANT_TARGET}" \
     "${VARIANT_TMP_SYSROOT}/resource-dir/lib/temp"
  mkdir -p "${VARIANT_TMP_SYSROOT}/resource-dir/lib/${VARIANT_TARGET}"
  mv "${VARIANT_TMP_SYSROOT}/resource-dir/lib/temp" \
     "${VARIANT_TMP_SYSROOT}/resource-dir/lib/${VARIANT_TARGET}/${VARIANT}"
  cp -r "${VARIANT_TMP_SYSROOT}/resource-dir" "${BASE_INSTALL_DIR}"
done
