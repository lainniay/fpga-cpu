`timescale 1ns/1ps
module tb_uart_tx;
    reg clk = 0;
    always #5 clk = ~clk;
    reg reset = 1;
    reg [1:0] baud_sel = 1;
    reg tx_start = 0;
    reg [7:0] tx_data = 0;
    wire tx_busy, uart_tx;
    uart_tx dut (.*);
    integer checks = 0;
    integer frames = 0;
    integer phase = 0;
    integer i;
    reg [31:0] rng = 32'h12a59c73;

    task automatic check_pin(input bit busy_expected, input bit pin_expected);
        begin
            checks = checks + 1;
            if ({tx_busy, uart_tx} !== {busy_expected, pin_expected})
                $fatal(1, "TX mismatch phase=%0d frame=%0d time=%0t got=%b/%b expected=%b/%b",
                       phase, frames, $time, tx_busy, uart_tx, busy_expected, pin_expected);
        end
    endtask

    task automatic send_frame(input [7:0] data, input [1:0] rate,
                              input bit perturb, input bit hold_request_at_end);
        integer divisor, elapsed, slot;
        bit expected_pin;
        begin
            divisor = rate == 0 ? 10417 : 868;
            @(negedge clk);
            check_pin(0, 1);
            baud_sel = rate;
            tx_data = data;
            tx_start = 1;
            @(posedge clk); #1;
            check_pin(1, 0); // No idle cycle after accepting a byte.
            for (elapsed = 1; elapsed <= 10 * divisor; elapsed = elapsed + 1) begin
                @(negedge clk);
                if (elapsed == 1) begin
                    tx_start = 0;
                    if (perturb) begin
                        tx_data = ~data;
                        baud_sel = rate == 0 ? 1 : 0;
                    end
                end
                if (perturb && elapsed == divisor * 3) tx_start = 1;
                if (perturb && elapsed == divisor * 4) tx_start = 0;
                if (hold_request_at_end && elapsed == 10 * divisor - 2) tx_start = 1;
                @(posedge clk); #1;
                slot = elapsed / divisor;
                if (slot == 0) expected_pin = 0;
                else if (slot < 9) expected_pin = data[slot - 1];
                else expected_pin = 1;
                check_pin(elapsed < 10 * divisor, expected_pin);
            end
            frames = frames + 1;
            $display("PASS TX frame=%0d data=%h baud=%0d clocks=%0d perturb=%0d",
                     frames, data, rate == 0 ? 9600 : 115200, 10 * divisor, perturb);
        end
    endtask

    task automatic abort_frame(input integer elapsed);
        begin
            @(negedge clk);
            baud_sel = 1;
            tx_data = 8'h00;
            tx_start = 1;
            @(posedge clk); #1; check_pin(1, 0);
            @(negedge clk); tx_start = 0;
            repeat (elapsed) @(posedge clk);
            @(negedge clk);
            reset = 1;
            tx_start = 1; // Reset wins over a new request.
            #1;
            if (tx_busy !== 1'b1) $fatal(1, "TX reset must be synchronous");
            @(posedge clk); #1; check_pin(0, 1);
            @(negedge clk); reset = 0; tx_start = 0;
            repeat (3) begin @(posedge clk); #1; check_pin(0, 1); end
        end
    endtask

    initial begin
        @(posedge clk); #1; check_pin(0, 1);
        @(negedge clk); reset = 0;
        repeat (5) begin @(posedge clk); #1; check_pin(0, 1); end
        phase = 1;
        send_frame('h55, 1, 1, 1);
        // Request remains high across completion: acceptance is level based on the next idle edge.
        send_frame('ha3, 1, 1, 0);
        send_frame('h00, 1, 0, 0);
        send_frame('hff, 1, 0, 0);
        send_frame('h80, 1, 0, 0);
        send_frame('h01, 1, 0, 0);
        @(negedge clk); tx_start = 0;
        repeat (9000) begin @(posedge clk); #1; check_pin(0, 1); end
        $display("PASS TX 115200 LSB order, exact bit lengths, complete stop, busy rejection, no queued byte");

        phase = 2;
        send_frame('ha5, 0, 1, 0);
        send_frame('h00, 0, 0, 0);
        send_frame('hff, 0, 0, 0);
        send_frame('h01, 0, 1, 0);
        send_frame('h80, 0, 0, 0);
        $display("PASS TX 9600 timing and latched data/baud during transmission");

        phase = 3;
        abort_frame(100);  // Start bit.
        abort_frame(3000); // Data bits.
        abort_frame(8000); // Stop bit (starts at clock 7812).
        send_frame('h3c, 1, 0, 0);
        $display("PASS TX synchronous reset in start/data/stop and recovery");

        phase = 4;
        for (i = 0; i < 16; i = i + 1) begin
            rng = rng ^ (rng << 13);
            rng = rng ^ (rng >> 17);
            rng = rng ^ (rng << 5);
            send_frame(rng[7:0], 1, 1, 0);
        end
        $display("PASS tb_uart_tx frames=%0d checks=%0d time=%0t", frames, checks, $time);
        $finish;
    end
    initial begin #30000000; $fatal(1, "TX timeout"); end
endmodule
