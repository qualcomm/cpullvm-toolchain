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

## [23.1.0]

### Added
- Enabled LLVM compiler-rt, picolibc and LLVM libc++ (libcxx, libcxxabi, libunwind) tests for baremetal multilib variants for Arm, AArch64 and RISC-V 32-bit and 64-bit targets
- Enabled Zephyr Twister tests for qemu_riscv32, qemu_riscv32_xip, qemu_riscv64, qemu_cortex_a53, qemu_cortex_m3 and qemu_cortex_a9 configurations
- Added an armv7a vfpv3 hard-float multilib variant required by Zephyr qemu_cortex_a9 test configuration
- Added Clang and LLVM development headers
- Added support for additional picolibc versions as overlays
- Added a picolibc v1.8.12 overlay, packaged separately from the toolchain release
- Added the riscv32imaf_zve32f_zvfh_zba_zbb_ilp32f multilib variant with `-mtune=sifive-x160` for the SiFive X160 core
- Added aligned AArch64 multilib variants
- Added a RISC-V 32-bit multilib variant combining Xqci, Atomics and Zinx extensions and built picolibc with thread support enabled
- Enabled Xqccmt extension in the RISC-V 32-bit Xqci multilib variants
- Enabled frame pointers for RISC-V 32-bit Xqci multilib variants to support field crash-dump collection, with an approximately 2%–3.5% increase in library size
- Added RISC-V 32-bit multilib variants with the Zb* and Zc* sub-extensions enabled
- Added an armv7m hard-float multilib variant with fpv5-d16 FPU support for Cortex-M7, built without position independent code (PIC)
- Added RISC-V control-flow protection (CFI) flags to the multilib configuration
- Enabled Python scripting support in LLDB
- Enabled LLDB dynamic script interpreter support, allowing LLDB to use any Python version at runtime. This feature is currently disabled on Windows because of a known issue

### Changed
- New changes on top of LLVM 23.1.0 release:
  * Added linker script support for Link-Time Optimization (LTO) in the LLVM compiler, LLD and ELD linkers. To enable this feature, pass `-flto -flto-linker-scripts` during compilation and `-flto -Wl,--lto-linker-scripts` to the compiler driver during linking
  * Added options for configuring load latency and branch-misprediction penalties, enabling compiler scheduling-model tuning
  * Added compiler macro fusion support for the Xqci extension
- New changes on top of musl 1.2.5:
  * Added C runtime (CRT) start-up code support for the Zcmt and Xqccmt extensions in musl Linux variants used in testing
- New changes on top of picolibc 1.8.12:
  * Modifications to build configuration and linker script required to enable LLVM libc++ builds
  * Add optimized memset/memcpy/strcpy/strcmp in picolibc multilib variants with Xqci extension enabled
- New changes on top of picolibc 1.8.10:
  * Add optimized memset/memcpy/strcpy/strcmp in picolibc multilib variants with Xqci extension enabled
  * Added C runtime (CRT) start-up code support for the Zcmt and Xqccmt extensions in picolibc multilib variants
- Switched to ELD's release/23.x_lto_linker_scripts branch with linker script support for LTO
- Updated the toolchain’s default picolibc version to align with Zephyr 4.4 and Zephyr SDK 1.0.0 at [01254932](https://github.com/picolibc/picolibc/commit/01254932e8e81085817ed61fd858648584ffe37c) (between 1.8.10 and 1.8.11 versions)
- Enforced a consistent TLS model across picolibc-based library builds to prevent undefined reference errors from unsupported dynamic TLS access
- Fixed armv7a/armv8a multilib triple matching by adding thumbv8a-to-armv8a mappings and correcting multilib variant ordering
- Explicitly require `-munaligned-access` on the compiler line to match Arm and AArch64 multilib variants built with unaligned access support, preventing accidental usage of unaligned variants when `-mno-unaligned-access` is specified
- Added basic multilib selection tests for previously untested variants
- Fixed triple matching for the armv8_soft_neon multilib variant
- Included the documentation folder in the toolchain binary release
- Updated the overlay section of the documentation and added information about picolibc v1.8.1.2
- Clarified documentation on how to run tests for selected subsets of multilib variants
- Clarified references to musl-embedded and musl Linux multilib variants in the user documentation
- Updated the README to reflect the Ubuntu 24.04 upgrade
- Corrected an AArch64 build variant reference in the developer documentation
- Documented the requirement to use QEMU system mode (qemu-system-<arch>) when building/testing multilib variants

### Removed
- musl-embedded for Arm / AArch64 is deprecated and removed from the release; switch to picolibc

## [22.1.3]
### Added
- Added aligned AArch64a, AArch64a pacret+bkey+bti, AArch64a nofp, and AArch64a nofp+pacret+bti library variants
### Changed
- Cherry-picked LLVM commit 23a01e9 - [AArch64] Support 4-byte stack protector with large code model
- Advanced ELD 22.1.0 to commit 92f8615 - [AArch64] Fixes for reloc overflows
- Multilib selection of unaligned Arm/AArch64 library variants now requires unaligned accesses to be enabled as determined by the flags used (or defaults) when building

## [22.1.2]
### Fixed
- Updated the Armv7-A and Armv8-A multilib variants to not require Thumb for matching

## [22.1.1]
### Added
- Added armv7m -mfpu=fpv5-d16 hard float runtime variant
- Added missing basic multilib tests for armv8_soft_neon and armv7m_soft_nofp runtime variants
### Changed
- Cherry-picked LLVM commit 57fcde7 - [AArch64] Make width of stack protector guard value load configurable
- Advanced ELD 22.1.0 to commit 5f28fc2 - Fix ELFObjectWriter::emitRelocation function
### Fixed
- Updated multilib triple for armv8_soft_neon variant to use Clang's normalized target triple
- Forced a consistent TLS model for all library builds using picolibc

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
