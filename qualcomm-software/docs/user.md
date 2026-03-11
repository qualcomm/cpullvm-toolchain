# Toolchain usage

## MUSL Overlays Installation
CPULLVM includes overlays for [Qualcomm’s musl-embedded](https://github.com/qualcomm/musl-embedded) Arm/AArch64 variants.

To install it, untar the overlay file at the root of the CPULLVM toolchain installation directory.

To invoke the toolchain using musl-embedded as the C library, use the `--config=musl-embedded.cfg` compiler option.

NOTE:
musl Linux variants are used for CPULLVM test infrastructure.
musl-embedded will be deprecated in CPULLVM 23.1.0. Please switch to picolibc.

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
