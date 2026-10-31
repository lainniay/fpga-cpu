    .include "common.inc"
    .text
    .globl _start
_start:
    UART_BASE

    addi.w  $r5, $r0, 0x00
    st.w    $r5, $r4, 4
1:
    ld.w    $r6, $r4, 0
    andi    $r6, $r6, 1
    beq     $r6, $r0, 1b

    addi.w  $r5, $r0, 0xff
    st.w    $r5, $r4, 4
2:
    ld.w    $r6, $r4, 0
    andi    $r6, $r6, 1
    beq     $r6, $r0, 2b

    addi.w  $r5, $r0, 0xaa
    st.w    $r5, $r4, 4
3:
    ld.w    $r6, $r4, 0
    andi    $r6, $r6, 1
    beq     $r6, $r0, 3b

    addi.w  $r5, $r0, 0x55
    st.w    $r5, $r4, 4
4:
    ld.w    $r6, $r4, 0
    andi    $r6, $r6, 1
    beq     $r6, $r0, 4b

    PASS
