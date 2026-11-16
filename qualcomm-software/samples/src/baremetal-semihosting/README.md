# Bare-metal semihosting sample

This sample shows how to use semihosting with the
[QEMU System emulator](https://www.qemu.org/docs/master/system/index.html).

Use the ``TARGET`` variable to select the target to build and run for:

| ``TARGET``       | QEMU executable            | Emulated machine |
| ---------------- | -------------------------- | ---------------- |
| ``arm``          | ``qemu-system-arm``        | [``mps2-an385``](https://www.qemu.org/docs/master/system/arm/mps2.html) (Cortex-M3) |
| ``aarch64``      | ``qemu-system-aarch64``    | [``virt``](https://www.qemu.org/docs/master/system/arm/virt.html) (Cortex-A57) |
| ``riscv32``      | ``qemu-system-riscv32``    | [``virt``](https://www.qemu.org/docs/master/system/riscv/virt.html) |
| ``riscv32-xqci`` | ``qemu-system-riscv32-xqci`` | [``virt``](https://www.qemu.org/docs/master/system/riscv/virt.html) with the Xqci extensions |
| ``riscv64``      | ``qemu-system-riscv64``    | [``virt``](https://www.qemu.org/docs/master/system/riscv/virt.html) |

For example:
```
$ make run TARGET=aarch64
```
The default is ``riscv32``.

The ``riscv32-xqci`` target requires a QEMU build with support for the Xqci
extensions, installed as ``qemu-system-riscv32-xqci``. See the
[Prerequisites](../../../docs/building.md#prerequisites) section of the build
documentation for how to obtain it.
