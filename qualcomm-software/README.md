
# CPULLVM Toolchain

This repository contains build scripts and auxiliary material for building LLVM-based toolchains for embedded,
including:

- clang + llvm
- eld
- lld
- compiler-rt
- picolibc
- musl
- musl-embedded
- libc++/libunwind/libc++abi

For Arm and AArch64 embedded environments, picolibc or musl-embedded may be used as the libc.
For RISC-V, only picolibc may be used.

Libraries intended for use in Linux environments may also be built as part of CPULLVM, though these
are primarily intended for testing and validation. For Arm and AArch64, musl-embedded is used
as the libc for Linux. For RISC-V, musl is used.

## Targets Built
CPULLVM supports generating code for Arm, AArch64, RISC-V, and x86 targets only. It does **not** generate code for other targets supported by the upstream LLVM compiler.

## Enabled Projects
- llvm
- clang
- polly
- lld
- eld

## Components
CPULLVM relies on the following upstream components:

- [LLVM](https://github.com/llvm/llvm-project)
- [picolibc](https://github.com/picolibc/picolibc)
- [musl](https://musl.libc.org/)
- [musl-embedded](https://github.com/qualcomm/musl-embedded)
- [eld](https://github.com/qualcomm/eld)

## Host Platforms
CPULLVM is built and tested on
- Linux Ubuntu 22.04 LTS on x86_64 and AArch64
- Windows Server 2025 on x86_64
- Windows 11 Desktop on Arm64

## Getting started

### Prerequisites for building toolchain 

   #### CPULLVM Build Environment Setup 
   This guide lists required tools and sets up Clang 19 as host compiler for building CPULLVM.  

   #### Install CMake and Ninja
   These are essential build tools for LLVM.
      
    sudo apt install cmake ninja-build

   #### Download LLVM 19 installer script
   Fetch the official LLVM installation script and make it executable.
      
    wget https://apt.llvm.org/llvm.sh
    chmod +x llvm.sh

   #### Install Clang 19 and verify
   Run the script to install Clang 19, then check the version.
      
    sudo ./llvm.sh 19
    clang --version

   #### Set Clang 19 as default compiler
   Use update-alternatives to make Clang 19 the system default.
   
    sudo update-alternatives --install /usr/bin/clang clang /usr/bin/clang-19 100
    sudo update-alternatives --install /usr/bin/clang++ clang++ /usr/bin/clang++-19 100

### Steps to build the CPULLVM compiler toolchain

   #### Clone the cpullvm-toolchain repository  
   
    git clone https://github.com/qualcomm/cpullvm-toolchain
      
   #### Navigate to the scripts directory
   
    cd cpullvm-toolchain/qualcomm-software/scripts
      
   #### Run the script 
   
    ./build.sh
