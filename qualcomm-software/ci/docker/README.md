
# CPU LLVM Toolchain Docker Setup and Image

## Overview

This Docker file provides a **build-ready Ubuntu 24.04 environment Docker Image** for working with the **Qualcomm LLVM (cpullvm) toolchain**.  
it comes preinstalled with common build tools, LLVM tooling, ARM cross-compilers, and Python utilities.

This image is intended for developers building or experimenting with Qualcomm software using LLVM and related cross-compilation toolchains.
The Image is available on **GitHub Container Registry (GHCR)**:

- **Image:**  
  https://ghcr.io/pranav4330/cpullvm-toolchain-dockerimage:ubuntu24.04
  
---

## CPU LLVM Toolchain

The Docker image is for  Qualcomm CPU LLVM toolchain.

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

# Installed Tools & Packages

### Build & Development Tools
- `build-essential`
- `make`
- `cmake`
- `ninja-build`
- `git`

### LLVM Toolchain
- `clang`
- `clang++`
- `lld`

### Cross Compilation
- `gcc-arm-linux-gnueabi`
- `libc6-dev-i386`
- `libstdc++-11-dev`
- `libstdc++-12-dev`
- `libstdc++-11-dev-arm64-cross`
- `libstdc++-12-dev-arm64-cross`

### Python Environment
- `python3`
- `python3-pip`
- `python3-yaml`
- **Meson:** `1.10.1`

> Meson is installed via `pip` using `--break-system-packages` for compatibility inside the container.

### Additional Libraries
- `zlib1g-dev`

---

## Image Configuration

- **Working Directory:** `/workspace`
- **Default Command:** `/bin/bash`
- **Non-interactive APT mode** enabled to support automated builds

---

## Directory Structure

```text
/workspace

