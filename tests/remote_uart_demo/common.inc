    .macro UART_BASE
        lu12i.w $r4, 0x1faf1
    .endm

    .macro SEND_CH value
        addi.w  $r5, $r0, \value
        st.w    $r5, $r4, 4
1:      ld.w    $r6, $r4, 0
        andi    $r6, $r6, 1
        beq     $r6, $r0, 1b
    .endm
