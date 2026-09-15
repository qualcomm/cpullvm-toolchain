; NOTE: This test is derived from the following C source. Two equally sized
; groups of candidates exist for one repeated sequence, one in .sec_a and one
; in .sec_b. Only one input section can be outlined per pass, so the tie is
; broken by the lexicographically smaller section name and .sec_a wins. A rerun
; then outlines the remaining .sec_b group into its own outlined function.
;
; #define BODY(N) do { a ^= b; b += a; a = (a << 3) | (a >> 29); \
;                       a ^= b; return a + N; } while (0)
; #define SEC(S, N, V) __attribute__((noinline, section(S))) \
;   unsigned N(unsigned a, unsigned b) { BODY(V); }
; SEC(".sec_a", a_0, 1) SEC(".sec_a", a_1, 2)
; SEC(".sec_b", b_0, 3) SEC(".sec_b", b_1, 4)

; RUN: llc -mtriple=riscv32 -enable-machine-outliner=always -verify-machineinstrs < %s | FileCheck %s --check-prefix=NORERUNS
; RUN: llc -mtriple=riscv32 -enable-machine-outliner=always -machine-outliner-reruns=1 -verify-machineinstrs < %s | FileCheck %s --check-prefix=RERUNS

define i32 @a_0(i32 %a, i32 %b) noinline section ".sec_a" {
; NORERUNS-LABEL: a_0:
; NORERUNS: call t0, OUTLINED_FUNCTION_0
; RERUNS-LABEL: a_0:
; RERUNS: call t0, OUTLINED_FUNCTION_0
  %a0 = xor i32 %a, %b
  %b0 = add i32 %b, %a0
  %a1 = shl i32 %a0, 3
  %a2 = lshr i32 %a0, 29
  %a3 = or i32 %a1, %a2
  %a4 = xor i32 %a3, %b0
  %result = add i32 %a4, 1
  ret i32 %result
}

define i32 @a_1(i32 %a, i32 %b) noinline section ".sec_a" {
; NORERUNS-LABEL: a_1:
; NORERUNS: call t0, OUTLINED_FUNCTION_0
; RERUNS-LABEL: a_1:
; RERUNS: call t0, OUTLINED_FUNCTION_0
  %a0 = xor i32 %a, %b
  %b0 = add i32 %b, %a0
  %a1 = shl i32 %a0, 3
  %a2 = lshr i32 %a0, 29
  %a3 = or i32 %a1, %a2
  %a4 = xor i32 %a3, %b0
  %result = add i32 %a4, 2
  ret i32 %result
}

; Without a rerun the .sec_b group keeps the full sequence inline.
define i32 @b_0(i32 %a, i32 %b) noinline section ".sec_b" {
; NORERUNS-LABEL: b_0:
; NORERUNS-NOT: call t0, OUTLINED_FUNCTION
; NORERUNS: xor a0, a0, a1
; RERUNS-LABEL: b_0:
; RERUNS: call t0, OUTLINED_FUNCTION_2_0
  %a0 = xor i32 %a, %b
  %b0 = add i32 %b, %a0
  %a1 = shl i32 %a0, 3
  %a2 = lshr i32 %a0, 29
  %a3 = or i32 %a1, %a2
  %a4 = xor i32 %a3, %b0
  %result = add i32 %a4, 3
  ret i32 %result
}

define i32 @b_1(i32 %a, i32 %b) noinline section ".sec_b" {
; NORERUNS-LABEL: b_1:
; NORERUNS-NOT: call t0, OUTLINED_FUNCTION
; NORERUNS: xor a0, a0, a1
; RERUNS-LABEL: b_1:
; RERUNS: call t0, OUTLINED_FUNCTION_2_0
  %a0 = xor i32 %a, %b
  %b0 = add i32 %b, %a0
  %a1 = shl i32 %a0, 3
  %a2 = lshr i32 %a0, 29
  %a3 = or i32 %a1, %a2
  %a4 = xor i32 %a3, %b0
  %result = add i32 %a4, 4
  ret i32 %result
}

; Only the .sec_a group is outlined without a rerun.
; NORERUNS: .section .sec_a,"ax",@progbits
; NORERUNS: OUTLINED_FUNCTION_0:
; NORERUNS-NOT: OUTLINED_FUNCTION_2_0:

; Each group is outlined into its own input section with a rerun.
; RERUNS: .section .sec_a,"ax",@progbits
; RERUNS: OUTLINED_FUNCTION_0:
; RERUNS: .section .sec_b,"ax",@progbits
; RERUNS: OUTLINED_FUNCTION_2_0:
