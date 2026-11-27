#
# Copyright (c) 2021-2025, Arm Limited and affiliates.
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

# See the baremetal-semihosting sample for a description of the memory map.
$(ELF): *.cpp
	$(BIN_PATH)/clang++ $(CFG_FILE) $(TARGET_FLAGS) $(CPP_FLAGS) $(LINKER) $(CRT_SEMIHOST) -g -T $(LIBC_LD_FILE) -o $@ $^

run: $(ELF)
	$(QEMU) $(QEMU_SEMIHOSTING) $(call QEMU_LOAD,$<)

debug: $(ELF)
	$(QEMU) $(QEMU_SEMIHOSTING) $(call QEMU_LOAD,$<) -s -S

clean:
	rm -f *.elf

.PHONY: build clean run debug
