    .include "common.inc"
    .text
    .globl _start
_start:
    UART_BASE
    add.w   $r3, $r4, $r0
1:
    ld.w    $r6, $r3, 0
    andi    $r6, $r6, 2
    beq     $r6, $r0, 1b
    ld.w    $r4, $r3, 8
loop:
    beq     $r4, $r0, done
2:
    ld.w    $r6, $r3, 0
    andi    $r6, $r6, 2
    beq     $r6, $r0, 2b
    ld.w    $r7, $r3, 8
    st.w    $r7, $r3, 4
3:
    ld.w    $r6, $r3, 0
    andi    $r6, $r6, 1
    beq     $r6, $r0, 3b
    addi.w  $r4, $r4, -1
    b       loop
done:
    PASS
