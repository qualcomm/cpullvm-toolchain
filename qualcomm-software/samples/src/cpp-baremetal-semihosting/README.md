# Bare-metal semihosting C++ sample

This sample shows how to use semihosting with the
[QEMU System emulator](https://www.qemu.org/docs/master/system/index.html)
to build C++ programs.

Use the ``TARGET`` variable to select the target to build and run for, as
described in the [baremetal-semihosting](../baremetal-semihosting/README.md)
sample.

The C++ libraries are built without support for exceptions and RTTI for most
targets, so the sample is compiled with ``-fno-exceptions -fno-rtti``.
