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
    andi    $r9, $r7, 1
    beq     $r9, $r0, even
    addi.w  $r10, $r0, 1
    b       send
even:
    addi.w  $r10, $r0, 0
send:
    st.w    $r10, $r4, 4
2:
    ld.w    $r6, $r4, 0
    andi    $r6, $r6, 1
    beq     $r6, $r0, 2b
    b       loop
done:
    PASS
