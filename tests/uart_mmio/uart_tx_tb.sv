`timescale 1ns/1ps

module uart_tx_tb;
    localparam integer CLK_NS = 10;
    localparam integer DIV_SLOW = 10417;
    localparam integer DIV_FAST = 868;

    reg clk = 1'b0;
    always #(CLK_NS / 2) clk = ~clk;
    reg reset = 1'b1;
    reg [1:0] baud_sel = 2'd1;
    reg tx_start = 1'b0;
    reg [7:0] tx_data = 8'd0;
    wire tx_busy;
    wire serial_out;
    reg [7:0] patterns [0:5];
    integer mode;
    integer i;
    integer checked_frames = 0;

    uart_tx dut (
        .clk(clk), .reset(reset), .baud_sel(baud_sel),
        .tx_start(tx_start), .tx_data(tx_data),
        .tx_busy(tx_busy), .uart_tx(serial_out)
    );

    task automatic reset_tx;
        begin
            @(negedge clk);
            reset = 1'b1;
            tx_start = 1'b0;
            repeat (4) @(negedge clk);
            reset = 1'b0;
            repeat (2) @(negedge clk);
            if (tx_busy !== 1'b0 || serial_out !== 1'b1)
                $fatal(1, "TX reset/idle outputs incorrect");
        end
    endtask

    // Check all N clock periods in every bit, including the full stop bit.
    task automatic check_frame(
        input [7:0] value,
        input [1:0] rate,
        input integer bit_cycles
    );
        begin
            @(negedge clk);
            baud_sel = rate;
            tx_data = value;
            tx_start = 1'b1;
            @(posedge clk);
            #1;
            if (tx_busy !== 1'b1 || serial_out !== 1'b0)
                $fatal(1, "TX did not accept the byte on the request edge");

            fork
                begin : check_waveform
                    integer bit_no;
                    integer tick;
                    reg expected_level;
                    for (bit_no = 0; bit_no < 10; bit_no = bit_no + 1) begin
                        if (bit_no == 0)
                            expected_level = 1'b0;
                        else if (bit_no == 9)
                            expected_level = 1'b1;
                        else
                            expected_level = value[bit_no - 1];

                        for (tick = 0; tick < bit_cycles; tick = tick + 1) begin
                            if (tx_busy !== 1'b1 ||
                                serial_out !== expected_level)
                                $fatal(1,
                                    "TX waveform: rate=%0d data=%02h bit=%0d tick=%0d busy=%b pin=%b expected=%b",
                                    rate, value, bit_no, tick,
                                    tx_busy, serial_out, expected_level);
                            @(posedge clk);
                            #1;
                        end
                    end
                    if (tx_busy !== 1'b0 || serial_out !== 1'b1)
                        $fatal(1, "TX did not finish after exactly 10 bit periods");
                end

                begin : disturb_inputs
                    @(negedge clk);
                    tx_start = 1'b0;
                    tx_data = ~value;
                    baud_sel = (rate == 2'd0) ? 2'd1 : 2'd0;

                    // A new request during the current frame must be ignored.
                    repeat (2 * bit_cycles) @(negedge clk);
                    tx_start = 1'b1;
                    @(negedge clk);
                    tx_start = 1'b0;
                end
            join

            repeat (4) begin
                @(posedge clk);
                #1;
                if (tx_busy !== 1'b0 || serial_out !== 1'b1)
                    $fatal(1, "TX queued a request received while busy");
            end
            checked_frames = checked_frames + 1;
            $display("[PASS] TX rate=%0d data=%02h", rate, value);
        end
    endtask

    initial begin
        if ($test$plusargs("wave")) begin
            $dumpfile("build/uart_mmio/uart_tx.vcd");
            $dumpvars(0, uart_tx_tb);
        end
        patterns[0] = 8'h00;
        patterns[1] = 8'hFF;
        patterns[2] = 8'h55;
        patterns[3] = 8'hAA;
        patterns[4] = 8'h81;
        patterns[5] = 8'h41;

        reset_tx();
        for (mode = 0; mode < 2; mode = mode + 1)
            for (i = 0; i < 6; i = i + 1)
                check_frame(patterns[i], (mode == 0) ? 2'd0 : 2'd1,
                            (mode == 0) ? DIV_SLOW : DIV_FAST);

        // Synchronous reset must abort a frame, even with start asserted.
        @(negedge clk);
        baud_sel = 2'd1;
        tx_data = 8'h55;
        tx_start = 1'b1;
        @(negedge clk);
        tx_start = 1'b0;
        repeat (3 * DIV_FAST) @(negedge clk);
        reset = 1'b1;
        tx_start = 1'b1;
        repeat (4) begin
            @(posedge clk);
            #1;
            if (tx_busy !== 1'b0 || serial_out !== 1'b1)
                $fatal(1, "TX reset did not cancel the frame");
        end
        @(negedge clk);
        tx_start = 1'b0;
        reset = 1'b0;
        repeat (8) @(negedge clk);
        if (tx_busy !== 1'b0 || serial_out !== 1'b1)
            $fatal(1, "TX produced stale traffic after reset");
        $display("[PASS] TX reset cancels frame and overrides start");
        check_frame(8'hB4, 2'd1, DIV_FAST);

        $display("[PASS] UART TX complete: %0d frames checked", checked_frames);
        $finish;
    end

    initial begin
        #100_000_000;
        $fatal(1, "UART TX timeout");
    end
endmodule
