    .include "common.inc"
    .text
    .globl _start
_start:
    UART_BASE
    addi.w  $r5, $r0, 0x55
    st.w    $r5, $r4, 4
1:
    ld.w    $r6, $r4, 0
    andi    $r6, $r6, 1
    beq     $r6, $r0, 1b
    PASS
