`timescale 1ns/1ps
module tb_branch_predictor;
    reg clk = 0;
    always #5 clk = ~clk;
    reg reset = 1;
    reg [31:0] query_pc = 0;
    wire pred_hit, pred_taken;
    wire [31:0] pred_target;
    reg upd_valid = 0;
    reg [31:0] upd_pc = 0;
    reg upd_taken = 0;
    reg [31:0] upd_target = 0;
    branch_predictor dut (.*);

    bit occupied [0:63];
    reg [31:0] owner_pc [0:63];
    reg [31:0] destination [0:63];
    integer confidence [0:63];
    integer checks = 0;
    integer phase = 0;
    integer i, j, idx;
    reg [31:0] rng = 32'h519ac7e3;
    reg [31:0] random_pc;

    task automatic check_query;
        integer slot;
        bit hit, taken;
        reg [31:0] target;
        begin
            slot = (query_pc / 4) % 64;
            hit = occupied[slot] && owner_pc[slot] == (query_pc & 32'hfffffffc);
            taken = hit && confidence[slot] >= 2;
            target = hit ? destination[slot] : 0;
            checks = checks + 1;
            if ({pred_hit, pred_taken, pred_target} !== {hit, taken, target})
                $fatal(1, "BP mismatch phase=%0d t=%0t PC=%h got=%b/%b/%h expected=%b/%b/%h",
                       phase, $time, query_pc, pred_hit, pred_taken, pred_target, hit, taken, target);
        end
    endtask

    task automatic model_update;
        integer slot, k;
        begin
            if (reset) begin
                for (k = 0; k < 64; k = k + 1) occupied[k] = 0;
            end else if (upd_valid) begin
                slot = (upd_pc / 4) % 64;
                if (!occupied[slot] || owner_pc[slot] != (upd_pc & 32'hfffffffc))
                    confidence[slot] = upd_taken ? 2 : 1;
                else begin
                    confidence[slot] = confidence[slot] + (upd_taken ? 1 : -1);
                    if (confidence[slot] > 3) confidence[slot] = 3;
                    if (confidence[slot] < 0) confidence[slot] = 0;
                end
                occupied[slot] = 1;
                owner_pc[slot] = upd_pc & 32'hfffffffc;
                destination[slot] = upd_target;
            end
        end
    endtask

    // Check old results before the edge and new results after nonblocking updates.
    task automatic cycle(input bit rst, input bit enable, input [31:0] pc,
                         input bit taken, input [31:0] target, input [31:0] query);
        begin
            @(negedge clk);
            reset = rst;
            upd_valid = enable;
            upd_pc = pc;
            upd_taken = taken;
            upd_target = target;
            query_pc = query;
            #1; check_query();
            @(posedge clk);
            model_update();
            #1; check_query();
        end
    endtask

    task automatic expect_direction(input bit hit, input bit taken, input [31:0] target);
        begin
            checks = checks + 1;
            if ({pred_hit, pred_taken, pred_target} !== {hit, taken, target})
                $fatal(1, "BP directed expectation failed at %0t", $time);
        end
    endtask

    initial begin
        @(posedge clk); #1;
        check_query();
        phase = 1;
        for (i = 0; i < 64; i = i + 1)
            cycle(0, 0, 0, 0, 0, 32'h100 + i * 4);
        $display("PASS BP reset: all 64 entries miss with zero outputs");

        phase = 2;
        cycle(0, 1, 'h100, 1, 'h200, 'h100);
        expect_direction(1, 1, 'h200); // New entry: weak taken (2).
        for (i = 0; i < 5; i = i + 1)
            cycle(0, 1, 'h100, 1, 'h200, 'h100);
        cycle(0, 1, 'h100, 0, 'h240, 'h100);
        expect_direction(1, 1, 'h240); // 3 -> 2, target changes even when not taken.
        cycle(0, 1, 'h100, 0, 'h240, 'h100);
        expect_direction(1, 0, 'h240); // 2 -> 1.
        for (i = 0; i < 5; i = i + 1)
            cycle(0, 1, 'h100, 0, 'h240, 'h100);
        cycle(0, 1, 'h100, 1, 'h240, 'h100);
        expect_direction(1, 0, 'h240); // 0 -> 1, no underflow.
        cycle(0, 1, 'h100, 1, 'h240, 'h100);
        expect_direction(1, 1, 'h240); // 1 -> 2.
        $display("PASS BP counter transitions, both saturation bounds and NT target update");

        phase = 3;
        cycle(0, 1, 'h100, 1, 'h240, 'h100); // Evicted entry is strongly taken.
        cycle(0, 1, 'h200, 0, 'h800, 'h200); // Same index, new tag.
        expect_direction(1, 0, 'h800);
        cycle(0, 0, 'h100, 1, 'h900, 'h100);
        expect_direction(0, 0, 0);
        cycle(0, 1, 'h200, 1, 'h804, 'h200);
        expect_direction(1, 1, 'h804); // Replacement began at 1, not old history.
        cycle(0, 1, 'h300, 1, 'h900, 'h300);
        cycle(0, 1, 'h300, 0, 'h900, 'h300);
        expect_direction(1, 0, 'h900); // Taken replacement began at 2.
        $display("PASS BP conflict eviction and fresh history in both directions");

        phase = 4;
        for (i = 0; i < 64; i = i + 1)
            cycle(0, 1, 'h1000 + i * 4, i % 2, 'h2000 + i * 8, 'h1000 + i * 4);
        for (i = 0; i < 64; i = i + 1)
            cycle(0, 0, 'h8000, 1, 'hdeadbeef, 'h1000 + i * 4);
        $display("PASS BP independent entries, disabled updates and continuous valid updates");

        phase = 5;
        cycle(1, 1, 'h1000, 1, 'hffff, 'h1000);
        expect_direction(0, 0, 0);
        for (i = 0; i < 64; i = i + 1)
            cycle(0, 0, 0, 0, 0, 'h1000 + i * 4);
        $display("PASS BP reset priority over training and full invalidation");

        phase = 6;
        for (j = 0; j < 2000; j = j + 1) begin
            rng = rng ^ (rng << 13);
            rng = rng ^ (rng >> 17);
            rng = rng ^ (rng << 5);
            idx = rng[5:0];
            random_pc = {22'd0, rng[7:6], 8'd0} + idx * 4;
            cycle(j % 251 == 250, rng[8], random_pc, rng[9], rng & 32'hfffffffc,
                  j % 2 == 0 ? random_pc : (rng & 32'h000003fc));
        end
        $display("PASS BP deterministic randomized scoreboard: 2000 cycles, seed=519ac7e3");
        $display("PASS tb_branch_predictor checks=%0d time=%0t", checks, $time);
        $finish;
    end
    initial begin #100000; $fatal(1, "BP timeout"); end
endmodule
