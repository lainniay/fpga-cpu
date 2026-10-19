`timescale 1ns / 1ps

// NOTE: ex9, 直接驱动 CSR 架构访问端口, 不修改 DUT 内部状态.
module ex9_topic2_csr_tb;
    localparam [13:0] ESTAT = 14'h0005, ERA = 14'h0006;
    localparam [13:0] TID = 14'h0040, TCFG = 14'h0041;
    localparam [13:0] TVAL = 14'h0042, TICLR = 14'h0044;
    reg clk = 1'b0;
    always #5 clk = ~clk;
    reg reset = 1'b1, csr_re = 1'b0, csr_we = 1'b0;
    reg wb_ex = 1'b0, ertn_flush = 1'b0;
    reg [13:0] csr_addr = 14'b0;
    reg [31:0] csr_wmask = 32'b0, csr_wvalue = 32'b0;
    reg [31:0] wb_pc = 32'h1c001234;
    reg [5:0] wb_ecode = 6'h0b;
    reg [8:0] wb_esubcode = 9'h123;
    wire [31:0] csr_rvalue, ex_entry, ertn_entry;
    wire [31:0] expected_cfg, expected_remaining, expiries, reloads;
    wire expected_pending;
    wire effective_write = csr_we && !wb_ex && !ertn_flush;
    reg [1:0] expected_software = 2'b0;
    reg [5:0] expected_code = 6'b0;
    reg [8:0] expected_subcode = 9'b0;
    reg [31:0] expected_tid = 32'b0, expected_era = 32'b0;
    wire [31:0] expected_status = {1'b0, expected_subcode, expected_code,
        4'b0, expected_pending, 9'b0, expected_software};
    integer steps = 0, passed = 0;
    string group_name = "startup";
    reg [31:0] held_value, previous_expiries;

    CSR dut (
        .clk(clk), .reset(reset), .csr_re(csr_re), .csr_addr(csr_addr),
        .csr_rvalue(csr_rvalue), .csr_we(csr_we), .csr_wmask(csr_wmask),
        .csr_wvalue(csr_wvalue), .wb_ex(wb_ex), .wb_pc(wb_pc),
        .wb_ecode(wb_ecode), .wb_esubcode(wb_esubcode),
        .ertn_flush(ertn_flush), .ex_entry(ex_entry), .ertn_entry(ertn_entry)
    );
    ex9_timer_reference reference_timer (
        .clk(clk), .reset(reset), .write_enable(effective_write),
        .address(csr_addr), .write_mask(csr_wmask), .write_value(csr_wvalue),
        .configuration(expected_cfg), .remaining(expected_remaining),
        .pending(expected_pending), .expiry_count(expiries), .reload_count(reloads)
    );

    // NOTE: ex9, 同一异常状态寄存器中, 软件中断位与异常码分别核对.
    always @(posedge clk) begin
        if (reset) begin
            expected_software <= 2'b0;
            expected_code <= 6'b0;
            expected_subcode <= 9'b0;
            expected_tid <= 32'b0;
            expected_era <= 32'b0;
        end else if (wb_ex) begin
            expected_code <= wb_ecode;
            expected_subcode <= wb_esubcode;
            expected_era <= wb_pc;
        end else if (!ertn_flush && csr_we) begin
            case (csr_addr)
                ESTAT: expected_software <= (expected_software & ~csr_wmask[1:0])
                                           | (csr_wvalue[1:0] & csr_wmask[1:0]);
                TID: expected_tid <= (expected_tid & ~csr_wmask)
                                    | (csr_wvalue & csr_wmask);
                ERA: expected_era <= (expected_era & ~csr_wmask)
                                    | (csr_wvalue & csr_wmask);
                default: begin end
            endcase
        end
    end

    task automatic fail(input string message);
        $display("[FAIL] CSR/%s step=%0d: %s", group_name, steps, message);
        $fatal(1, "ex9 Topic 2 CSR test failed");
    endtask

    task automatic require_value(input [31:0] actual, expected,
                                 input string description);
        if (actual !== expected)
            fail($sformatf("%s actual=%08h expected=%08h", description, actual, expected));
    endtask

    task automatic expect_read(input [13:0] number, input [31:0] expected);
        csr_re = 1'b1;
        csr_addr = number;
        #0.1;
        require_value(csr_rvalue, expected, $sformatf("CSR[%04h]", number));
    endtask

    task automatic check_state;
        reg [13:0] saved_address;
        saved_address = csr_addr;
        expect_read(TCFG, expected_cfg);
        expect_read(TVAL, expected_remaining);
        expect_read(ESTAT, expected_status);
        expect_read(TICLR, 32'b0);
        expect_read(TID, expected_tid);
        expect_read(ERA, expected_era);
        csr_addr = saved_address;
        csr_re = 1'b0;
        #0.1;
        require_value(csr_rvalue, 32'b0, "read disabled");
    endtask

    // NOTE: ex9, 输入在下降沿改变, 检查在上升沿非阻塞赋值生效后进行.
    task automatic step(input bit writing, input [13:0] number,
                        input [31:0] mask, value, input bit exception_event, return_event);
        @(negedge clk);
        csr_we = writing;
        csr_addr = number;
        csr_wmask = mask;
        csr_wvalue = value;
        wb_ex = exception_event;
        ertn_flush = return_event;
        @(posedge clk);
        #1;
        steps = steps + 1;
        check_state();
    endtask

    task automatic write_csr(input [13:0] number, input [31:0] mask, value);
        step(1'b1, number, mask, value, 1'b0, 1'b0);
    endtask

    task automatic idle(input integer count);
        for (integer n = 0; n < count; n = n + 1)
            step(1'b0, 14'b0, 32'b0, 32'b0, 1'b0, 1'b0);
    endtask

    task automatic begin_group(input string name);
        group_name = name;
        reset = 1'b1;
        idle(2);
        reset = 1'b0;
    endtask

    task automatic pass_group;
        $display("[PASS] CSR/%s", group_name);
        passed = passed + 1;
    endtask

    initial begin
        if ($test$plusargs("WAVES")) begin
            $dumpfile("ex9_topic2_csr.vcd");
            $dumpvars(0, ex9_topic2_csr_tb);
        end

        begin_group("reset, read-only fields and 32-bit masks");
        idle(4);
        require_value(expected_remaining, 32'hffffffff, "reset stop value");
        write_csr(TCFG, 32'hffffffff, 32'h89abcde0);
        idle(2);
        write_csr(TCFG, 32'h00ff0000, 32'h00550000);
        write_csr(TVAL, 32'hffffffff, 32'h12345678);
        write_csr(TICLR, 32'hffffffff, 32'hffffffff);
        write_csr(TID, 32'hffffffff, 32'hfedcba98);
        write_csr(TCFG, 32'hffffffff, 32'hfffffffd);
        require_value(expected_remaining, 32'hfffffffc, "full-width initial value");
        idle(3);
        step(1'b0, TCFG, 32'hffffffff, 32'b0, 1'b0, 1'b0);
        write_csr(TCFG, 32'h00000001, 32'b0);
        held_value = expected_remaining;
        idle(5);
        require_value(expected_remaining, held_value, "disabled hold");
        pass_group();

        begin_group("one-shot expiry, held request and write-one clear");
        write_csr(TCFG, 32'hffffffff, 32'h00000009);
        require_value(expected_remaining, 32'd8, "initial load");
        idle(8);
        require_value(expected_remaining, 32'b0, "zero before expiry edge");
        require_value({31'b0, expected_pending}, 32'b0, "not expired early");
        idle(1);
        require_value(expected_remaining, 32'hffffffff, "one-shot stops");
        require_value(expiries, 32'd1, "one expiry");
        idle(15);
        require_value(expiries, 32'd1, "no repeated one-shot event");
        write_csr(TICLR, 32'hffffffff, 32'b0);
        write_csr(TICLR, 32'b0, 32'd1);
        write_csr(TICLR, 32'hfffffffe, 32'hffffffff);
        write_csr(TID, 32'hffffffff, 32'd1);
        write_csr(ESTAT, 32'hffffffff, 32'b0);
        require_value({31'b0, expected_pending}, 32'd1, "invalid clears preserve request");
        write_csr(TCFG, 32'hffffffff, 32'b0);
        require_value({31'b0, expected_pending}, 32'd1, "disable preserves request");
        write_csr(TICLR, 32'd1, 32'd1);
        idle(4);
        require_value({31'b0, expected_pending}, 32'b0, "valid clear persists");
        pass_group();

        begin_group("periodic reload repeats and is independent of request");
        write_csr(TCFG, 32'hffffffff, 32'h0000000b);
        idle(27);
        require_value(reloads, 32'd3, "three periodic reloads without clearing");
        require_value({31'b0, expected_pending}, 32'd1, "periodic request held");
        write_csr(TICLR, 32'd1, 32'd1);
        require_value({31'b0, expected_pending}, 32'b0, "periodic clear between events");
        idle(8);
        require_value(reloads, 32'd4, "next reload after clear");
        require_value({31'b0, expected_pending}, 32'd1, "next expiry sets request again");
        write_csr(TCFG, 32'd1, 32'b0);
        held_value = expected_remaining;
        previous_expiries = expiries;
        idle(20);
        require_value(expected_remaining, held_value, "periodic disabled hold");
        require_value(expiries, previous_expiries, "no expiry while disabled");
        pass_group();

        begin_group("reconfigure, preserved enable, zero mask and restart");
        write_csr(TCFG, 32'hffffffff, 32'h00000041);
        idle(3);
        write_csr(TCFG, 32'hfffffffc, 32'h00000008);
        require_value(expected_remaining, 32'd8, "new value with enable mask zero");
        idle(3);
        write_csr(TCFG, 32'b0, 32'hffffffff);
        require_value(expected_remaining, 32'd8, "enabled zero-mask write reloads");
        write_csr(TCFG, 32'd2, 32'd2);
        require_value(expected_remaining, 32'd8, "mode-only update reloads");
        write_csr(TCFG, 32'd1, 32'b0);
        require_value(expected_remaining, 32'd8, "disable does not decrement once more");
        idle(5);
        write_csr(TCFG, 32'd1, 32'd1);
        require_value(expected_remaining, 32'd8, "enable restarts from configured value");
        idle(9);
        write_csr(TCFG, 32'hffffffff, 32'h00000011);
        require_value({31'b0, expected_pending}, 32'd1, "reconfigure does not clear request");
        require_value(expected_remaining, 32'd16, "reconfigure uses new initial value");
        pass_group();

        begin_group("zero initial value, collisions and exception field isolation");
        write_csr(TCFG, 32'hffffffff, 32'd1);
        require_value(expected_remaining, 32'b0, "zero initial load");
        write_csr(TICLR, 32'd1, 32'd1);
        require_value({31'b0, expected_pending}, 32'd1, "expiry wins over clear");
        require_value(expected_remaining, 32'hffffffff, "zero one-shot stops");
        write_csr(TICLR, 32'd1, 32'd1);
        write_csr(TCFG, 32'hffffffff, 32'd3);
        write_csr(TICLR, 32'd1, 32'd1);
        idle(3);
        require_value(reloads, 32'd4, "zero periodic reloads every edge");
        write_csr(TCFG, 32'hffffffff, 32'b0);
        write_csr(TICLR, 32'd1, 32'd1);
        write_csr(ESTAT, 32'hffffffff, 32'hffffffff);
        require_value({31'b0, expected_pending}, 32'b0, "ESTAT write cannot set timer bit");
        write_csr(TCFG, 32'hffffffff, 32'h00000011);
        step(1'b1, TCFG, 32'hffffffff, 32'h00000001, 1'b1, 1'b0);
        require_value(expected_remaining, 32'd15, "exception suppresses config but not counting");
        step(1'b1, TCFG, 32'hffffffff, 32'b0, 1'b0, 1'b1);
        require_value(expected_remaining, 32'd14, "return suppresses config but not counting");
        idle(15);
        step(1'b1, TICLR, 32'd1, 32'd1, 1'b1, 1'b0);
        step(1'b1, TICLR, 32'd1, 32'd1, 1'b0, 1'b1);
        require_value({31'b0, expected_pending}, 32'd1, "exception and return do not clear request");
        write_csr(ESTAT, 32'd1, 32'b0);
        write_csr(TICLR, 32'd1, 32'd1);
        // 旧计数恰为零时重新配置: 旧到期事件仍须保留.
        write_csr(TCFG, 32'hffffffff, 32'd1);
        write_csr(TCFG, 32'hffffffff, 32'h00000009);
        require_value(expected_remaining, 32'd8, "collision loads new configuration");
        require_value({31'b0, expected_pending}, 32'd1, "old expiry survives reconfiguration");
        reset = 1'b1;
        idle(1);
        reset = 1'b0;
        idle(2);
        require_value(expected_cfg, 32'b0, "reset clears configuration");
        require_value(expected_remaining, 32'hffffffff, "reset stops active timer");
        pass_group();

        if (passed != 5) fail("not all groups ran");
        $display("ALL PASS: ex9 Topic 2 CSR (5/5 groups, %0d checked edges)", steps);
        $finish;
    end

    initial begin
        #100000;
        $fatal(1, "ex9 Topic 2 CSR timeout");
    end
endmodule
