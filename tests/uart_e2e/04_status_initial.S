    .include "common.inc"
    .text
    .globl _start
_start:
    UART_BASE
    ld.w    $r6, $r4, 0
    andi    $r7, $r6, 1
    beq     $r7, $r0, fail
    andi    $r7, $r6, 2
    bne     $r7, $r0, fail
    PASS
fail:
    FAIL
