    .include "common.inc"
    .text
    .globl _start
_start:
    UART_BASE
    lu12i.w $r5, 1
    ori     $r5, $r5, 0x234
    st.w    $r5, $r4, 4
1:
    ld.w    $r6, $r4, 0
    andi    $r6, $r6, 1
    beq     $r6, $r0, 1b
    PASS
