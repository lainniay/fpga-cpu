`timescale 1ns/1ps

// NOTE: ex9 独立小程序驱动完整 CPU, 不改官方镜像或参考比较器.
module ex9_1_tb;
    reg clk = 0;
    always #5 clk = ~clk;
    reg resetn = 0;
    wire inst_en, data_en;
    wire [3:0] inst_we, data_we, debug_we;
    wire [31:0] inst_addr, inst_wdata, data_addr, data_wdata;
    reg [31:0] inst_rdata, data_rdata;
    wire [31:0] debug_pc, debug_data;
    wire [4:0] debug_reg;
    reg [31:0] imem [0:4095];
    reg [31:0] dmem [0:1023];
    localparam [31:0] BASE = 32'h1c000000;
    localparam [31:0] HANDLER = BASE + 32'h1000;
    localparam [31:0] RESUME = BASE + 32'h300;
    integer cases = 0;
    integer offset;
    reg [7:0] sample_byte;
    reg [15:0] sample_half;
    reg [31:0] lane_mask;
    integer cycles, i, lane;
    integer traps;
    reg armed = 0;
    reg [5:0] expected_code;
    reg [31:0] expected_pc;
    reg [31:0] expected_badv;
    reg [255:0] case_name;

    mycpu_top dut (
        .clk(clk), .resetn(resetn),
        .inst_sram_en(inst_en), .inst_sram_we(inst_we),
        .inst_sram_addr(inst_addr), .inst_sram_wdata(inst_wdata),
        .inst_sram_rdata(inst_rdata),
        .data_sram_en(data_en), .data_sram_we(data_we),
        .data_sram_addr(data_addr), .data_sram_wdata(data_wdata),
        .data_sram_rdata(data_rdata),
        .debug_wb_pc(debug_pc), .debug_wb_rf_we(debug_we),
        .debug_wb_rf_wnum(debug_reg), .debug_wb_rf_wdata(debug_data)
    );

    // NOTE: ex9 同步读 SRAM, 停止请求时保留旧读数据, 用于暴露 ADEF 的旧指令污染.
    always @(posedge clk) begin
        if (inst_en) inst_rdata <= imem[inst_addr[13:2]];
        if (data_en) begin
            data_rdata <= dmem[data_addr[11:2]];
            for (lane = 0; lane < 4; lane = lane + 1)
                if (data_we[lane]) dmem[data_addr[11:2]][8*lane +: 8] <= data_wdata[8*lane +: 8];
        end
        if (armed && resetn && inst_en && inst_addr[1:0] != 0)
            $fatal(1, "%0s: issued misaligned instruction request %h", case_name, inst_addr);
        if (armed && resetn && expected_code == 6'h09 &&
            (data_en || data_we != 0) && data_addr == expected_badv)
            $fatal(1, "%0s: ALE request escaped in EXE at %h", case_name, data_addr);
        if (armed && resetn && dut.wb_ex) begin
            if (traps != 0) $fatal(1, "%0s: unexpected second trap", case_name);
            if (dut.wb_pc !== expected_pc || dut.wb_ecode !== expected_code || dut.wb_esubcode !== 0)
                $fatal(1, "%0s: trap pc=%h code=%h sub=%h, expected pc=%h code=%h",
                       case_name, dut.wb_pc, dut.wb_ecode, dut.wb_esubcode, expected_pc, expected_code);
            if (debug_we !== 0 || dut.csr_we !== 0 || data_en !== 0 || data_we !== 0)
                $fatal(1, "%0s: trap has register/CSR/memory side effect", case_name);
            traps = traps + 1;
            #1;
            if (dut.u_csr.era !== expected_pc || dut.u_csr.estat_ecode !== expected_code)
                $fatal(1, "%0s: CSR did not capture exception", case_name);
        end
    end

    function [31:0] addi(input [4:0] rd, input [4:0] rj, input [11:0] imm);
        addi = 32'h02800000 | {10'b0, imm, rj, rd};
    endfunction
    function [31:0] csr(input [4:0] rd, input [4:0] rj, input [13:0] addr);
        csr = 32'h04000000 | {8'b0, addr, rj, rd};
    endfunction
    function [31:0] memop(input [31:0] op, input [4:0] rd, input [4:0] rj, input [11:0] imm);
        memop = op | {10'b0, imm, rj, rd};
    endfunction

    task prepare(input [255:0] name, input [5:0] code, input [31:0] pc);
        begin
            @(negedge clk);
            armed = 0;
            resetn = 0;
            repeat (5) @(negedge clk);
            case_name = name;
            expected_code = code;
            expected_pc = pc;
            expected_badv = 32'h123;
            traps = 0;
            for (i = 0; i < 4096; i = i + 1) imem[i] = 32'h02800000;
            for (i = 0; i < 1024; i = i + 1) dmem[i] = 32'ha5a55a5a;
            imem[0] = 32'h1438002c; // lu12i.w r12, 0x1c001
            imem[1] = csr(12, 1, 14'hc);
            imem[2] = addi(4, 0, 84);
            imem[3] = addi(5, 0, 7);
            imem[4] = addi(6, 0, 12'h123);
            imem[5] = addi(20, 0, 12'h456);
            imem[6] = csr(0, 1, 14'h30);
            imem[7] = csr(6, 1, 14'h7);
            // NOTE: ex9 处理程序通过真实 CSR 指令读取现场, 再用 ertn 返回.
            imem[1024] = csr(16, 0, 14'h5);
            imem[1025] = csr(17, 0, 14'h6);
            imem[1026] = csr(18, 0, 14'h7);
            imem[1027] = 32'h14380013; // lu12i.w r19, 0x1c000
            imem[1028] = addi(19, 19, 12'h300);
            imem[1029] = csr(19, 1, 14'h6);
            imem[1030] = 32'h06483800;
            imem[1031] = memop(32'h29800000, 6, 0, 12'h104);
            imem[192] = addi(31, 0, 12'h55);
            imem[193] = 32'h50000000; // b .
        end
    endtask

    task younger(input integer index);
        begin
            imem[index] = memop(32'h29800000, 6, 0, 12'h104);
            imem[index+1] = csr(6, 1, 14'h30);
            imem[index+2] = addi(20, 0, 1);
        end
    endtask

    task run_case;
        begin
            armed = 1;
            resetn = 1;
            cycles = 0;
            begin : wait_finish
                while (cycles < 500) begin
                    @(negedge clk);
                    cycles = cycles + 1;
                    if (debug_we != 0 && debug_reg == 31 && debug_data == 32'h55)
                        disable wait_finish;
                end
                $fatal(1, "%0s: timeout pc=%h traps=%0d", case_name, debug_pc, traps);
            end
            if (traps != 1) $fatal(1, "%0s: expected one trap, got %0d", case_name, traps);
            if (dmem[65] !== 32'ha5a55a5a || dut.u_csr.save0 !== 0 ||
                dut.u_id_stage.u_regfile.rf[20] !== 32'h456)
                $fatal(1, "%0s: squashed instruction changed architectural state", case_name);
            if (dut.u_id_stage.u_regfile.rf[16] !== {10'b0, expected_code, 16'b0} ||
                dut.u_id_stage.u_regfile.rf[17] !== expected_pc)
                $fatal(1, "%0s: exception handler read wrong CSR state", case_name);
            if (dut.u_id_stage.u_regfile.rf[18] !== expected_badv)
                $fatal(1, "%0s: BADV=%h expected=%h", case_name,
                       dut.u_id_stage.u_regfile.rf[18], expected_badv);
            cases = cases + 1;
            $display("PASS %0s (%0d cycles)", case_name, cycles);
            armed = 0;
        end
    endtask

    task adef_case(input [11:0] offset, input [31:0] poison);
        begin
            prepare("ADEF jump target", 6'h08, BASE + {20'b0, offset});
            expected_badv = expected_pc;
            imem[8] = 32'h14380008; // lu12i.w r8, 0x1c000
            imem[9] = addi(8, 8, offset);
            imem[10] = 32'h4c000109; // jirl r9, r8, 0
            younger(11);
            imem[128] = poison;
            run_case;
            if (dut.u_id_stage.u_regfile.rf[9] !== BASE + 32'h2c)
                $fatal(1, "ADEF lost the older jirl link write");
        end
    endtask

    task ale_case(input [255:0] name, input [31:0] op, input [11:0] address);
        begin
            prepare(name, 6'h09, BASE + 32'h20);
            expected_badv = {20'b0, address};
            imem[8] = memop(op, 20, 0, address);
            younger(9);
            run_case;
            if (dmem[64] !== 32'ha5a55a5a)
                $fatal(1, "%0s: misaligned store changed memory", case_name);
        end
    endtask

    task aligned_case(input [255:0] name, input [31:0] op, input [11:0] address,
                      input is_load, input [31:0] expected_value);
        begin
            prepare(name, 6'h0c, BASE + 32'h24);
            imem[8] = memop(op, is_load ? 5'd21 : 5'd20, 0, address);
            imem[9] = 32'h002a0000;
            younger(10);
            run_case;
            if (is_load) begin
                if (dut.u_id_stage.u_regfile.rf[21] !== expected_value)
                    $fatal(1, "%0s: legal load data=%h expected=%h", name,
                           dut.u_id_stage.u_regfile.rf[21], expected_value);
            end else if (dmem[64] !== expected_value)
                $fatal(1, "%0s: legal store data=%h expected=%h", name, dmem[64], expected_value);
        end
    endtask

    task fault_case(input [255:0] name, input [31:0] instruction, input [5:0] code);
        begin
            prepare(name, code, BASE + 32'h20);
            imem[8] = instruction;
            younger(9);
            run_case;
        end
    endtask

    initial begin
        fault_case("break code=0", 32'h002a0000, 6'h0c);
        fault_case("break code=32767", 32'h002a7fff, 6'h0c);
        fault_case("INE all ones", 32'hffffffff, 6'h0d);
        fault_case("INE zero", 32'h00000000, 6'h0d);
        fault_case("INE near ertn low bit", 32'h06483801, 6'h0d);
        fault_case("INE broad ertn prefix", 32'h06000000, 6'h0d);
        fault_case("syscall regression", 32'h002b0000, 6'h0b);
        prepare("divide before break", 6'h0c, BASE + 32'h24);
        imem[8] = 32'h00201487; // div.w r7, r4, r5
        imem[9] = 32'h002a0000;
        younger(10);
        run_case;
        if (dut.u_id_stage.u_regfile.rf[7] !== 12) $fatal(1, "older divide lost");
        prepare("flush younger divide", 6'h0c, BASE + 32'h20);
        imem[8] = 32'h002a0000;
        imem[9] = 32'h00201487;
        younger(10);
        imem[192] = 32'h002010a7; // div.w r7, r5, r4
        imem[193] = addi(31, 0, 12'h55);
        imem[194] = 32'h50000000;
        run_case;
        if (dut.u_id_stage.u_regfile.rf[7] !== 0) $fatal(1, "new divide used stale result");
        adef_case(12'h201, 32'hffffffff);
        adef_case(12'h202, memop(32'h29800000, 6, 0, 12'h104));
        adef_case(12'h203, 32'h06483800);
        for (offset = 1; offset <= 3; offset = offset + 1) begin
            ale_case("ALE ld.w", 32'h28800000, 12'h100 + offset[11:0]);
            ale_case("ALE st.w", 32'h29800000, 12'h100 + offset[11:0]);
        end
        for (offset = 1; offset <= 3; offset = offset + 2) begin
            ale_case("ALE ld.h", 32'h28400000, 12'h100 + offset[11:0]);
            ale_case("ALE ld.hu", 32'h2a400000, 12'h100 + offset[11:0]);
            ale_case("ALE st.h", 32'h29400000, 12'h100 + offset[11:0]);
        end
        for (offset = 0; offset < 4; offset = offset + 1) begin
            sample_byte = 32'ha5a55a5a >> (8*offset);
            aligned_case("legal ld.b lane", 32'h28000000, 12'h100 + offset[11:0],
                         1, {{24{sample_byte[7]}}, sample_byte});
            aligned_case("legal ld.bu lane", 32'h2a000000, 12'h100 + offset[11:0],
                         1, {24'b0, sample_byte});
            lane_mask = 32'hff << (8*offset);
            aligned_case("legal st.b lane", 32'h29000000, 12'h100 + offset[11:0],
                         0, (32'ha5a55a5a & ~lane_mask) | (32'h56 << (8*offset)));
        end
        for (offset = 0; offset < 4; offset = offset + 2) begin
            sample_half = 32'ha5a55a5a >> (8*offset);
            aligned_case("legal ld.h lane", 32'h28400000, 12'h100 + offset[11:0],
                         1, {{16{sample_half[15]}}, sample_half});
            aligned_case("legal ld.hu lane", 32'h2a400000, 12'h100 + offset[11:0],
                         1, {16'b0, sample_half});
            lane_mask = 32'hffff << (8*offset);
            aligned_case("legal st.h lane", 32'h29400000, 12'h100 + offset[11:0],
                         0, (32'ha5a55a5a & ~lane_mask) | (32'h456 << (8*offset)));
        end
        aligned_case("legal ld.w", 32'h28800000, 12'h100, 1, 32'ha5a55a5a);
        aligned_case("legal st.w", 32'h29800000, 12'h100, 0, 32'h456);
        prepare("BADV masked CSR write", 6'h0c, BASE + 32'h2c);
        imem[8] = addi(10, 0, 12'hff);
        imem[9] = addi(11, 0, 12'h5a);
        imem[10] = csr(11, 10, 14'h7);
        imem[11] = 32'h002a0000;
        younger(12);
        expected_badv = 32'h15a;
        run_case;
        if (dut.u_id_stage.u_regfile.rf[11] !== 32'h123) $fatal(1, "csrxchg lost old BADV");
        prepare("older break beats younger ALE", 6'h0c, BASE + 32'h20);
        imem[8] = 32'h002a0000;
        imem[9] = memop(32'h29800000, 20, 0, 12'h101);
        younger(10);
        run_case;
        if (dmem[64] !== 32'ha5a55a5a) $fatal(1, "younger ALE store escaped");
        $display("PASS ex9_1 directed tests: %0d cases", cases);
        $finish;
    end
endmodule
