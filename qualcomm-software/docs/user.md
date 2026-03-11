# Toolchain usage

## MUSL Overlays Installation
CPULLVM includes overlays for [Qualcomm’s musl-embedded](https://github.com/qualcomm/musl-embedded) Arm/AArch64 variants.

To install it, untar the overlay file at the root of the CPULLVM toolchain installation directory.

To invoke the toolchain using musl-embedded as the C library, use the `--config=musl-embedded.cfg` compiler option.

> [!WARNING]
> musl Linux variants are used for CPULLVM test infrastructure.
> musl-embedded will be deprecated in CPULLVM 23.1.0. Please switch to picolibc.

## Using ELD
CPULLVM supports and recommends the [ELD linker](https://github.com/qualcomm/eld) for building embedded images.
To do this, add the `-fuse-ld=eld` flag to the compiler driver invocation.

## C++ Support
libc++ and libc++abi runtimes libraries are provided for many embedded variants. Features that are currently not
supported include:

* Multithreading
* Exceptions
* RTTI

If variants with exceptions and RTTI enabled are required, please file an issue.

## Multilib
CPULLVM automatically selects a set of headers and runtimes libraries to use when compiling and linking based on
the set of arguments passed on the command line. A warning will be emitted if no appropriate set of headers/libraries
can be found.

When compiling and linking, you should provide at least the following options on the command line:
* The target triple (ex: `--target=riscv32-unknown-elf`)
* `-march`, `-mabi`, and `-mfpu`, if using non-default options and applicable to your target
* Whether to use position independent code
* Any additional options like sanitizers or `-mbranch-protection`

Additionally, CPULLVM implements custom multilib flags to allow selecting variants that are not otherwise tied
to normal compiler flags. These are specified by `-fmultilib-flag=<flag>`. Currently implemented flags include:
* **`threads`/`nothreads`**: Picolibc only. When `threads` is set, a variant with [`thread-local-storage`](https://github.com/picolibc/picolibc/blob/ce4e736ebef081d13a81a29b6cfb51335f6f890d/doc/build.md#thread-local-storage-options) enabled,
[`single-thread`](https://github.com/picolibc/picolibc/blob/ce4e736ebef081d13a81a29b6cfb51335f6f890d/doc/build.md#locking-options) disabled,
and [`atomic-ungetc`](https://github.com/picolibc/picolibc/blob/ce4e736ebef081d13a81a29b6cfb51335f6f890d/doc/build.md#locking-options) enabled is selected. `nothreads` selects a variant with the inverse. `threads` is default.

To display all available multilibs run clang with the flag `-print-multi-lib` and an appropriate target triple.

To display the directory selected by the multilib system, add the flag `-print-multi-directory` to your clang command line options.

> [!WARNING]
> Using `--sysroot` to select a variant or hardcoding paths to variants should generally not be done.
> Please file an issue if you find that this is needed. Variant names and paths may change at any time
> without notice.
