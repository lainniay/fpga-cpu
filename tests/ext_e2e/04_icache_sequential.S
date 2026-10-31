    .include "common.inc"
    .text
    .globl _start
_start:
    addi.w  $r5, $r0, 0
    addi.w  $r5, $r5, 1
    addi.w  $r5, $r5, 1
    addi.w  $r5, $r5, 1
    addi.w  $r5, $r5, 1
    addi.w  $r5, $r5, 1
    addi.w  $r5, $r5, 1
    addi.w  $r5, $r5, 1
    addi.w  $r5, $r5, 1
    addi.w  $r5, $r5, 1
    addi.w  $r5, $r5, 1
    addi.w  $r5, $r5, 1
    addi.w  $r5, $r5, 1
    addi.w  $r5, $r5, 1
    addi.w  $r5, $r5, 1
    addi.w  $r5, $r5, 1
    addi.w  $r5, $r5, 1
    addi.w  $r5, $r5, 1
    addi.w  $r5, $r5, 1
    addi.w  $r5, $r5, 1
    addi.w  $r5, $r5, 1
    addi.w  $r8, $r0, 20
    bne     $r5, $r8, fail
    PASS
fail:
    FAIL
