    .include "common.inc"
    .text
    .globl _start
_start:
    UART_BASE
    SEND_CH 0x55
    SEND_CH 0x41
    SEND_CH 0x52
    SEND_CH 0x54
    SEND_CH 0x20
    SEND_CH 0x4f
    SEND_CH 0x4b
    SEND_CH 0x0d
    SEND_CH 0x0a
loop:
    ld.w    $r6, $r4, 0
    andi    $r6, $r6, 2
    beq     $r6, $r0, loop
    ld.w    $r5, $r4, 8
    st.w    $r5, $r4, 4
wait_tx:
    ld.w    $r6, $r4, 0
    andi    $r6, $r6, 1
    beq     $r6, $r0, wait_tx
    b       loop
