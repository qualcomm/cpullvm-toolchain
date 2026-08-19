# Toolchain usage

## Overlay Installation and Usage
CPULLVM distributes additional overlay packages that allow for alternative sets of libraries (using different C library
implementations or versions, for example) to be optionally downloaded, installed, and used.

To install the overlay, untar or unzip the overlay file at the root of an existing CPULLVM toolchain installation directory.

To invoke the toolchain using the desired overlay, pass either of the below options to all compile and link
commands:
* `--config=<overlay name>.cfg` (ex: `--config=picolibc-v1812.cfg`)
* `--sysroot=<path to toolchain root>/lib/clang-runtimes/<overlay name>`
(ex: `--sysroot=<path to>/lib/clang-runtimes/picolibc-v1812`)

Using `--config=<overlay name>.cfg` should be preferred.

However, some build systems (e.g. Zephyr) provide better support for specifying a sysroot directly, so `--sysroot`
may still be a useful alternative.

> [!WARNING]
> The toolchain-internal paths to overlays (ex: `lib/clang-runtimes`) may change between releases without warning.

The default set of libraries (currently picolibc v1.8.10) are still available and will be  used if the `--config` and `--sysroot`
options above are omitted.

The following overlays are supported:
* `picolibc-v1812`: picolibc [v1.8.12](https://github.com/picolibc/picolibc/releases/tag/1.8.12) supporting the same
variants as CPULLVM's default picolibc library set.

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
CPULLVM automatically selects a set of headers and runtime libraries to use when compiling and linking based on
the set of arguments passed on the command line. A warning will be emitted if no appropriate set of headers/libraries
can be found.

When compiling and linking, you should provide at least the following options on the command line:
* The target triple (ex: `--target=riscv32-unknown-elf`)
* `-march`, `-mabi`, and `-mfpu`, if using non-default options and applicable to your target
* Whether to use position independent code
* Any additional options like sanitizers or `-mbranch-protection`

Additionally, CPULLVM implements custom multilib flags to allow selecting variants that are not otherwise tied
to normal compiler flags. These are specified by `-fmultilib-flag=<flag>`. Currently implemented flags include:
* **`threads`/`no-threads`**: Picolibc only. When `threads` is set, a variant with [`thread-local-storage`](https://github.com/picolibc/picolibc/blob/ce4e736ebef081d13a81a29b6cfb51335f6f890d/doc/build.md#thread-local-storage-options) enabled,
[`single-thread`](https://github.com/picolibc/picolibc/blob/ce4e736ebef081d13a81a29b6cfb51335f6f890d/doc/build.md#locking-options) disabled,
and [`atomic-ungetc`](https://github.com/picolibc/picolibc/blob/ce4e736ebef081d13a81a29b6cfb51335f6f890d/doc/build.md#locking-options) enabled is selected. `no-threads` selects a variant with the inverse. `threads` is default.

To display all available multilibs run clang with the flag `-print-multi-lib` and an appropriate target triple.

To display the directory selected by the multilib system, add the flag `-print-multi-directory` to your clang command line options.

> [!WARNING]
> Using `--sysroot` to select a variant or hardcoding paths to variants should generally not be done.
> Please file an issue if you find that this is needed.
>
> Variant names and paths may change at any time without notice.

## Picolibc

Picolibc offers [comprehensive documentation](https://github.com/picolibc/picolibc/tree/main/doc) that users are encouraged to review thoroughly.

In particular, refer to [Using Picolibc in Embedded Systems](https://github.com/picolibc/picolibc/blob/main/doc/using.md)
for the details of how picolibc handles initialization. Custom linker script changes might be required to
[link picolibc in embedded applications](https://github.com/picolibc/picolibc/blob/main/doc/linking.md#linking-picolibc-applications).

See [Picolibc and Operating Systems](https://github.com/picolibc/picolibc/blob/main/doc/os.md)
for the details on redirecting `stdin`, `stdout` and `stderr`.

## LLDB
The LLDB build for Linux hosts was configured with Editline, Curses, and LZMA.
To ensure LLDB runs correctly, users must verify that compatible versions of these libraries are installed on their systems.
For more details, refer to [LLDB's Optional Dependencies](https://lldb.llvm.org/resources/build.html#optional-dependencies).
