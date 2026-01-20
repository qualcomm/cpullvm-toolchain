#!/usr/bin/env bash

usage() {
  cat <<'EOF'
Usage:
  build_riscv_linux_runtimes.sh [options]

  !!!! Note that all options must be specified

  !!!! Note that the clang you use must be the clang you are installing
       things into

Options:
  --base-build-dir <path>     Directory for the build
  --base-install-dir <path>   Directory for the install
  --resource-dir <path>       Resource directory for installing runtimes
  --llvm-src-dir <path>       Directory of the LLVM sources
  --download-dir <path>       Directory where extra projects are downloaded into
EOF
}

# Given a string containing compile flags (hopefully containing a
# `--target<triple>`), echo the `<triple>` or exit if not found.
get_target_from_flags() {
  local target_flag_regex="--target=([a-z0-9-]+)"
  [[ "$1" =~ ${target_flag_regex} ]]
  local target="${BASH_REMATCH[1]}"
  if [ -z "${target}" ]; then
    echo "Could not parse --target from string $1!"
    exit 1
  fi
  echo "${target}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --base-build-dir) BASE_BUILD_DIR="$2"; shift 2 ;;
    --base-install-dir) BASE_INSTALL_DIR="$2"; shift 2;;
    --resource-dir) RESOURCE_DIR="$2"; shift 2 ;;
    --llvm-src-dir) LLVM_BASE_DIR="$2"; shift 2 ;;
    --download-dir) DOWNLOAD_DIR="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1"; usage; exit 1 ;;
  esac
done

# Require all flags be passed.
if [ -z "${BASE_BUILD_DIR}" ] ||
   [ -z "${BASE_INSTALL_DIR}" ] ||
   [ -z "${RESOURCE_DIR}" ] ||
   [ -z "${LLVM_BASE_DIR}" ] ||
   [ -z "${DOWNLOAD_DIR}" ]; then
  echo "All options must be specified"; usage; exit 1
fi

# Double check that the resource dirs match. We could remove the flag,
# but I want something that prevents accidentally installing things to
# random other toolchains during testing.
if [[ "$(clang -print-resource-dir)" != "${RESOURCE_DIR}" ]]; then
  echo "clang's resource dir does not match --resource-dir"; usage; exit 1
fi

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

# Source musl for use for RISC-V. In the past, we used different versions
# of musl for Arm and RISC-V with our RISC-V being significantly newer. We're
# only doing Linux support here, so source a matching version (1.2.5) from
# upstream.
MUSL_SOURCE_BASE="musl-1.2.5"
MUSL_SOURCE_BASE_DIR="${DOWNLOAD_DIR}/${MUSL_SOURCE_BASE}"
if [[ ! -d "${MUSL_SOURCE_BASE_DIR}" ]]; then
  wget https://git.musl-libc.org/cgit/musl/snapshot/${MUSL_SOURCE_BASE}.tar.gz
  tar xvf "${MUSL_SOURCE_BASE}.tar.gz"
  rm "${MUSL_SOURCE_BASE}.tar.gz"
fi
popd >/dev/null

# Variants to build and the basic set of compile flags to use for each. There's
# surely more elegant ways of doing this, but this doesn't require any extra
# dependencies and is intended as temporary code.
VARIANTS=("rv32imac_ilp32" "rv64imac_lp64" "rv64gc_lp64d")
declare -A VARIANT_BUILD_FLAGS
VARIANT_BUILD_FLAGS["rv32imac_ilp32"]="--target=riscv32-unknown-linux-gnu -march=rv32imac -mabi=ilp32"
VARIANT_BUILD_FLAGS["rv64imac_lp64"]="--target=riscv64-unknown-linux-gnu -march=rv64imac -mabi=lp64"
VARIANT_BUILD_FLAGS["rv64gc_lp64d"]="--target=riscv64-unknown-linux-gnu -march=rv64gc -mabi=lp64d"

