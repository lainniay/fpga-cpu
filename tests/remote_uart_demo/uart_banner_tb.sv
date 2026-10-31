`timescale 1ns/1ps
module uart_banner_tb;
    localparam integer BIT_NS = 8680;

    reg clk = 0;
    always #10 clk = ~clk;

    reg resetn = 0;
    reg uart_rx = 1;
    reg [7:0] switch = 8'hff;
    reg [3:0] btn_key_row = 4'd0;
    reg [1:0] btn_step = 2'd3;
    wire uart_tx;
    wire [15:0] led;
    wire [1:0] led_rg0;
    wire [1:0] led_rg1;
    wire [7:0] num_csn;
    wire [6:0] num_a_g;
    wire [31:0] num_data;
    wire [3:0] btn_key_col;

    reg [7:0] expected [0:8];
    reg [7:0] tx_byte;
    integer tx_count = 0;
    integer k;

    soc_lite_top #(.SIMULATION(1'b1)) soc_lite (
        .resetn(resetn),
        .clk(clk),
        .uart_rx(uart_rx),
        .uart_tx(uart_tx),
        .led(led),
        .led_rg0(led_rg0),
        .led_rg1(led_rg1),
        .num_csn(num_csn),
        .num_a_g(num_a_g),
        .num_data(num_data),
        .switch(switch),
        .btn_key_col(btn_key_col),
        .btn_key_row(btn_key_row),
        .btn_step(btn_step)
    );

    initial begin
        expected[0] = 8'h55;
        expected[1] = 8'h41;
        expected[2] = 8'h52;
        expected[3] = 8'h54;
        expected[4] = 8'h20;
        expected[5] = 8'h4f;
        expected[6] = 8'h4b;
        expected[7] = 8'h0d;
        expected[8] = 8'h0a;
    end

    initial begin
        repeat (5) @(posedge clk);
        #1 resetn = 1;
    end

    initial begin
        @(posedge resetn);
        repeat (5) @(posedge clk);
        forever begin
            @(negedge uart_tx);
            #(BIT_NS + BIT_NS / 2);
            for (k = 0; k < 8; k = k + 1) begin
                tx_byte[k] = uart_tx;
                #BIT_NS;
            end
            if (uart_tx !== 1'b1) $fatal(1, "UART stop bit is not high");
            if (tx_byte !== expected[tx_count])
                $fatal(1, "banner byte %0d=%h expected=%h", tx_count, tx_byte, expected[tx_count]);
            tx_count = tx_count + 1;
            if (tx_count == 9) begin
                $display("PASS: UART banner %s", "UART OK");
                $finish;
            end
        end
    end

    initial begin
        #1500000;
        $fatal(1, "UART banner timeout: tx_count=%0d", tx_count);
    end
endmodule
