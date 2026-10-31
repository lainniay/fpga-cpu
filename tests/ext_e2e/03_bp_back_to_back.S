    .include "common.inc"
    .text
    .globl _start
_start:
    addi.w  $r4, $r0, 8
    addi.w  $r5, $r0, 0
loop:
    beq     $r4, $r0, finish
    addi.w  $r5, $r5, 1
    bne     $r4, $r0, dec
    addi.w  $r5, $r5, 0x10
dec:
    addi.w  $r4, $r4, -1
    b       loop
finish:
    addi.w  $r8, $r0, 8
    bne     $r5, $r8, fail
    PASS
fail:
    FAIL
