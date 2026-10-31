    .include "common.inc"
    .text
    .globl _start
_start:
    addi.w  $r4, $r0, 8
    addi.w  $r5, $r0, 0
loop:
    andi    $r6, $r4, 1
    beq     $r6, $r0, even
    addi.w  $r5, $r5, 1
    b       next
even:
    addi.w  $r5, $r5, 2
next:
    addi.w  $r4, $r4, -1
    bne     $r4, $r0, loop
    addi.w  $r8, $r0, 12
    bne     $r5, $r8, fail
    PASS
fail:
    FAIL
