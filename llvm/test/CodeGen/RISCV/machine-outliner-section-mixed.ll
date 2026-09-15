; NOTE: This test is derived from the following C source. It exercises normal
; outlining alongside outlining from explicitly sectioned functions.
;
; This also demonstrates the placement tie-break, here between functions with
; no explicit input section and functions with a named input section. Both
; groups have three occurrences of the same sequence, and only one input
; section can be outlined per pass. The empty section name of the unsectioned
; functions sorts before .sec_shared, so they win the first pass. Adding the
; rerun flag therefore outlines the sequence from the named input section
; functions as well, into a separate outlined function placed in .sec_shared.
;
; #define BODY(N) do { a ^= b; b += a; a = (a << 3) | (a >> 29); \
;                       a ^= b; return a + N; } while (0)
; #define SEC(N, V) __attribute__((noinline, section(".sec_shared"))) \
;   unsigned N(unsigned a, unsigned b) { BODY(V); }
; #define PLAIN(N, V) __attribute__((noinline)) \
;   unsigned N(unsigned a, unsigned b) { BODY(V); }
; SEC(shared_0, 1) SEC(shared_1, 2) SEC(shared_2, 3)
; PLAIN(plain_0, 4) PLAIN(plain_1, 5) PLAIN(plain_2, 6)

; RUN: llc -mtriple=riscv32 -enable-machine-outliner=always -machine-outliner-reruns=1 -verify-machineinstrs < %s | FileCheck %s --check-prefixes=CHECK,NOFS
; RUN: llc -mtriple=riscv32 -enable-machine-outliner=always -machine-outliner-reruns=1 --function-sections -verify-machineinstrs < %s | FileCheck %s --check-prefixes=CHECK,FS

; CHECK: .section .sec_shared,"ax",@progbits

define i32 @shared_0(i32 %a, i32 %b) noinline section ".sec_shared" {
; CHECK-LABEL: shared_0:
; CHECK: call t0, OUTLINED_FUNCTION_[[SHARED:[0-9_]+]]
  %a0 = xor i32 %a, %b
  %b0 = add i32 %b, %a0
  %a1 = shl i32 %a0, 3
  %a2 = lshr i32 %a0, 29
  %a3 = or i32 %a1, %a2
  %a4 = xor i32 %a3, %b0
  %result = add i32 %a4, 1
  ret i32 %result
}

define i32 @shared_1(i32 %a, i32 %b) noinline section ".sec_shared" {
; CHECK-LABEL: shared_1:
; CHECK: call t0, OUTLINED_FUNCTION_[[SHARED]]
  %a0 = xor i32 %a, %b
  %b0 = add i32 %b, %a0
  %a1 = shl i32 %a0, 3
  %a2 = lshr i32 %a0, 29
  %a3 = or i32 %a1, %a2
  %a4 = xor i32 %a3, %b0
  %result = add i32 %a4, 2
  ret i32 %result
}

define i32 @shared_2(i32 %a, i32 %b) noinline section ".sec_shared" {
; CHECK-LABEL: shared_2:
; CHECK: call t0, OUTLINED_FUNCTION_[[SHARED]]
  %a0 = xor i32 %a, %b
  %b0 = add i32 %b, %a0
  %a1 = shl i32 %a0, 3
  %a2 = lshr i32 %a0, 29
  %a3 = or i32 %a1, %a2
  %a4 = xor i32 %a3, %b0
  %result = add i32 %a4, 3
  ret i32 %result
}

define i32 @plain_0(i32 %a, i32 %b) noinline {
; NOFS: .text
; FS: .section .text.plain_0,"ax",@progbits
; CHECK-LABEL: plain_0:
; CHECK: call t0, OUTLINED_FUNCTION_[[PLAIN:[0-9_]+]]
  %a0 = xor i32 %a, %b
  %b0 = add i32 %b, %a0
  %a1 = shl i32 %a0, 3
  %a2 = lshr i32 %a0, 29
  %a3 = or i32 %a1, %a2
  %a4 = xor i32 %a3, %b0
  %result = add i32 %a4, 4
  ret i32 %result
}

define i32 @plain_1(i32 %a, i32 %b) noinline {
; CHECK-LABEL: plain_1:
; CHECK: call t0, OUTLINED_FUNCTION_[[PLAIN]]
  %a0 = xor i32 %a, %b
  %b0 = add i32 %b, %a0
  %a1 = shl i32 %a0, 3
  %a2 = lshr i32 %a0, 29
  %a3 = or i32 %a1, %a2
  %a4 = xor i32 %a3, %b0
  %result = add i32 %a4, 5
  ret i32 %result
}

define i32 @plain_2(i32 %a, i32 %b) noinline {
; CHECK-LABEL: plain_2:
; CHECK: call t0, OUTLINED_FUNCTION_[[PLAIN]]
  %a0 = xor i32 %a, %b
  %b0 = add i32 %b, %a0
  %a1 = shl i32 %a0, 3
  %a2 = lshr i32 %a0, 29
  %a3 = or i32 %a1, %a2
  %a4 = xor i32 %a3, %b0
  %result = add i32 %a4, 6
  ret i32 %result
}

; The unsectioned group wins the first pass, and the rerun outlines the
; .sec_shared group into a separate function in .sec_shared.
; NOFS: OUTLINED_FUNCTION_[[PLAIN]]:
; FS: .section .text.OUTLINED_FUNCTION_[[PLAIN]],"ax",@progbits
; FS: OUTLINED_FUNCTION_[[PLAIN]]:
; CHECK: .section .sec_shared,"ax",@progbits
; CHECK: OUTLINED_FUNCTION_[[SHARED]]:
