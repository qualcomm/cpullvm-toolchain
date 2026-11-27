This directory contains LLVM lit tests to be run against CPULLVM
that has been extracted from a package in the same way
that a user of the product would. This is unlike the tests in the test
directory, which run against tools in the build directory.

You can run the tests ensuring that all dependencies are built:

    ninja check-package-llvm-toolchain

Or run the tests with lit directly:

    ${BUILD_DIR}/llvm/bin/llvm-lit -sv ${BUILD_DIR}/packagetest

Files in this directory are never included in the toolchain package. The tests
are split into two directories:
* `sample-tests`: tests that build and run the [samples](../samples), which
  are included in the toolchain package.
* `internal`: tests that use their own source files, for testing that is not
  covered by the samples.

Programs are always built, but are only run if QEMU testing is enabled
(`-DENABLE_QEMU_TESTING=ON`). Each QEMU executable provides its own lit
feature, e.g. `qemu-system-riscv32` provides `qemu-riscv32`. Tests should guard
any step that requires QEMU with `%if qemu-<target> %{ ... %}` or
`REQUIRES: qemu-<target>`. The `qemu-riscv32-xqci` feature is only available if
`qemu-system-riscv32-xqci` is found on the `PATH`.

Tests in `sample-tests` can use `%sample_make` to invoke a sample's Makefile
with the unpacked toolchain, e.g.
`%sample_make -C %samples_dir/src/<sample> TARGET=<target> run`. These
substitutions are defined in [sample-tests/lit.local.cfg](sample-tests/lit.local.cfg)
and are not available to other tests.

All tests can use the following substitutions, where `<target>` is one of the
targets supported by the samples:
* `%{target-<target>}`: compiler options for the target.
* `%{link-semihost}`: link options for a semihosted program.
* `%{qemu-<target>}`: QEMU command line, followed by the image to run.

For example, see [internal/hello.c](internal/hello.c).
