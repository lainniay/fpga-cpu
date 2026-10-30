`timescale 1ns/1ps

module uart_rx_tb;

    localparam integer CLK_NS = 10;
    localparam integer DIV_SLOW = 10417;
    localparam integer DIV_FAST = 868;

    reg clk = 1'b0;
    always #(CLK_NS / 2) clk = ~clk;

    reg reset = 1'b1;
    reg [1:0] baud_sel = 2'd1;
    reg serial_in = 1'b1;

    wire rx_valid;
    wire [7:0] rx_data;

    uart_rx dut (
        .clk      (clk),
        .reset    (reset),
        .baud_sel (baud_sel),
        .uart_rx  (serial_in),
        .rx_valid (rx_valid),
        .rx_data  (rx_data)
    );

    // Record valid bytes that the external sender plans to transmit.
    reg [7:0] expected_data [0:63];
    time earliest_valid [0:63];

    integer expected_count = 0;
    integer received_count = 0;
    reg previous_valid = 1'b0;

    reg [7:0] patterns [0:5];
    integer mode;
    integer cycles;
    integer i;

    // Observe after the DUT's nonblocking assignments have settled.
    always @(posedge clk) begin
        #1;

        if (reset) begin
            if (rx_valid !== 1'b0)
                $fatal(1, "rx_valid must be 0 during reset");

            previous_valid = 1'b0;
        end
        else begin
            if ((rx_valid !== 1'b0) &&
                (rx_valid !== 1'b1))
                $fatal(1, "rx_valid contains X/Z");

            if (rx_valid === 1'b1) begin
                if (previous_valid)
                    $fatal(1, "rx_valid lasted more than one cycle");

                if (received_count >= expected_count)
                    $fatal(1,
                        "Unexpected byte: %02h at time %0t",
                        rx_data, $time);

                if ($time < earliest_valid[received_count])
                    $fatal(1, "Byte reported before stop bit");

                if (rx_data !== expected_data[received_count])
                    $fatal(1,
                        "Byte %0d: expected=%02h received=%02h",
                        received_count,
                        expected_data[received_count],
                        rx_data);

                received_count = received_count + 1;
            end

            previous_valid = rx_valid;
        end
    end

    task automatic expect_byte(
        input [7:0] value,
        input integer bit_cycles
    );
        begin
            if (expected_count >= 64)
                $fatal(1, "Expected-data queue is full");

            expected_data[expected_count] = value;

            // The stop bit starts after one start bit and eight data bits.
            earliest_valid[expected_count] =
                $time + 9 * bit_cycles * CLK_NS;

            expected_count = expected_count + 1;
        end
    endtask

    // Drive a complete 8N1 frame without inspecting DUT internals.
    task automatic send_frame(
        input [7:0] value,
        input integer bit_cycles,
        input bit good_stop
    );
        integer bit_no;
        begin
            serial_in = 1'b0;
            #(bit_cycles * CLK_NS);

            for (bit_no = 0; bit_no < 8; bit_no = bit_no + 1) begin
                serial_in = value[bit_no];
                #(bit_cycles * CLK_NS);
            end

            serial_in = good_stop;
            #(bit_cycles * CLK_NS);

            serial_in = 1'b1;
        end
    endtask

    task automatic reset_rx;
        begin
            @(negedge clk);
            reset = 1'b1;
            serial_in = 1'b1;

            repeat (4) @(negedge clk);
            reset = 1'b0;

            repeat (8) @(negedge clk);
        end
    endtask

    task automatic checkpoint(input string name);
        begin
            repeat (8) @(negedge clk);

            if (received_count != expected_count)
                $fatal(1,
                    "%s: missing byte, expected count=%0d received=%0d",
                    name, expected_count, received_count);

            $display("[PASS] %s", name);
        end
    endtask

    initial begin
        // Enable waveform output with the optional runtime argument +wave.
        if ($test$plusargs("wave")) begin
            $dumpfile("uart_rx.vcd");
            $dumpvars(0, uart_rx_tb);
        end

        patterns[0] = 8'h00;
        patterns[1] = 8'hFF;
        patterns[2] = 8'h55;
        patterns[3] = 8'hAA;
        patterns[4] = 8'h81;
        patterns[5] = 8'h41;

        reset_rx();

        // 1. Idle must not produce a byte.
        #(12 * DIV_FAST * CLK_NS);
        checkpoint("reset and idle");

        // 2. Both baud rates, varied data patterns and input phases.
        for (mode = 0; mode < 2; mode = mode + 1) begin
            baud_sel = (mode == 0) ? 2'd0 : 2'd1;
            cycles = (mode == 0) ? DIV_SLOW : DIV_FAST;

            for (i = 0; i < 6; i = i + 1) begin
                case (i % 3)
                    0: #2;
                    1: #4;
                    2: #7;
                endcase

                expect_byte(patterns[i], cycles);
                send_frame(patterns[i], cycles, 1'b1);
                checkpoint($sformatf(
                    "baud_sel=%0d data=%02h", mode, patterns[i]));
            end

            // Each frame has one full stop bit and no extra idle bit.
            #2;
            expect_byte(8'h12, cycles);
            send_frame(8'h12, cycles, 1'b1);

            expect_byte(8'hA5, cycles);
            send_frame(8'hA5, cycles, 1'b1);

            expect_byte(8'hE7, cycles);
            send_frame(8'hE7, cycles, 1'b1);

            checkpoint($sformatf(
                "back-to-back frames baud_sel=%0d", mode));
        end

        // 3. Invalid starts, invalid stops and subsequent recovery.
        for (mode = 0; mode < 2; mode = mode + 1) begin
            baud_sel = (mode == 0) ? 2'd0 : 2'd1;
            cycles = (mode == 0) ? DIV_SLOW : DIV_FAST;

            // A quarter-bit low pulse must fail start-bit confirmation.
            #2;
            serial_in = 1'b0;
            #((cycles / 4) * CLK_NS);
            serial_in = 1'b1;

            #(12 * cycles * CLK_NS);
            checkpoint($sformatf(
                "false start baud_sel=%0d", mode));

            // An invalid frame is intentionally not added to the queue.
            #2;
            send_frame(8'h96, cycles, 1'b0);

            #(2 * cycles * CLK_NS);
            checkpoint($sformatf(
                "bad stop baud_sel=%0d", mode));

            #2;
            expect_byte(8'h3C, cycles);
            send_frame(8'h3C, cycles, 1'b1);

            checkpoint($sformatf(
                "recovery baud_sel=%0d", mode));
        end

        // 4. Change configuration after the current frame has started.
        // The external sender keeps the original bit duration.
        for (mode = 0; mode < 2; mode = mode + 1) begin
            baud_sel = (mode == 0) ? 2'd0 : 2'd1;
            cycles = (mode == 0) ? DIV_SLOW : DIV_FAST;

            #2;
            expect_byte(8'h69, cycles);

            fork
                begin
                    send_frame(8'h69, cycles, 1'b1);
                end

                begin
                    #(2 * cycles * CLK_NS);
                    baud_sel = (mode == 0) ? 2'd1 : 2'd0;
                end
            join

            checkpoint($sformatf(
                "baud change during frame, original=%0d", mode));
        end

        // 5. Reset cancels a partial frame; the sender also returns idle.
        baud_sel = 2'd1;

        #2;
        serial_in = 1'b0;
        #(DIV_FAST * CLK_NS);

        serial_in = 1'b1;
        #(DIV_FAST * CLK_NS);

        serial_in = 1'b0;
        #((DIV_FAST / 3) * CLK_NS);

        reset_rx();

        #(12 * DIV_FAST * CLK_NS);
        checkpoint("reset cancels partial frame");

        #2;
        expect_byte(8'hB4, DIV_FAST);
        send_frame(8'hB4, DIV_FAST, 1'b1);
        checkpoint("receive after reset");

        $display("[PASS] UART RX complete: %0d bytes checked",
                 received_count);
        $finish;
    end

    initial begin
        #100_000_000;
        $fatal(1, "Simulation timeout");
    end

endmodule
