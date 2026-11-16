#
# Copyright (c) 2020-2025, Arm Limited and affiliates.
# Part of the Arm Toolchain project, under the Apache License v2.0 with LLVM Exceptions.
# See https://llvm.org/LICENSE.txt for license information.
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#
# Changes from Qualcomm Technologies, Inc. are provided under the following license:
# Copyright (c) Qualcomm Technologies, Inc. and/or its subsidiaries.
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#

include ../../Makefile.conf

ELF=hello-$(TARGET).elf

build: $(ELF)

# The C library's default memory map for the selected target already matches
# the emulated machine's memory, so its linker script can be used as-is. Real
# projects should use a linker script appropriate for their hardware.
# Alternatively, the default memory map can be overridden with a script that
# defines __flash, __flash_size, __ram, __ram_size and __stack_size before doing
# "INCLUDE $(LIBC_LD_FILE)".
$(ELF): *.c
	$(BIN_PATH)/clang $(CFG_FILE) $(TARGET_FLAGS) $(LINKER) $(CRT_SEMIHOST) -g -T $(LIBC_LD_FILE) -o $@ $^

run: $(ELF)
	$(QEMU) $(QEMU_SEMIHOSTING) $(call QEMU_LOAD,$<)

debug: $(ELF)
	$(QEMU) $(QEMU_SEMIHOSTING) $(call QEMU_LOAD,$<) -s -S

clean:
	rm -f *.elf

.PHONY: build clean run debug
