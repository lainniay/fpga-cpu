    .include "common.inc"
    .text
    .globl _start
_start:
    addi.w  $r4, $r0, 16
    addi.w  $r5, $r0, 0
loop:
    addi.w  $r5, $r5, 1
    addi.w  $r4, $r4, -1
    bne     $r4, $r0, loop
    addi.w  $r8, $r0, 16
    bne     $r5, $r8, fail
    PASS
fail:
    FAIL
