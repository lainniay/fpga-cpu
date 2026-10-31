`timescale 1ns/1ps
module uart_e2e_tb;
    localparam integer BIT_NS = 8680;
    localparam integer BIT_CYCLES = 434;

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

    integer test_id;
    integer exp_len = 0;
    reg [7:0] exp_data [0:7];
    reg [7:0] tx_data [0:7];
    integer tx_count = 0;
    integer k;
    reg [7:0] tx_byte_r;

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

    task send_byte;
        input [7:0] data;
        integer i;
        begin
            @(negedge clk);
            uart_rx = 1'b0;
            repeat (BIT_CYCLES) @(negedge clk);
            for (i = 0; i < 8; i = i + 1) begin
                uart_rx = data[i];
                repeat (BIT_CYCLES) @(negedge clk);
            end
            uart_rx = 1'b1;
            repeat (BIT_CYCLES) @(negedge clk);
        end
    endtask

    task send_false_start;
        begin
            @(negedge clk);
            uart_rx = 1'b0;
            repeat (100) @(negedge clk);
            uart_rx = 1'b1;
            repeat (500) @(negedge clk);
        end
    endtask

    task check_result;
        input [7:0] status;
        integer i;
        begin
            if (status == 8'hff) begin
                if (tx_count != exp_len)
                    $fatal(1, "TEST%0d TX count=%0d expected=%0d", test_id, tx_count, exp_len);
                for (i = 0; i < exp_len; i = i + 1) begin
                    if (tx_data[i] !== exp_data[i])
                        $fatal(1, "TEST%0d TX[%0d]=%h expected=%h", test_id, i, tx_data[i], exp_data[i]);
                end
                $display("PASS: uart_e2e test%0d tx_count=%0d", test_id, tx_count);
                $finish;
            end
            if (status == 8'hfe)
                $fatal(1, "TEST%0d CPU firmware reported failure", test_id);
        end
    endtask

    initial begin
        if (!$value$plusargs("TEST=%d", test_id)) $fatal(1, "missing +TEST=<1..10>");
        case (test_id)
            1: begin exp_len = 1; exp_data[0] = 8'h55; end
            2: begin
                exp_len = 4;
                exp_data[0] = 8'h00;
                exp_data[1] = 8'hff;
                exp_data[2] = 8'haa;
                exp_data[3] = 8'h55;
            end
            3: begin exp_len = 1; exp_data[0] = 8'h34; end
            4: exp_len = 0;
            5: exp_len = 0;
            6: exp_len = 0;
            7: exp_len = 0;
            8: begin exp_len = 1; exp_data[0] = 8'hc3; end
            9: exp_len = 0;
            10: begin exp_len = 1; exp_data[0] = 8'h55; end
            default: $fatal(1, "unknown TEST=%0d", test_id);
        endcase
    end

    initial begin
        repeat (5) @(posedge clk);
        #1 resetn = 1;
        #10000;
        case (test_id)
            5: send_byte(8'ha5);
            6: send_byte(8'h5a);
            7: begin
                send_byte(8'h11);
                #100000;
                send_byte(8'h22);
            end
            8: send_byte(8'h3c);
            9: begin
                send_false_start;
                #10000;
                send_byte(8'h7e);
            end
            default: ;
        endcase
    end

    initial begin
        @(posedge resetn);
        repeat (5) @(posedge clk);
        forever begin
            @(negedge uart_tx);
            #(BIT_NS + BIT_NS / 2);
            for (k = 0; k < 8; k = k + 1) begin
                tx_byte_r[k] = uart_tx;
                #BIT_NS;
            end
            if (uart_tx !== 1'b1) $fatal(1, "TEST%0d UART stop bit is not high", test_id);
            if (tx_count < 8) tx_data[tx_count] = tx_byte_r;
            tx_count = tx_count + 1;
        end
    end

    always @(posedge clk) begin
        if (soc_lite.u_confreg.write_uart_valid)
            check_result(soc_lite.u_confreg.write_uart_data);
    end

    initial begin
        #500000;
        $fatal(1, "TEST%0d timeout: tx_count=%0d", test_id, tx_count);
    end
endmodule
