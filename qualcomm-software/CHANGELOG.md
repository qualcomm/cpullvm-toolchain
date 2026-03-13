# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [Unreleased]

### Added
### Changed
### Deprecated
### Removed
### Fixed
### Security

## [22.1.0]

### Added
- Added 'empty' multilib.yaml at the base of every embedded variant to allow setting alternative sysroot
- Built RISC-V 32- and 64-bit targets embedded variants for ilp32, ilp32f, lp64 and lp64d ABIs, with several combinations of RISC-V standard extensions
(e.g., I, M, A, C, F, D, G, Zb\*, Zc\*, Xqci, Xqccmp) and security features (e.g., SCS)
- Built Arm v7 embedded variants with and without floating-point and Neon support
- Built AArch32 and AArch64 embedded variants with security features enabled (e.g., BTI, PACRET); some AArch64 variants are build with TLS initial-exec mode enabled
- Added custom multilib flags and new multilib checks to build embedded variants with security features (e.g., SCS, BTI, PACRET), PIC mode, TLS and Threading
- Extended support for -fmultilib-flag to Arm, AArch64 and RISC-V targets
- Added openmp as part of Linux runtimes built with musl libc
- Added compiler-rt and profile libraries for Windows on AArch64 and Windows on x86_64 hosts
- Added compiler-rt and libc++ runtimes for Linux built with musl libc for testability
- Added picolibc equivalents of musl-embedded libc variants
- Enabled Arm, AArch64, x86_64 and RISC-V 32- and 64-bit targets in LLVM, ELD and LLDB
- Enabled LLDB without python support but includes Editline, Curses and LZMA support in Linux hosts
- Enabled clang-tools-extra sub-project
- Integrated picolibc and ELD projects
- Built Linux on x86_64 and Linux on AArch64 toolchains against the system's libstdc++
- Added workflows for Windows native build of runtimes
- Added workflow to copy runtimes built on Linux x86_64 to the other toolchain hosts
- Added workflows to build four toolchain hosts: Linux on x86_64, Linux on AArch64, Windows on x86_64, and Windows on AArch64
- Added multi-level CPULLVM project documentation, e.g., README overview, Changelog, Release Notes, build-from-source instructions, developer and toolchain user guides

### Deprecated
- musl-embeded for Arm / AArch64 is deprecated; switch to picolibc
- ELD linker features that are deprecated: `--disable-bss-conversion`, `--enable-bss-mixing` and `--compact` flags; `__attribute__((section(section@address)))` GNU extension; and `.region_table` keyword in linker script

### Changed
- Refactored project to utilize ATfE framework
- Installed Linux libraries in `*-linux-musl[eabi]` to reflect use of musl sysroot

### Removed
- Removed ELD linker symbolic links, e.g., arm-link, aarch64-link and riscv-link
- Removed compiler developer-facing tools from the distributed components
- Removed musl-embedded standlone and uselocks variants
