    .include "common.inc"
    .text
    .globl _start
_start:
    UART_BASE
    add.w   $r3, $r4, $r0
    addi.w  $r4, $r0, 4
    addi.w  $r5, $r0, 0
loop:
1:
    ld.w    $r6, $r3, 0
    andi    $r6, $r6, 2
    beq     $r6, $r0, 1b
    ld.w    $r7, $r3, 8
    add.w   $r5, $r5, $r7
    addi.w  $r4, $r4, -1
    bne     $r4, $r0, loop

    st.w    $r5, $r3, 4
2:
    ld.w    $r6, $r3, 0
    andi    $r6, $r6, 1
    beq     $r6, $r0, 2b
    PASS
