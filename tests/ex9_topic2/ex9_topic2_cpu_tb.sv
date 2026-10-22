`timescale 1ns / 1ps

// NOTE: ex9, 整核执行真实 CSR 指令. 不依赖交叉编译器或官方镜像.
module ex9_topic2_cpu_tb;
    localparam [31:0] BOOT = 32'h1c000000, NOP = 32'h03400000;
    localparam [31:0] SYSCALL = 32'h002b0000, ERTN = 32'h06483800;
    localparam [13:0] ESTAT = 14'h0005, ERA = 14'h0006, EENTRY = 14'h000c;
    localparam [13:0] TID = 14'h0040, TCFG = 14'h0041;
    localparam [13:0] TVAL = 14'h0042, TICLR = 14'h0044;
    localparam integer WORDS = 2048, RETURN_INDEX = 1024, HANDLER_INDEX = 1536;
    reg clk = 1'b0, resetn = 1'b0;
    always #5 clk = ~clk;
    wire inst_en, data_en;
    wire [3:0] inst_we, data_we, wb_we;
    wire [31:0] inst_addr, inst_wdata, data_addr, data_wdata;
    reg [31:0] inst_rdata = NOP;
    wire [31:0] wb_pc, wb_data;
    wire [4:0] wb_dest;
    reg [31:0] rom [0:WORDS-1];
    reg [31:0] expected_pc [0:WORDS-1];
    reg [31:0] registers [0:31];
    reg [31:0] reference_tid = 32'b0, reference_era = 32'b0;
    reg [31:0] reference_entry = 32'b0;
    reg [1:0] reference_software = 2'b0;
    reg [5:0] reference_code = 6'b0;
    reg [8:0] reference_subcode = 9'b0;
    wire [31:0] expected_cfg, expected_remaining, expiries, reloads;
    wire expected_pending;
    wire [31:0] reference_status = {1'b0, reference_subcode, reference_code,
        4'b0, expected_pending, 9'b0, reference_software};
    reg [63:0] stable_reference = 64'b0;
    integer ip = 0, planned = 0, retired = 0, cycles = 0;
    integer csr_reads = 0, csr_writes = 0, value_reads = 0;
    integer stalls = 0, expiry_during_stall = 0, running_flushes = 0;
    integer syscall_count = 0, return_count = 0;
    reg done = 1'b0;
    reg [31:0] finish_pc;

    mycpu_top dut (
        .clk(clk), .resetn(resetn),
        .inst_sram_en(inst_en), .inst_sram_we(inst_we),
        .inst_sram_addr(inst_addr), .inst_sram_wdata(inst_wdata),
        .inst_sram_rdata(inst_rdata), .data_sram_en(data_en),
        .data_sram_we(data_we), .data_sram_addr(data_addr),
        .data_sram_wdata(data_wdata), .data_sram_rdata(32'b0),
        .debug_wb_pc(wb_pc), .debug_wb_rf_we(wb_we),
        .debug_wb_rf_wnum(wb_dest), .debug_wb_rf_wdata(wb_data)
    );

    // 访问端口在每次提交时由下方独立译码检查, 不能靠错误写使参考模型同步错误.
    ex9_timer_reference reference_timer (
        .clk(clk), .reset(!resetn || dut.reset),
        .write_enable(dut.csr_we && !dut.wb_ex && !dut.ertn_flush),
        .address(dut.csr_addr), .write_mask(dut.csr_wmask), .write_value(dut.csr_wvalue),
        .configuration(expected_cfg), .remaining(expected_remaining),
        .pending(expected_pending), .expiry_count(expiries), .reload_count(reloads)
    );

    function automatic [31:0] ri(input [31:0] opcode, input integer rd, rj, imm);
        ri = opcode | ((imm & 4095) << 10) | (rj << 5) | rd;
    endfunction
    function automatic [31:0] rr(input [31:0] opcode, input integer rd, rj, rk);
        rr = opcode | (rk << 10) | (rj << 5) | rd;
    endfunction
    function automatic [31:0] csr_inst(input integer rd, rj, input [13:0] number);
        csr_inst = 32'h04000000 | (number << 10) | (rj << 5) | rd;
    endfunction

    task automatic fail(input string message);
        $display("[FAIL] CPU cycle=%0d retired=%0d/%0d WB_PC=%08h: %s",
            cycles, retired, planned, wb_pc, message);
        $fatal(1, "ex9 Topic 2 CPU test failed");
    endtask
    task automatic emit(input [31:0] instruction);
        if (ip >= WORDS || planned >= WORDS) $fatal(1, "local ROM overflow");
        rom[ip] = instruction;
        expected_pc[planned] = BOOT + 4 * ip;
        planned = planned + 1;
        ip = ip + 1;
    endtask
    task automatic li(input integer rd, input [31:0] value);
        emit(32'h14000000 | ((value >> 12) << 5) | rd);
        emit(ri(32'h03800000, rd, rd, value[11:0]));
    endtask
    task automatic nops(input integer count);
        repeat (count) emit(NOP);
    endtask
    task automatic write_value(input [13:0] number, input [31:0] value);
        li(4, value);
        emit(csr_inst(4, 1, number));
    endtask
    task automatic exchange(input [13:0] number, input [31:0] mask, value);
        li(5, value);
        li(6, mask);
        emit(csr_inst(5, 6, number));
    endtask

    // NOTE: ex9, 读值按 WB 上升沿之前的参考状态计算, 写回旧值后才修改状态.
    task automatic check_retirement;
        reg [31:0] instruction, result, mask, old_data;
        reg gpr_write, csr_read, csr_write;
        integer rd, rj, rk, number;
        if (retired >= planned) fail("unexpected extra retirement");
        if (wb_pc !== expected_pc[retired])
            fail($sformatf("PC actual=%08h expected=%08h", wb_pc, expected_pc[retired]));
        instruction = rom[(wb_pc - BOOT) >> 2];
        rd = instruction[4:0];
        rj = instruction[9:5];
        rk = instruction[14:10];
        result = 32'b0;
        gpr_write = 1'b1;
        csr_read = 1'b0;
        csr_write = 1'b0;
        if (instruction[31:24] == 8'h04) begin
            number = instruction[23:10];
            case (number)
                ESTAT: result = reference_status;
                ERA: result = reference_era;
                EENTRY: result = reference_entry;
                TID: result = reference_tid;
                TCFG: result = expected_cfg;
                TVAL: begin result = expected_remaining; value_reads = value_reads + 1; end
                TICLR: result = 32'b0;
                default: fail("reference decoder lacks CSR");
            endcase
            csr_read = 1'b1;
            csr_reads = csr_reads + 1;
            csr_write = (rj != 0);
            if (dut.csr_addr !== number[13:0]) fail("wrong CSR number at WB");
            if (csr_write) begin
                mask = (rj == 1) ? 32'hffffffff : registers[rj];
                old_data = registers[rd];
                if (dut.csr_wmask !== mask || dut.csr_wvalue !== old_data)
                    fail("wrong CSR mask/data: original GPR operands were not preserved");
                case (number)
                    ESTAT: reference_software = (reference_software & ~mask[1:0])
                                               | (old_data[1:0] & mask[1:0]);
                    ERA: reference_era = (reference_era & ~mask) | (old_data & mask);
                    EENTRY: reference_entry = ((reference_entry & ~mask) | (old_data & mask))
                                              & 32'hffffffc0;
                    TID: reference_tid = (reference_tid & ~mask) | (old_data & mask);
                    default: begin end
                endcase
                csr_writes = csr_writes + 1;
            end
        end else if ((instruction & 32'hfe000000) == 32'h14000000) begin
            result = {instruction[24:5], 12'b0};
        end else if ((instruction & 32'hffc00000) == 32'h02800000) begin
            result = registers[rj] + {{20{instruction[21]}}, instruction[21:10]};
        end else if ((instruction & 32'hffc00000) == 32'h03800000) begin
            result = registers[rj] | {20'b0, instruction[21:10]};
        end else if ((instruction & 32'hffff8000) == 32'h00100000) begin
            result = registers[rj] + registers[rk];
        end else if ((instruction & 32'hffff8000) == 32'h00200000) begin
            result = $signed(registers[rj]) / $signed(registers[rk]);
        end else if (instruction == NOP) begin
            result = 32'b0;
        end else if (instruction == SYSCALL) begin
            gpr_write = 1'b0;
            reference_era = wb_pc;
            reference_code = 6'h0b;
            reference_subcode = 9'b0;
            syscall_count = syscall_count + 1;
        end else if (instruction == ERTN) begin
            gpr_write = 1'b0;
            return_count = return_count + 1;
        end else begin
            fail($sformatf("reference decoder lacks instruction %08h", instruction));
        end
        if (dut.csr_re !== csr_read || dut.csr_we !== csr_write)
            fail("CSR read/write enables do not match retired instruction");
        if (dut.wb_ex !== (instruction == SYSCALL)
            || dut.ertn_flush !== (instruction == ERTN)) fail("unexpected exception/return");
        if (gpr_write && rd != 0) begin
            if (wb_we !== 4'hf || wb_dest !== rd[4:0] || wb_data !== result)
                fail($sformatf("GPR actual r%0d=%08h we=%h expected r%0d=%08h inst=%08h",
                    wb_dest, wb_data, wb_we, rd, result, instruction));
            registers[rd] = result;
        end else if (gpr_write) begin
            if (wb_we !== 4'b0 && (wb_we !== 4'hf || wb_dest !== 5'b0))
                fail("zero-destination instruction wrote another register");
        end else if (wb_we !== 4'b0) begin
            fail("exception/return instruction wrote GPR");
        end
        registers[0] = 32'b0;
        retired = retired + 1;
        if (wb_pc == finish_pc) done = 1'b1;
    endtask

    always @(posedge clk) begin
        if (inst_en && !dut.reset) begin
            if (inst_addr < BOOT || inst_addr >= BOOT + 4 * WORDS || inst_addr[1:0] != 0)
                fail("instruction fetch outside local ROM");
            inst_rdata <= rom[(inst_addr - BOOT) >> 2];
        end
    end

    always @(posedge clk) begin
        if (dut.reset === 1'b1) begin
            stable_reference = 64'b0;
        end else if (dut.reset === 1'b0 && resetn) begin
            cycles = cycles + 1;
            if (cycles > 5000) fail("timeout: test did not finish");
            stable_reference = stable_reference + 64'd1;
            if (inst_we !== 4'b0 || data_en !== 1'b0 || data_we !== 4'b0)
                fail("CSR-only program issued unexpected memory write/data request");
            if (dut.es_valid && !dut.es_ready_go) begin
                stalls = stalls + 1;
                if (expected_cfg[0] && expected_remaining == 0)
                    expiry_during_stall = expiry_during_stall + 1;
            end
            if (dut.flush && expected_cfg[0] && expected_remaining != 32'hffffffff)
                running_flushes = running_flushes + 1;
            if (dut.u_wb_stage.ws_valid) begin
                check_retirement();
            end else if (dut.csr_we !== 1'b0 || dut.csr_re !== 1'b0 || wb_we !== 4'b0) begin
                fail("invalid WB stage produced a side effect");
            end
            #1;
            if (dut.u_csr.u_timer.tcfg !== expected_cfg
                || dut.u_csr.u_timer.timer_cnt !== expected_remaining
                || dut.u_csr.u_timer.ti_flag !== expected_pending)
                fail($sformatf("timer actual cfg/count/pending=%08h/%08h/%b expected=%08h/%08h/%b",
                    dut.u_csr.u_timer.tcfg, dut.u_csr.u_timer.timer_cnt, dut.u_csr.u_timer.ti_flag,
                    expected_cfg, expected_remaining, expected_pending));
            if (dut.u_exe_stage.u_counter.stable_counter !== stable_reference)
                fail("Stable Counter stopped or changed during timer operations/stall/flush");
            if (done) begin
                if (retired != planned || stalls < 10 || expiry_during_stall < 1
                    || running_flushes != 2 || syscall_count != 1 || return_count != 1
                    || value_reads < 5 || reloads < 2)
                    fail("required scenario did not execute");
                $display("[PASS] CPU/CSR read-write, old-value return and GPR dependencies");
                $display("[PASS] CPU/timer counts through division stall and syscall/ertn flush");
                $display("[PASS] CPU/killed young configuration/clear writes have no side effects");
                $display("ALL PASS: ex9 Topic 2 CPU (retired=%0d reads=%0d writes=%0d stall=%0d expiry_in_stall=%0d running_flush=%0d)",
                    retired, csr_reads, csr_writes, stalls, expiry_during_stall, running_flushes);
                $finish;
            end
        end
    end

    initial begin
        if ($test$plusargs("WAVES")) begin
            $dumpfile("ex9_topic2_cpu.vcd");
            $dumpvars(0, ex9_topic2_cpu_tb);
        end
        for (integer n = 0; n < WORDS; n = n + 1) rom[n] = NOP;
        for (integer n = 0; n < 32; n = n + 1) registers[n] = 32'b0;
        for (integer n = 1; n < 32; n = n + 1) emit(ri(32'h02800000, n, 0, 0));
        emit(csr_inst(7, 0, TVAL));
        emit(csr_inst(8, 0, TCFG));
        emit(csr_inst(9, 0, TICLR));
        write_value(TCFG, 32'h87654320);
        emit(rr(32'h00100000, 7, 4, 4));
        emit(csr_inst(8, 0, TCFG));
        write_value(TCFG, 32'h00000021);
        emit(csr_inst(7, 0, TVAL));
        emit(rr(32'h00100000, 8, 7, 7));
        exchange(TCFG, 32'hfffffffc, 32'h00000008);
        emit(csr_inst(7, 0, TCFG));
        nops(20);
        emit(csr_inst(8, 0, ESTAT));
        emit(csr_inst(9, 0, TVAL));
        write_value(ESTAT, 32'd3);
        write_value(TICLR, 32'b0);
        exchange(TICLR, 32'd2, 32'd1);
        emit(csr_inst(8, 0, ESTAT));
        exchange(TICLR, 32'd1, 32'd1);
        emit(csr_inst(8, 0, ESTAT));
        emit(csr_inst(9, 0, TICLR));
        write_value(TVAL, 32'h12345678);
        emit(csr_inst(9, 0, TVAL));

        write_value(TCFG, 32'd7);
        nops(24);
        emit(csr_inst(8, 0, ESTAT));
        exchange(TCFG, 32'd1, 32'b0);
        emit(csr_inst(9, 0, TVAL));
        write_value(TICLR, 32'd1);
        emit(csr_inst(8, 0, ESTAT));
        write_value(TCFG, 32'h00000041);
        exchange(TCFG, 32'hfffffffc, 32'h00000010);
        exchange(TCFG, 32'b0, 32'hffffffff);
        emit(csr_inst(9, 0, TVAL));

        li(10, 32'd100);
        li(11, 32'd3);
        write_value(TCFG, 32'd9);
        emit(rr(32'h00200000, 12, 10, 11));
        emit(csr_inst(8, 0, ESTAT));
        emit(csr_inst(9, 0, TVAL));

        write_value(EENTRY, BOOT + 4 * HANDLER_INDEX);
        write_value(TCFG, 32'h00000083);
        li(8, 32'b0);
        li(9, 32'd1);
        emit(SYSCALL);
        // 错路径指令不加入提交计划. 如果任何一条产生副作用, 端口/计数检查失败.
        rom[ip] = csr_inst(8, 1, TCFG);
        rom[ip + 1] = csr_inst(9, 1, TICLR);

        ip = HANDLER_INDEX;
        emit(csr_inst(20, 0, ERA));
        li(22, BOOT + 4 * RETURN_INDEX);
        emit(csr_inst(22, 1, ERA));
        emit(csr_inst(23, 0, TVAL));
        emit(csr_inst(24, 0, ESTAT));
        emit(ERTN);
        rom[ip] = csr_inst(8, 1, TCFG);
        rom[ip + 1] = csr_inst(9, 1, TICLR);

        ip = RETURN_INDEX;
        emit(csr_inst(25, 0, TCFG));
        emit(csr_inst(26, 0, TVAL));
        emit(csr_inst(27, 0, ESTAT));
        finish_pc = BOOT + 4 * ip;
        emit(ri(32'h02800000, 31, 0, 12'h5a5));
        rom[ip] = 32'h50000000;
        repeat (6) @(negedge clk);
        resetn = 1'b1;
    end

    initial begin
        #100000;
        $fatal(1, "ex9 Topic 2 CPU watchdog timeout");
    end
endmodule
