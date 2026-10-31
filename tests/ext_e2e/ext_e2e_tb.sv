`timescale 1ns/1ps
module ext_e2e_tb;
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

    task check_result;
        input [7:0] status;
        begin
            if (status == 8'hff) begin
                if (test_id <= 3) begin
                    if (bp_hit_count == 0 || bp_taken_count == 0 ||
                        bp_mispredict_count == 0)
                        $fatal(1, "TEST%0d BP counters hit=%0d taken=%0d mis=%0d",
                               test_id, bp_hit_count, bp_taken_count, bp_mispredict_count);
                end
                else begin
                    if (ic_hit_count == 0 || ic_miss_count == 0)
                        $fatal(1, "TEST%0d ICache counters hit=%0d miss=%0d",
                               test_id, ic_hit_count, ic_miss_count);
                end
                $display("PASS: ext_e2e test%0d bp_req=%0d bp_hit=%0d bp_taken=%0d bp_mis=%0d ic_req=%0d ic_hit=%0d ic_miss=%0d",
                         test_id, bp_req_count, bp_hit_count, bp_taken_count,
                         bp_mispredict_count, ic_req_count, ic_hit_count, ic_miss_count);
                $finish;
            end
            if (status == 8'hfe)
                $fatal(1, "TEST%0d CPU firmware reported failure", test_id);
        end
    endtask

    initial begin
        if (!$value$plusargs("TEST=%d", test_id)) $fatal(1, "missing +TEST=<1..6>");
        if (test_id < 1 || test_id > 6) $fatal(1, "unknown TEST=%0d", test_id);
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

    initial begin
        repeat (5) @(posedge clk);
        #1 resetn = 1;
    end

    always @(posedge clk) begin
        if (soc_lite.u_confreg.write_uart_valid)
            check_result(soc_lite.u_confreg.write_uart_data);
    end

    initial begin
        #300000;
        $fatal(1, "TEST%0d timeout: bp_hit=%0d bp_taken=%0d ic_hit=%0d ic_miss=%0d",
               test_id, bp_hit_count, bp_taken_count, ic_hit_count, ic_miss_count);
    end
endmodule
