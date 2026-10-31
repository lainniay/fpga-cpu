    .include "common.inc"
    .text
    .globl _start
_start:
    UART_BASE
    addi.w  $r5, $r0, 0xc3
    st.w    $r5, $r4, 4
1:
    ld.w    $r6, $r4, 0
    andi    $r6, $r6, 1
    beq     $r6, $r0, 1b
2:
    ld.w    $r6, $r4, 0
    andi    $r6, $r6, 2
    beq     $r6, $r0, 2b
    ld.w    $r7, $r4, 8
    addi.w  $r8, $r0, 0x3c
    bne     $r7, $r8, fail
    PASS
fail:
    FAIL
