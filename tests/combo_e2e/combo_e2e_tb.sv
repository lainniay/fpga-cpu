`timescale 1ns/1ps
module combo_e2e_tb;
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
    reg [7:0] tx_byte;
    integer bp_req_count = 0;
    integer bp_hit_count = 0;
    integer bp_taken_count = 0;
    integer bp_mispredict_count = 0;
    integer ic_req_count = 0;
    integer ic_hit_count = 0;
    integer ic_miss_count = 0;

    wire bp_pred_hit = soc_lite.cpu.u_if_stage.pred_hit;
    wire bp_pred_taken = soc_lite.cpu.u_if_stage.pred_taken;
    wire bp_new_req = soc_lite.cpu.u_if_stage.new_req_valid;
    wire bp_mispredict = soc_lite.cpu.u_if_stage.mispredict;
    wire ic_req_valid = soc_lite.cpu.u_if_stage.u_inst_fetch_mem.u_icache.req_valid;
    wire ic_req_ready = soc_lite.cpu.u_if_stage.u_inst_fetch_mem.u_icache.req_ready;
    wire ic_query_hit = soc_lite.cpu.u_if_stage.u_inst_fetch_mem.u_icache.query_hit;

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
                if (bp_hit_count == 0 || bp_taken_count == 0 || bp_mispredict_count == 0)
                    $fatal(1, "TEST%0d BP counters hit=%0d taken=%0d mis=%0d",
                           test_id, bp_hit_count, bp_taken_count, bp_mispredict_count);
                if (ic_hit_count == 0 || ic_miss_count == 0)
                    $fatal(1, "TEST%0d ICache counters hit=%0d miss=%0d",
                           test_id, ic_hit_count, ic_miss_count);
                $display("PASS: combo_e2e test%0d tx=%0d bp_hit=%0d bp_mis=%0d ic_hit=%0d ic_miss=%0d",
                         test_id, tx_count, bp_hit_count, bp_mispredict_count,
                         ic_hit_count, ic_miss_count);
                $finish;
            end
            if (status == 8'hfe)
                $fatal(1, "TEST%0d CPU firmware reported failure", test_id);
        end
    endtask

    initial begin
        if (!$value$plusargs("TEST=%d", test_id)) $fatal(1, "missing +TEST=<1..5>");
        case (test_id)
            1: begin
                exp_len = 3;
                exp_data[0] = 8'h11;
                exp_data[1] = 8'h22;
                exp_data[2] = 8'h33;
            end
            2: begin
                exp_len = 2;
                exp_data[0] = 8'haa;
                exp_data[1] = 8'h55;
            end
            3: begin exp_len = 1; exp_data[0] = 8'h0a; end
            4: begin
                exp_len = 3;
                exp_data[0] = 8'h11;
                exp_data[1] = 8'h22;
                exp_data[2] = 8'h33;
            end
            5: begin
                exp_len = 4;
                exp_data[0] = 8'h00;
                exp_data[1] = 8'h01;
                exp_data[2] = 8'h00;
                exp_data[3] = 8'h01;
            end
            default: $fatal(1, "unknown TEST=%0d", test_id);
        endcase
    end

    initial begin
        repeat (5) @(posedge clk);
        #1 resetn = 1;
        #10000;
        case (test_id)
            1: begin
                send_byte(8'h11); #20000;
                send_byte(8'h22); #20000;
                send_byte(8'h33); #20000;
                send_byte(8'hff);
            end
            2: begin
                send_byte(8'h01); #20000;
                send_byte(8'h02); #20000;
                send_byte(8'hff);
            end
            3: begin
                send_byte(8'h01); #20000;
                send_byte(8'h02); #20000;
                send_byte(8'h03); #20000;
                send_byte(8'h04);
            end
            4: begin
                send_byte(8'h03); #20000;
                send_byte(8'h11); #20000;
                send_byte(8'h22); #20000;
                send_byte(8'h33);
            end
            5: begin
                send_byte(8'h10); #20000;
                send_byte(8'h11); #20000;
                send_byte(8'h12); #20000;
                send_byte(8'h13); #20000;
                send_byte(8'hff);
            end
        endcase
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
            if (uart_tx !== 1'b1) $fatal(1, "TEST%0d UART stop bit is not high", test_id);
            if (tx_count < 8) tx_data[tx_count] = tx_byte;
            tx_count = tx_count + 1;
        end
    end

    always @(posedge clk) begin
        if (!resetn) begin
            bp_req_count <= 0;
            bp_hit_count <= 0;
            bp_taken_count <= 0;
            bp_mispredict_count <= 0;
            ic_req_count <= 0;
            ic_hit_count <= 0;
            ic_miss_count <= 0;
        end
        else begin
            if (bp_new_req) begin
                bp_req_count <= bp_req_count + 1;
                if (bp_pred_hit) bp_hit_count <= bp_hit_count + 1;
                if (bp_pred_hit && bp_pred_taken) bp_taken_count <= bp_taken_count + 1;
            end
            if (bp_mispredict) bp_mispredict_count <= bp_mispredict_count + 1;
            if (ic_req_valid && ic_req_ready) begin
                ic_req_count <= ic_req_count + 1;
                if (ic_query_hit) ic_hit_count <= ic_hit_count + 1;
                else ic_miss_count <= ic_miss_count + 1;
            end
        end
    end

    always @(posedge clk) begin
        if (soc_lite.u_confreg.write_uart_valid)
            check_result(soc_lite.u_confreg.write_uart_data);
    end

    initial begin
        #1000000;
        $fatal(1, "TEST%0d timeout tx_count=%0d bp_hit=%0d ic_hit=%0d",
               test_id, tx_count, bp_hit_count, ic_hit_count);
    end
endmodule