for VARIANT in "${VARIANTS[@]}"; do
  echo "Building libraries for ${VARIANT}"
  VARIANT_BASE_BUILD_DIR="${BASE_BUILD_DIR}/${VARIANT}"
  mkdir -p "${VARIANT_BASE_BUILD_DIR}"

  BUILD_FLAGS="${VARIANT_BUILD_FLAGS[$VARIANT]}"

  # Create a temporary sysroot to dump our libraries into--we'll sort out the
  # final install location later.
  VARIANT_TMP_SYSROOT="${VARIANT_BASE_BUILD_DIR}/tmp_sysroot"
  mkdir -p "${VARIANT_TMP_SYSROOT}"

  # Install kernel headers. They get their own folder so they aren't added to
  # the distribution
  echo "Installing kernel headers for ${VARIANT}"
  KERNEL_BUILD_BASE="${VARIANT_BASE_BUILD_DIR}/kernel"
  make -C "${KERNEL_SOURCE_BASE_DIR}" clean
  # Seems riscv is the only supported RISC-V ARCH?
  make -C "${KERNEL_SOURCE_BASE_DIR}" \
          headers_install \
          INSTALL_HDR_PATH="${KERNEL_BUILD_BASE}" \
          ARCH=riscv

  # Flags common to all libraries.
  LIB_BUILD_FLAGS="${BUILD_FLAGS} -isystem${KERNEL_BUILD_BASE}/include --sysroot=${VARIANT_TMP_SYSROOT}"
  LIB_BUILD_FLAGS="${LIB_BUILD_FLAGS} -ffunction-sections -fdata-sections"

  # Parse out the --target flag rather than map it above
  VARIANT_TARGET="$(get_target_from_flags ${BUILD_FLAGS})"

  # Install musl headers
  # This is probably overkill for headers-only (nothing should be compiled)
  # but just use our normal configure step.
  echo "Installing musl headers for ${VARIANT}"
  VARIANT_MUSL_BUILD_DIR="${VARIANT_BASE_BUILD_DIR}"/musl
  mkdir -p "${VARIANT_MUSL_BUILD_DIR}"
  pushd "${VARIANT_MUSL_BUILD_DIR}" >/dev/null
  "${MUSL_SOURCE_BASE_DIR}"/configure \
                            --disable-shared \
                            --disable-wrapper \
                            --prefix="${VARIANT_TMP_SYSROOT}" \
                            CROSS_COMPILE="llvm-" \
                            CC="clang --target=${VARIANT_TARGET} -fuse-ld=eld" \
                            CFLAGS="${LIB_BUILD_FLAGS} -Os"
  make install-headers
  popd >/dev/null

  # Install *only* the builtins
  echo "Installing builtins for ${VARIANT}"
  BUILTINS_BUILD_DIR="${VARIANT_BASE_BUILD_DIR}/builtins"
  # Setting CMAKE_TRY_COMPILE_TARGET_TYPE as we have no other libraries
  # at the moment so test links won't end well. And, we're only building
  # the builtins.
  cmake -G Ninja \
      -DCMAKE_INSTALL_PREFIX="${RESOURCE_DIR}" \
      -DCMAKE_SYSROOT="${TMP_RESOURCE_DIR}" \
      -DCMAKE_BUILD_TYPE="MinSizeRel" \
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

  # **** Nasty hack ****
  # We have an issue in that we want to build/install/distribute
  # multiple, possibly conficting (different ABIs, etc.) variants. Parts of the
  # subsequent build steps need to be able to find the correct set of libraries
  # for the given variant being built out--basically, we need multilib or to
  # be able to manually point to the correct set of libraries. AFAIK, there's
  # no great way of handling this for Linux currently where builtins are
  # concerned. There's two situations where this comes up:
  #   1. Basic "can we compile/link a simple thing" tests (roughly) of the form:
  #      `clang --target=<arch>-linux-gnu test.c <extra flags>`
  #   2. Locating the builtins through `--print-libgcc-file-name`. This can
  #      happen in ex: `add_compiler_rt_runtime`.
  # We have lots of options to work around the first case. In the second case, I
  # can't find any way to actually influence where clang looks for compiler-rt
  # (without source changes) in a way that helps us--it always looks into
  # some "fixed" path that, at best, is common for variants of the same triple.
  #
  # To work around this, we install the builtins in one of the expected places
  # to let the various compile/link/--print-libgcc-file-name tests work
  # correctly. Make an additional copy in our temporary sysroot though and at
  # the end of building this variant, we'll delete the installed folder for
  # the next variant. Once all variants are built, we can go through and install
  # everything in the correct location again.
  #
  # UPDATE/FIXME: I've since learned `--resource-dir <dir>` is a thing--I think
  # this improves the situation a bit in that we can set up per-variant
  # resource dirs for building rather than share the single "real" one in clang.
  # I *think* that should at least allow us to relax the sequential ordering
  # between same-target variants. This script is throwaway code so I'm not
  # going to make this change here--I'll address this post refactor.
  mkdir -p "${VARIANT_TMP_SYSROOT}/lib"
  cp -r "${RESOURCE_DIR}/lib/${VARIANT_TARGET}" "${VARIANT_TMP_SYSROOT}/lib"

  # Install musl, including the libraries this time.
  echo "Installing musl libraries for ${VARIANT}"
  pushd "${VARIANT_MUSL_BUILD_DIR}" >/dev/null
  # TODO: we should probably standardize which linker we're using (lld vs eld)
  # but that can wait--this matches what we've done in the past.
  "${MUSL_SOURCE_BASE_DIR}"/configure \
                            --disable-shared \
                            --disable-wrapper \
                            --prefix="${VARIANT_TMP_SYSROOT}" \
                            CROSS_COMPILE="llvm-" \
                            CC="clang --target=${VARIANT_TARGET} -fuse-ld=eld" \
                            CFLAGS="${LIB_BUILD_FLAGS} -Os"
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
      -DCMAKE_SYSROOT="${TMP_RESOURCE_DIR}" \
      -DCMAKE_BUILD_TYPE="MinSizeRel" \
      -DCMAKE_C_COMPILER="clang" \
      -DCMAKE_CXX_COMPILER="clang++" \
      -DCMAKE_SYSTEM_NAME="Linux" \
      -DCMAKE_TRY_COMPILE_TARGET_TYPE="STATIC_LIBRARY" \
      -DCMAKE_ASM_COMPILER_TARGET="${TARGET_TRIPLE}" \
      -DCMAKE_C_COMPILER_TARGET="${TARGET_TRIPLE}" \
      -DCMAKE_CXX_COMPILER_TARGET="${TARGET_TRIPLE}" \
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
  # As a continuation of the hack above, just install these into the temp
  # sysroot and we'll move them later.
  # FIXME: Disable fuzzers as well to work around (I think) an upstream bug.
  # `partially_link_libcxx` in fuzzer/CMakeLists.txt has a custom command that
  # invokes the linker, but it just uses the toolchain default. So, we get
  # errors as it picks up the host ld.bfd when linking for riscv64 rather than
  # our just-built lld with no way to override this. Note that re-enabling
  # this also requires messing with some libc++ configuration similar to
  # above.
  # TODO: Investigate if we can merge this with the libc++ build above as
  # it'd simplify things a bit. Not sure how that works with install dirs
  echo "Installing compiler-rt for ${VARIANT}"
  COMPILER_RT_BUILD_DIR="${VARIANT_BASE_BUILD_DIR}/compiler-rt"
  cmake -G Ninja \
      -DCMAKE_INSTALL_PREFIX="${RESOURCE_DIR}" \
      -DCMAKE_SYSROOT="${TMP_RESOURCE_DIR}" \
      -DCMAKE_BUILD_TYPE="MinSizeRel" \
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
      -DCOMPILER_RT_BUILD_XRAY=OFF \
      -DLLVM_ENABLE_RUNTIMES=compiler-rt \
      -DCMAKE_EXE_LINKER_FLAGS="-fuse-ld=lld --rtlib=compiler-rt -stdlib=libc++" \
      -DCMAKE_SHARED_LINKER_FLAGS="-fuse-ld=lld --rtlib=compiler-rt -stdlib=libc++" \
      -DCMAKE_MODULE_LINKER_FLAGS="-fuse-ld=lld --rtlib=compiler-rt -stdlib=libc++" \
      -B "${COMPILER_RT_BUILD_DIR}" \
      -S "${LLVM_BASE_DIR}/runtimes"
  ninja -C "${COMPILER_RT_BUILD_DIR}" install

  # As a continuation of the hack above, clean up the resource dir for the
  # next variant.
  rm -rf "${RESOURCE_DIR}/lib/${VARIANT_TARGET}"
