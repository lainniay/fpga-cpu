    .include "common.inc"
    .text
    .globl _start
_start:
    UART_BASE
loop:
1:
    ld.w    $r6, $r4, 0
    andi    $r6, $r6, 2
    beq     $r6, $r0, 1b
    ld.w    $r7, $r4, 8
    addi.w  $r8, $r0, 0xff
    beq     $r7, $r8, done
    st.w    $r7, $r4, 4
2:
    ld.w    $r6, $r4, 0
    andi    $r6, $r6, 1
    beq     $r6, $r0, 2b
    b       loop
done:
    PASS
