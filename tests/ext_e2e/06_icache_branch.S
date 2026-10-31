    .include "common.inc"
    .text
    .globl _start
_start:
    addi.w  $r5, $r0, 0
    b       far
    addi.w  $r5, $r5, 0x10
    addi.w  $r5, $r5, 0x10
    addi.w  $r5, $r5, 0x10
    addi.w  $r5, $r5, 0x10
    addi.w  $r5, $r5, 0x10
    addi.w  $r5, $r5, 0x10
    addi.w  $r5, $r5, 0x10
    addi.w  $r5, $r5, 0x10
    addi.w  $r5, $r5, 0x10
    addi.w  $r5, $r5, 0x10
    addi.w  $r5, $r5, 0x10
    addi.w  $r5, $r5, 0x10
    addi.w  $r5, $r5, 0x10
    addi.w  $r5, $r5, 0x10
    addi.w  $r5, $r5, 0x10
    addi.w  $r5, $r5, 0x10
    addi.w  $r5, $r5, 0x10
    addi.w  $r5, $r5, 0x10
    addi.w  $r5, $r5, 0x10
    addi.w  $r5, $r5, 0x10
far:
    addi.w  $r5, $r5, 1
    addi.w  $r8, $r0, 1
    bne     $r5, $r8, fail
    PASS
fail:
    FAIL
