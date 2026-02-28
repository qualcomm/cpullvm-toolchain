# Building from source

## Host platforms

CPULLVM is built and tested on Linux Ubuntu and Windows.

Please refer to the "Host Platforms" section in the [README](/qualcomm-software/README.md) for details.

## Prerequisites

CPULLVM requires the following software to be installed:
* [Software required by LLVM on Linux](https://llvm.org/docs/GettingStarted.html#software) or
   [software required by LLVM on Windows](https://llvm.org/docs/GettingStartedVS.html) depending on your platform of choice
* [Meson](https://mesonbuild.com/Getting-meson.html)
    * [Meson v1.9.0](https://mesonbuild.com/Release-notes-for-1-9-0.html) or later must be
      used to support building picolibc with eld
* [Ninja](https://ninja-build.org/)
* [Git](https://git-scm.com/book/en/v2/Getting-Started-Installing-Git)
* CPULLVM releases use clang and clang-cl to build on Linux and Windows, respectively.
  Alternative toolchains may be used, but are not tested.

Library testing requires:
* [QEMU](https://www.qemu.org/download/)

Testing with QEMU is enabled by default, but can be disabled using the 
`-DENABLE_QEMU_TESTING=OFF` CMake option if testing is not required or QEMU is
not installed.

A relatively recent version of QEMU is required to support the latest RISC-V extensions.
CPULLVM currently builds and tests with QEMU v10.1.3.

The `riscv32ima_xqci_ilp32` library-test variant requires an [Xqci](https://github.com/quic/riscv-unified-db/releases) enabled QEMU build. Clone and build the [QEMU Xqci fork](https://github.com/quic/qemu/tree/feature/xqci), and ensure the binary is available as `qemu-system-riscv32-xqci` in your `PATH`:

```
git clone --branch feature/xqci https://github.com/quic/qemu.git qemu-xqci
cd qemu-xqci
./configure --target-list=riscv32-softmmu
ninja

# CPULLVM expects this executable name
mv "<path-to>/qemu-system-riscv32" "<path-to>/qemu-system-riscv32-xqci"
```

Refer to the [Xqci json](https://github.com/qualcomm/cpullvm-toolchain/blob/qualcomm-software/qualcomm-software/embedded-multilib/json/variants/riscv32ima_xqci_ilp32_nopic.json) file for the flags that need to be passed to QEMU.

## Patching

CPULLVM may contain patches with changes that are pending or unmerged in the upstream projects it uses.
Generally, these patches are automatically applied, except for llvm-project which must be
patched manually. The below command assumes you are in the `cpullvm-toolchain` directory:

```
python3 qualcomm-software/cmake/patch_repo.py --method apply qualcomm-software/patches/llvm-project
```

Other projects (eld, picolibc, etc.) are checked out and patched automatically. If you prefer, you can check
out and patch the repos manually and use those, see [developing.md](./developing.md).

## Building

### Linux
The commands in the sections below assume you are in the `cpullvm-toolchain/qualcomm-software` directory.

The toolchain can be built directly with CMake.

All dependencies are assumed to be present in your `PATH`.

```
# Alternatively, CMAKE_C_COMPILER/CMAKE_CXX_COMPILER may be set directly
export CC=clang
export CXX=clang++
mkdir build
cd build
cmake .. -GNinja -DFETCHCONTENT_QUIET=OFF
ninja llvm-toolchain
```

### Windows
The commands in the sections below assume you are in the `cpullvm-toolchain/qualcomm-software` directory.

The toolchain can be built directly with CMake.

All dependencies are assumed to be present in your `PATH`.

```
mkdir build
cd build
cmake .. -GNinja -DFETCHCONTENT_QUIET=OFF -DCMAKE_C_COMPILER=clang-cl -DCMAKE_CXX_COMPILER=clang-cl
ninja llvm-toolchain
```

### Testing the toolchain

To run all LLVM, eld, and library tests together, the below command may be used:
```
ninja check-all-llvm-toolchain
```

### Installing the toolchain

```
ninja install-llvm-toolchain
```

### Packaging the toolchain

To create a zip or tar.xz file as appropriate for the platform:
```
ninja package-llvm-toolchain
```

### Advanced usage

CPULLVM can be configured and built in a variety of ways, including changing the default libc to use for embedded,
building Linux libraries, and building only a subset of library variants. These (and other) options are
documented in part in [developing.md](./developing.md).
