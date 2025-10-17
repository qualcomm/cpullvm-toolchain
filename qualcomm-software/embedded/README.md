
# CPULLVM Toolchain for Embedded

This repository contains build scripts and auxiliary material for building Linux and bare-metal LLVM-based toolchains, including:

- clang + llvm
- eld linker
- lld
- libc++abi
- libc++
- compiler-rt for Linux Arm/AArch64
- compiler-rt for bare-metal Arm/AArch64
- musl-embedded

## Targets Built
- Arm
- AArch64

## Enabled Projects
- llvm
- clang
- polly
- lld
- mlir
- eld

## Goal
The CPULLVM Compiler generates code for Arm and AArch64 targets only. It does **not** generate code for other targets supported by the upstream LLVM compiler.

## Components
The CPULLVM toolchain for Embedded relies on the following upstream components:

- [CPULLVM](https://github.com/qualcomm/cpullvm-toolchain)
- [musl-embedded](https://github.com/qualcomm/musl-embedded)
- [eld linker](https://github.com/qualcomm/eld)

## Host Platforms
CPULLVM Toolchain for Embedded is built and tested on
- Linux Ubuntu 22.04 LTS

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

   #### Install libc++ and libc++abi
   These provide C++ standard library support for Clang.
      
    sudo apt-get install libc++-19-dev libc++abi-19-dev

   #### Install cross-compilers for Arm/AArch64
   Required for building Arm and AArch64 targets.
      
    sudo apt-get install gcc-arm-linux-gnueabi
    sudo apt-get install gcc-aarch64-linux-gnu

### Steps to build the CPULLVM compiler toolchain

   #### Clone the cpullvm-toolchain repository  
   
    git clone https://github.com/qualcomm/cpullvm-toolchain
      
   #### Navigate to the scripts directory
   
    cd cpullvm-toolchain/qualcomm-software/embedded/scripts
      
   #### Run the script 
   
    ./build.sh
