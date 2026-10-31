    .macro UART_BASE
        lu12i.w $r4, 0x1faf1
    .endm

    .macro PASS
        lu12i.w $r9, 0x1faff
        ori     $r9, $r9, 0xf10
        addi.w  $r10, $r0, 0xff
        st.w    $r10, $r9, 0
999:    b       999b
    .endm

    .macro FAIL
        lu12i.w $r9, 0x1faff
        ori     $r9, $r9, 0xf10
        addi.w  $r10, $r0, 0xfe
        st.w    $r10, $r9, 0
998:    b       998b
    .endm
