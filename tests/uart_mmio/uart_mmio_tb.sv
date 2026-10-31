`timescale 1ns/1ps

module uart_mmio_tb;
    localparam integer CLK_NS = 10;
    localparam integer BIT_CYCLES = 868;
    localparam integer BIT_NS = BIT_CYCLES * CLK_NS;

    reg clk = 1'b0;
    always #(CLK_NS / 2) clk = ~clk;
    reg reset = 1'b1;
    reg sel = 1'b0;
    reg [3:0] we = 4'd0;
    reg commit = 1'b0;
    reg [31:0] wdata = 32'd0;
    reg [7:0] addr_off = 8'd0;
    reg serial_in = 1'b1;
    wire [31:0] rdata;
    wire serial_out;

    reg [7:0] expected_tx [0:63];
    integer tx_expected = 0;
    integer tx_started = 0;
    integer tx_completed = 0;
    integer tx_aborted = 0;
    integer cases_checked = 0;
    integer mask;
    integer offset;
    integer count_before;
    integer tick;
    reg [31:0] sampled;
    string current_case = "initial reset";

    uart_mmio dut (
        .clk(clk), .reset(reset), .sel(sel), .we(we),
        .commit(commit), .wdata(wdata), .addr_off(addr_off),
        .rdata(rdata), .uart_rx(serial_in), .uart_tx(serial_out)
    );

    // Decode the actual output pin independently of the TX implementation.
    // The separate TX test checks every bit's exact duration and busy timing.
    always @(negedge serial_out) begin : observe_tx
        reg [7:0] wanted;
        reg [7:0] decoded;
        integer bit_no;
        if (!reset) begin
            if (tx_started >= tx_expected)
                $fatal(1, "Unexpected TX frame during %s", current_case);
            wanted = expected_tx[tx_started];
            tx_started = tx_started + 1;

            fork : frame_or_reset
                begin
                    #(BIT_NS / 2);
                    if (serial_out !== 1'b0)
                        $fatal(1, "TX start bit invalid");
                    for (bit_no = 0; bit_no < 8; bit_no = bit_no + 1) begin
                        #(BIT_NS);
                        decoded[bit_no] = serial_out;
                    end
                    #(BIT_NS);
                    if (serial_out !== 1'b1 || decoded !== wanted)
                        $fatal(1, "TX expected=%02h received=%02h stop=%b",
                               wanted, decoded, serial_out);
                    tx_completed = tx_completed + 1;
                    // Return before the next legal start bit.
                    #(BIT_NS / 2 - 1);
                end
                begin
                    @(posedge reset);
                    tx_aborted = tx_aborted + 1;
                end
            join_any
            disable frame_or_reset;
        end
    end

    task automatic idle_bus;
        begin
            sel = 1'b0;
            commit = 1'b0;
            we = 4'd0;
            addr_off = 8'd0;
            wdata = 32'd0;
        end
    endtask

    // Read sampling happens on the access edge BEFORE DUT NBA updates.
    task automatic bus_access(
        input bit selected,
        input bit committed,
        input [3:0] mask_value,
        input [7:0] off,
        input [31:0] value,
        output [31:0] read_value
    );
        begin
            @(negedge clk);
            sel = selected;
            commit = committed;
            we = mask_value;
            addr_off = off;
            wdata = value;
            @(posedge clk);
            read_value = rdata;
            #1;
            @(negedge clk);
            idle_bus();
        end
    endtask

    task automatic check_read(
        input [7:0] off,
        input [31:0] wanted
    );
        reg [31:0] value;
        begin
            bus_access(1'b1, 1'b1, 4'd0, off, 32'd0, value);
            if (value !== wanted)
                $fatal(1, "%s: read %02h expected=%08h received=%08h",
                       current_case, off, wanted, value);
        end
    endtask

    task automatic check_peek(
        input [7:0] off,
        input [31:0] wanted
    );
        reg [31:0] value;
        begin
            bus_access(1'b1, 1'b0, 4'd0, off, 32'd0, value);
            if (value !== wanted)
                $fatal(1, "%s: uncommitted read %02h expected=%08h received=%08h",
                       current_case, off, wanted, value);
        end
    endtask

    task automatic write_reg(
        input [7:0] off,
        input [3:0] mask_value,
        input [31:0] value
    );
        reg [31:0] ignored;
        begin
            bus_access(1'b1, 1'b1, mask_value, off, value, ignored);
        end
    endtask

    task automatic expect_tx(input [7:0] value);
        begin
            if (tx_expected >= 64)
                $fatal(1, "TX expected queue full");
            expected_tx[tx_expected] = value;
            tx_expected = tx_expected + 1;
        end
    endtask

    task automatic accept_tx(
        input [31:0] value,
        input [3:0] mask_value
    );
        integer started_before;
        begin
            started_before = tx_started;
            expect_tx(value[7:0]);
            @(negedge clk);
            sel = 1'b1;
            commit = 1'b1;
            we = mask_value;
            addr_off = 8'h04;
            wdata = value;
            @(posedge clk);
            #1;
            if (tx_started != started_before + 1 || serial_out !== 1'b0)
                $fatal(1, "TX did not start on the MMIO write edge");

            // Check TX_READY immediately after the accepting edge.
            addr_off = 8'h00;
            we = 4'd0;
            #1;
            if (rdata[0] !== 1'b0 || rdata[31:2] !== 30'd0)
                $fatal(1, "TX_READY did not clear on the accepting edge");
            @(negedge clk);
            idle_bus();
        end
    endtask

    task automatic wait_tx_ready;
        reg [31:0] value;
        integer poll_count;
        begin : poll_ready
            for (poll_count = 0; poll_count < 10000;
                 poll_count = poll_count + 1) begin
                bus_access(1'b1, 1'b0, 4'd0, 8'h00, 32'd0, value);
                if (value[31:2] !== 30'd0 ||
                    (value[0] !== 1'b0 && value[0] !== 1'b1))
                    $fatal(1, "Invalid STATUS while waiting for TX");
                if (value[0] === 1'b1)
                    disable poll_ready;
            end
            $fatal(1, "TX_READY timeout during %s", current_case);
        end
    endtask

    task automatic send_rx(input [7:0] value, input bit good_stop);
        integer bit_no;
        begin
            serial_in = 1'b0;
            #(BIT_NS);
            for (bit_no = 0; bit_no < 8; bit_no = bit_no + 1) begin
                serial_in = value[bit_no];
                #(BIT_NS);
            end
            serial_in = good_stop;
            #(BIT_NS);
            serial_in = 1'b1;
        end
    endtask

    // Schedule a real bus read on the edge that MMIO samples the real RX
    // completion pulse. No RX data or DUT state is forced or replaced.
    task automatic read_with_new_rx(
        input [7:0] new_byte,
        input [31:0] old_read_value
    );
        begin
            fork
                begin
                    send_rx(new_byte, 1'b1);
                end
                begin
                    @(posedge dut.u_rx.rx_valid);
                    check_read(8'h08, old_read_value);
                end
            join
        end
    endtask

    task automatic finish_case(input string name);
        begin
            repeat (4) @(negedge clk);
            if (tx_started != tx_expected ||
                tx_completed + tx_aborted != tx_started)
                $fatal(1, "%s: TX expected=%0d started=%0d completed=%0d aborted=%0d",
                       name, tx_expected, tx_started, tx_completed, tx_aborted);
            cases_checked = cases_checked + 1;
            $display("[PASS] MMIO %s", name);
        end
    endtask

    initial begin
        if ($test$plusargs("wave")) begin
            $dumpfile("build/uart_mmio/uart_mmio.vcd");
            $dumpvars(0, uart_mmio_tb);
        end

        repeat (4) @(negedge clk);
        reset = 1'b0;
        repeat (8) @(negedge clk);
        check_read(8'h00, 32'h1);
        check_read(8'h08, 32'h0);
        check_read(8'h04, 32'h0);
        bus_access(1'b0, 1'b1, 4'd0, 8'h00, 32'd0, sampled);
        if (sampled !== 32'd0)
            $fatal(1, "Unselected UART read must return zero");
        finish_case("reset, idle and empty reads");

        current_case = "write qualification";
        count_before = tx_started;
        for (mask = 0; mask < 16; mask = mask + 2)
            write_reg(8'h04, mask[3:0], 32'h11223344);
        bus_access(1'b0, 1'b1, 4'hF, 8'h04, 32'h55, sampled);
        bus_access(1'b1, 1'b0, 4'hF, 8'h04, 32'h66, sampled);
        write_reg(8'h00, 4'hF, 32'hFFFFFFFF);
        write_reg(8'h08, 4'hF, 32'hFFFFFFFF);
        repeat (8) @(negedge clk);
        if (tx_started != count_before)
            $fatal(1, "An invalid write started TX");
        check_read(8'h00, 32'h1);
        finish_case(current_case);

        current_case = "all valid byte masks and busy writes";
        for (mask = 1; mask < 16; mask = mask + 2) begin
            accept_tx(32'hA55AC300 | mask, mask[3:0]);
            check_read(8'h00, 32'h0);
            write_reg(8'h04, 4'hF, 32'hDEADBEEF);
            bus_access(1'b1, 1'b0, 4'hF, 8'h04, 32'hFFFFFFFF, sampled);
            wait_tx_ready();
            check_read(8'h00, 32'h1);
        end
        finish_case(current_case);

        current_case = "continuous commit represents repeated accesses";
        expect_tx(8'hD6);
        expect_tx(8'hD6);
        count_before = tx_started;
        @(negedge clk);
        sel = 1'b1;
        commit = 1'b1;
        we = 4'h1;
        addr_off = 8'h04;
        wdata = 32'hD6;
        // Keep commit high across completion of the first frame.
        for (tick = 0; tick < 10 * BIT_CYCLES + 10 &&
             tx_started < count_before + 2; tick = tick + 1)
            @(negedge clk);
        idle_bus();
        if (tx_started != count_before + 2)
            $fatal(1, "Continuous commit was incorrectly treated as an edge");
        wait_tx_ready();
        finish_case(current_case);

        current_case = "RX retention, read-clear and exact address decoding";
        #2;
        send_rx(8'h41, 1'b1);
        check_read(8'h00, 32'h3);
        check_peek(8'h08, 32'h41);
        check_peek(8'h08, 32'h41);
        write_reg(8'h00, 4'hF, 32'hFFFFFFFF);
        write_reg(8'h08, 4'hF, 32'hFFFFFFFF);
        bus_access(1'b0, 1'b1, 4'd0, 8'h08, 32'd0, sampled);
        if (sampled !== 32'd0)
            $fatal(1, "Unselected RXDATA read must return zero");
        for (offset = 0; offset < 256; offset = offset + 1) begin
            if (offset != 0 && offset != 4 && offset != 8) begin
                check_read(offset[7:0], 32'd0);
                write_reg(offset[7:0], 4'hF, 32'h12345678);
            end
        end
        check_read(8'h00, 32'h3);
        check_read(8'h08, 32'h41);
        check_read(8'h00, 32'h1);
        check_read(8'h08, 32'h0);
        finish_case(current_case);

        current_case = "full RX buffer preserves old byte";
        #2;
        send_rx(8'hA1, 1'b1);
        send_rx(8'hB2, 1'b1);
        check_read(8'h00, 32'h3);
        check_read(8'h08, 32'hA1);
        check_read(8'h08, 32'h0);
        #2;
        send_rx(8'hC3, 1'b1);
        check_read(8'h08, 32'hC3);
        finish_case(current_case);

        current_case = "read old byte and receive new byte on same edge";
        #2;
        send_rx(8'h11, 1'b1);
        check_read(8'h00, 32'h3);
        #2;
        read_with_new_rx(8'h22, 32'h11);
        check_read(8'h00, 32'h3);
        check_read(8'h08, 32'h22);
        check_read(8'h00, 32'h1);
        finish_case(current_case);

        current_case = "empty read and receive new byte on same edge";
        #2;
        read_with_new_rx(8'h33, 32'h0);
        check_read(8'h00, 32'h3);
        check_read(8'h08, 32'h33);
        check_read(8'h00, 32'h1);
        finish_case(current_case);

        current_case = "invalid stop and recovery through real RX";
        #2;
        send_rx(8'h96, 1'b0);
        #(2 * BIT_NS);
        check_read(8'h00, 32'h1);
        check_read(8'h08, 32'h0);
        #2;
        send_rx(8'h44, 1'b1);
        check_read(8'h08, 32'h44);
        finish_case(current_case);

        current_case = "simultaneous transmit and receive";
        fork
            begin
                accept_tx(32'h765432A6, 4'hF);
                write_reg(8'h04, 4'h1, 32'hEE);
                wait_tx_ready();
            end
            begin
                #113;
                send_rx(8'h5A, 1'b1);
            end
        join
        check_read(8'h00, 32'h3);
        check_read(8'h08, 32'h5A);
        finish_case(current_case);

        current_case = "reset overrides accesses and cancels RX/TX";
        #2;
        send_rx(8'h88, 1'b1);
        check_read(8'h00, 32'h3);
        accept_tx(32'h77, 4'h1);
        count_before = tx_started;
        #2;
        serial_in = 1'b0;
        #(BIT_NS);
        @(negedge clk);
        reset = 1'b1;
        serial_in = 1'b1;
        sel = 1'b1;
        commit = 1'b1;
        we = 4'hF;
        addr_off = 8'h04;
        wdata = 32'hFF;
        repeat (4) begin
            @(posedge clk);
            #1;
            if (serial_out !== 1'b1)
                $fatal(1, "Reset did not restore TX idle level");
        end
        @(negedge clk);
        idle_bus();
        reset = 1'b0;
        repeat (8) @(negedge clk);
        check_read(8'h00, 32'h1);
        check_read(8'h08, 32'h0);
        #(12 * BIT_NS);
        check_read(8'h00, 32'h1);
        if (tx_started != count_before)
            $fatal(1, "Reset generated or queued an extra TX frame");
        finish_case(current_case);

        current_case = "reset overrides simultaneous RX completion and read";
        #2;
        send_rx(8'h55, 1'b1);
        check_read(8'h00, 32'h3);
        #2;
        fork
            begin
                send_rx(8'h66, 1'b1);
            end
            begin
                @(posedge dut.u_rx.rx_valid);
                @(negedge clk);
                reset = 1'b1;
                sel = 1'b1;
                commit = 1'b1;
                we = 4'd0;
                addr_off = 8'h08;
                repeat (4) @(negedge clk);
                idle_bus();
                reset = 1'b0;
            end
        join
        check_read(8'h00, 32'h1);
        check_read(8'h08, 32'h0);
        finish_case(current_case);

        current_case = "receive and transmit after reset";
        #2;
        send_rx(8'h5C, 1'b1);
        check_read(8'h08, 32'h5C);
        accept_tx(32'h9D, 4'h1);
        wait_tx_ready();
        check_read(8'h00, 32'h1);
        finish_case(current_case);

        if (tx_aborted != 1)
            $fatal(1, "Expected exactly one reset-aborted TX frame");
        $display("[PASS] UART MMIO complete: %0d cases, %0d TX frames, %0d reset abort",
                 cases_checked, tx_completed, tx_aborted);
        $finish;
    end

    initial begin
        #100_000_000;
        $fatal(1, "UART MMIO timeout during %s", current_case);
    end
endmodule
