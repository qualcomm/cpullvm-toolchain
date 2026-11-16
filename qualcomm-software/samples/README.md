# Sample code for CPULLVM

This directory contains sample code which demonstrates how to use CPULLVM to
build embedded programs.

## Directory structure

* `src` - Sample source code, Makefile and description, each sub-directory is a
  separate sample.

## Supported environments

The build scripts support the following environments:
* Linux
* Windows

## Prerequisites

In order to compile the samples you will need the following tools:
* CPULLVM
* GNU Make
* On Windows, a POSIX shell (see below)

On Windows, the Makefiles must be run from a POSIX shell, for example the Git
Bash shell provided by [Git for Windows](https://gitforwindows.org/) or
[MSYS2](https://www.msys2.org/). Alternatively, add the directory containing
``sh.exe`` (e.g. ``C:\Program Files\Git\usr\bin``) to the ``PATH``
environment variable so that GNU Make uses it to run commands.

To run the samples you will need a QEMU emulator to be installed on your
machine. The samples rely on the QEMU System emulator for the selected target
(e.g. ``qemu-system-riscv32``). See the
[Prerequisites](../docs/building.md#prerequisites) section of the build
documentation for the supported QEMU version, and for how to obtain the QEMU
build required by the ``riscv32-xqci`` target.

## Specifying the location of the installed toolchain

The Makefiles of the code samples need the location of the installed CPULLVM
toolchain.

If you are running the samples directly from the installation directory the
Makefiles will determine the correct location automatically.

Otherwise you will need to set the variable ``BIN_PATH`` to point to the
``bin`` directory of the toolchain.

## Compiling, running and debugging the samples

> [!NOTE]
> On Windows, ensure that the directories containing ``make.exe`` and, if you
> plan to run the compiled samples, QEMU are present in the ``PATH`` environment
> variable.

Change to the directory of a specific sample (e.g.
``src/baremetal-semihosting``) and use the following commands to build,
run or debug the sample:
* ``$ make build`` to build the sample.
* ``$ make run`` to run the sample with QEMU emulator.
* ``$ make debug`` to run the sample with QEMU emulator with GDB server
  listening on the default port 1234.

  To debug, attach to QEMU with [LLDB](https://lldb.llvm.org/):

  ```
  $ lldb hello-riscv32.elf
  (lldb) gdb-remote 1234
  ```
* ``$ make clean`` to delete the generated ``.elf`` files.

Use the ``TARGET`` variable with the Makefile to select the target to build and
run the sample for, for example:
```
$ make run TARGET=aarch64
```
The default is ``riscv32``. The supported targets are ``arm``, ``aarch64``,
``riscv32``, ``riscv32-xqci`` and ``riscv64``, see the README of each sample for
details.
