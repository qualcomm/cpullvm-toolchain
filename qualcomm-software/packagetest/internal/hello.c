// RUN: %clang %{target-arm} %{link-semihost} %s -o %t-arm.elf
// RUN: %if qemu-arm %{ %{qemu-arm} %t-arm.elf 2>&1 | FileCheck %s %}
// RUN: %clang %{target-aarch64} %{link-semihost} %s -o %t-aarch64.elf
// RUN: %if qemu-aarch64 %{ %{qemu-aarch64} %t-aarch64.elf 2>&1 | FileCheck %s %}
// RUN: %clang %{target-riscv32} %{link-semihost} %s -o %t-riscv32.elf
// RUN: %if qemu-riscv32 %{ %{qemu-riscv32} %t-riscv32.elf 2>&1 | FileCheck %s %}
// RUN: %clang %{target-riscv32-xqci} %{link-semihost} %s -o %t-riscv32-xqci.elf
// RUN: %if qemu-riscv32-xqci %{ %{qemu-riscv32-xqci} %t-riscv32-xqci.elf 2>&1 | FileCheck %s %}
// RUN: %clang %{target-riscv64} %{link-semihost} %s -o %t-riscv64.elf
// RUN: %if qemu-riscv64 %{ %{qemu-riscv64} %t-riscv64.elf 2>&1 | FileCheck %s %}

#include <stdio.h>

int main(void) {
  printf("Hello World!\n"); // CHECK: Hello World!
  return 0;
}
