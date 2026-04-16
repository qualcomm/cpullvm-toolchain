
# Qualcomm LLVM Toolchain Docker Setup and Image

## Overview

This Docker file creates a **build-ready Ubuntu 24.04 environment Docker Image** for working with the **Qualcomm LLVM (cpullvm) toolchain**.  
It installs all required system dependencies, cross-compilers, build tools, and Python utilities, then **clones and sets up the Qualcomm LLVM toolchain from GitHub**.

This image is intended for developers building or experimenting with Qualcomm software using LLVM and related cross-compilation toolchains.
The Image is available on **GitHub Container Registry (GHCR)**:

- **Image:**  
  https://ghcr.io/pranav4330/cpullvmtoolchain22.x:ubuntu24.04
  
---

## Qualcomm LLVM Toolchain

The Docker image automatically clones and initializes the Qualcomm LLVM toolchain.

- **Repository:**  
  https://github.com/qualcomm/cpullvm-toolchain.git

- **Branch:**  
  `release/qualcomm-software/22.x`

These values can be overridden at build time using Docker build arguments.

---

## Base Image

- **Operating System:** Ubuntu 24.04 (Noble Numbat)

---

## Installed Tool Versions

### System Toolchain & Build Tools

- **Clang / Clang++** (Ubuntu 24.04 package version)
- **LLD**
- **GCC ARM Cross Compiler:** `gcc-arm-linux-gnueabi`
- **Make**
- **CMake**
- **Ninja**
- **Git**
- **build-essential**

### C / C++ Libraries

- `zlib1g-dev`
- `libc6-dev-i386`
- **libstdc++**
  - Version 11 (native)
  - Version 12 (native)
  - Version 11 (ARM64 cross)
  - Version 12 (ARM64 cross)

### Python Environment

- **Python:** 3.x (Ubuntu default for 24.04)
- **pip**
- **python3-yaml**
- **Meson:** `1.10.1`

> Meson is installed using `pip` with `--break-system-packages` to ensure compatibility inside the container.
