    .include "common.inc"
    .text
    .globl _start
_start:
    UART_BASE
1:
    ld.w    $r6, $r4, 0
    andi    $r6, $r6, 2
    beq     $r6, $r0, 1b
    ld.w    $r7, $r4, 8
    addi.w  $r8, $r0, 0x7e
    bne     $r7, $r8, fail
    PASS
fail:
    FAIL