done

# Move libraries into the final layout/install. The layout looks something
# like this:
#   - libc/libc++: <install>/<target>/<variant>
#   - compiler-rt: <resource dir>/lib/<target>/<variant>
# I don't think this layout is ideal, but it is close to what we had in the
# past. When we know what to do with the installed libc++ module files
# we can revisit this.
echo "Copying libraries to their final locations"
for VARIANT in "${VARIANTS[@]}"; do
  VARIANT_TMP_SYSROOT="${BASE_BUILD_DIR}/${VARIANT}/tmp_sysroot"
  VARIANT_TARGET="$(get_target_from_flags ${VARIANT_BUILD_FLAGS[$VARIANT]})"
  VARIANT_CRT_DEST="${RESOURCE_DIR}/lib/${VARIANT_TARGET}"
  mkdir -p "${VARIANT_CRT_DEST}"
  # Just move this so it isn't duplicated--we can fix this later.
  mv "${VARIANT_TMP_SYSROOT}/lib/${VARIANT_TARGET}" "${VARIANT_CRT_DEST}/${VARIANT}"
  mkdir -p "${BASE_INSTALL_DIR}/${VARIANT_TARGET}/${VARIANT}"
  cp -r "${VARIANT_TMP_SYSROOT}"/* "${BASE_INSTALL_DIR}/${VARIANT_TARGET}/${VARIANT}"
done
