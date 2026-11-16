This directory contains LLVM lit tests to be run against CPULLVM
that has been extracted from a package in the same way
that a user of the product would. This is unlike the tests in the test
directory, which run against tools in the build directory.

You can run the tests ensuring that all dependencies are built:

    ninja check-package-llvm-toolchain

Or run the tests with lit directly:

    ${BUILD_DIR}/llvm/bin/llvm-lit -sv ${BUILD_DIR}/packagetest

Tests can either build and run one of the [samples](../samples), which are
included in the toolchain package, or use their own source files kept in this
directory (e.g. in an `Inputs` sub-directory). Files in this directory are
never included in the toolchain package.

Samples are always built, but are only run if QEMU testing is enabled
(`-DENABLE_QEMU_TESTING=ON`). Each QEMU executable provides its own lit
feature, e.g. `qemu-system-riscv32` provides `qemu-riscv32`. Tests should guard
any step that requires QEMU with `%if qemu-<target> %{ ... %}` or
`REQUIRES: qemu-<target>`. The `qemu-riscv32-xqci` feature is only available if
`qemu-system-riscv32-xqci` is found on the `PATH`.

Use `%sample_make` to invoke a sample's Makefile with the unpacked toolchain,
e.g. `%sample_make -C %samples_dir/src/<sample> TARGET=<target> run`.

Tests that do not use the samples can use the following substitutions, where
`<target>` is one of the targets supported by the samples:
* `%{target-<target>}`: compiler options for the target.
* `%{link-semihost}`: link options for a semihosted program.
* `%{qemu-<target>}`: QEMU command line, followed by the image to run.

For example, see [hello.c](hello.c).
