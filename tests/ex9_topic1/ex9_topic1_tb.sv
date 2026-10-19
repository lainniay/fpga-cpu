`timescale 1ns / 1ps

// NOTE: ex9, Topic 1 独立整核测试. 不读取或改写官方镜像和 trace.
module ex9_topic1_tb;
    localparam [31:0] BOOT = 32'h1c000000;
    localparam [31:0] DATA_BASE = 32'h00001000;
    localparam integer ROM_WORDS = 1024;
    localparam integer RAM_WORDS = 64;
    localparam integer MAX_RETIRES = 1024;
    localparam [13:0] TID = 14'h0040;
    localparam [13:0] ERA = 14'h0006;
    localparam [13:0] EENTRY = 14'h000c;
    localparam [13:0] TCFG = 14'h0041;
    localparam [31:0] NOP = 32'h03400000; // andi r0, r0, 0.
    localparam [31:0] SYSCALL = 32'h002b0000;
    localparam [31:0] ERTN = 32'h06483800;

    reg clk = 1'b0;
    reg resetn = 1'b0;
    always #5 clk = ~clk;

    wire inst_en, data_en;
    wire [3:0] inst_we, data_we;
    wire [31:0] inst_addr, inst_wdata, data_addr, data_wdata;
    reg [31:0] inst_rdata = NOP;
    reg [31:0] data_rdata = 32'b0;
    wire [31:0] wb_pc, wb_data;
    wire [3:0] wb_we;
    wire [4:0] wb_dest;

    mycpu_top dut (
        .clk(clk), .resetn(resetn),
        .inst_sram_en(inst_en), .inst_sram_we(inst_we),
        .inst_sram_addr(inst_addr), .inst_sram_wdata(inst_wdata),
        .inst_sram_rdata(inst_rdata),
        .data_sram_en(data_en), .data_sram_we(data_we),
        .data_sram_addr(data_addr), .data_sram_wdata(data_wdata),
        .data_sram_rdata(data_rdata),
        .debug_wb_pc(wb_pc), .debug_wb_rf_we(wb_we),
        .debug_wb_rf_wnum(wb_dest), .debug_wb_rf_wdata(wb_data)
    );

    reg [31:0] rom [0:ROM_WORDS-1];
    reg [31:0] ram [0:RAM_WORDS-1];
    reg [31:0] ref_ram [0:RAM_WORDS-1];
    reg [31:0] ref_gpr [0:31];
    reg [31:0] ref_csr [0:127];
    reg [31:0] expected_pc [0:MAX_RETIRES-1];
    reg [63:0] sampled_counter [0:ROM_WORDS-1];
    reg sampled_valid [0:ROM_WORDS-1];
    reg [63:0] ref_counter = 64'b0;
    reg [63:0] next_counter;
    reg monitor_active = 1'b0;
    reg case_done = 1'b0;
    string case_name;
    integer ip, expected_count, retired_count, cycles;
    integer actual_stores, expected_stores, stall_cycles, flush_cycles;
    integer low_reads, high_reads, id_reads, carry_events, wrap_events;
    integer es_count_fwd, ms_count_fwd, ws_tid_fwd;
    integer passed_cases = 0;
    reg [31:0] finish_pc;

    // NOTE: ex9, 本地编码函数只生成下面测试使用的 LA32R 指令.
    function automatic [31:0] rr(input [31:0] opcode,
        input integer rd, rj, rk);
        rr = opcode | (rk << 10) | (rj << 5) | rd;
    endfunction

    function automatic [31:0] ri(input [31:0] opcode,
        input integer rd, rj, imm);
        ri = opcode | ((imm & 4095) << 10) | (rj << 5) | rd;
    endfunction

    function automatic [31:0] csr_inst(input integer rd, rj,
        input [13:0] number);
        csr_inst = 32'h04000000 | (number << 10) | (rj << 5) | rd;
    endfunction

    function automatic [31:0] cnt_low(input integer rd);
        cnt_low = 32'h00006000 | rd;
    endfunction

    function automatic [31:0] cnt_high(input integer rd);
        cnt_high = 32'h00006400 | rd;
    endfunction

    function automatic [31:0] cnt_id(input integer rj);
        cnt_id = 32'h00006000 | (rj << 5);
    endfunction

    function automatic is_low(input [31:0] instruction);
        is_low = ((instruction & 32'hffffffe0) == 32'h00006000);
    endfunction

    function automatic is_high(input [31:0] instruction);
        is_high = ((instruction & 32'hffffffe0) == 32'h00006400);
    endfunction

    function automatic is_id(input [31:0] instruction);
        is_id = ((instruction & 32'hfffffc1f) == 32'h00006000)
                && (instruction[9:5] != 5'd0);
    endfunction

    task automatic fail(input string message);
        $display("[FAIL] %s cycle=%0d retired=%0d/%0d WB_PC=%08h: %s",
            case_name, cycles, retired_count, expected_count, wb_pc, message);
        $fatal(1, "ex9 Topic 1 failed");
    endtask

    // NOTE: ex9, 每个实际提交的 PC 都与执行计划比较, 错路径写回不能被跳过.
    task automatic emit(input [31:0] instruction);
        if (ip >= ROM_WORDS || expected_count >= MAX_RETIRES)
            $fatal(1, "test program exceeds local memory");
        rom[ip] = instruction;
        expected_pc[expected_count] = BOOT + 4 * ip;
        expected_count = expected_count + 1;
        ip = ip + 1;
    endtask

    task automatic emit_li(input integer rd, input [31:0] value);
        emit(32'h14000000 | ((value >> 12) << 5) | rd);
        emit(ri(32'h03800000, rd, rd, value[11:0]));
    endtask

    task automatic finish_program;
        finish_pc = BOOT + 4 * ip;
        emit(ri(32'h02800000, 31, 0, 12'h5a5));
        rom[ip] = 32'h50000000; // b 0, 不再产生 GPR 写回.
    endtask

    task automatic prepare_case(input string name);
        @(negedge clk);
        monitor_active = 1'b0;
        resetn = 1'b0;
        case_done = 1'b0;
        case_name = name;
        ip = 0;
        expected_count = 0;
        retired_count = 0;
        cycles = 0;
        actual_stores = 0;
        expected_stores = 0;
        stall_cycles = 0;
        flush_cycles = 0;
        low_reads = 0;
        high_reads = 0;
        id_reads = 0;
        carry_events = 0;
        wrap_events = 0;
        es_count_fwd = 0;
        ms_count_fwd = 0;
        ws_tid_fwd = 0;
        ref_counter = 64'b0;
        finish_pc = 32'hffffffff;
        for (integer n = 0; n < ROM_WORDS; n = n + 1) begin
            rom[n] = NOP;
            sampled_counter[n] = 64'b0;
            sampled_valid[n] = 1'b0;
        end
        for (integer n = 0; n < RAM_WORDS; n = n + 1) begin
            ram[n] = 32'b0;
            ref_ram[n] = 32'b0;
        end
        for (integer n = 0; n < 32; n = n + 1)
            ref_gpr[n] = 32'b0;
        for (integer n = 0; n < 128; n = n + 1)
            ref_csr[n] = 32'b0;
        ref_csr[0] = 32'h8;
        // Regfile 本身无复位, 用真实指令初始化, 不从 testbench 改写 GPR.
        for (integer n = 1; n < 32; n = n + 1)
            emit(ri(32'h02800000, n, 0, 0));
    endtask

    task automatic run_case(input bit seed_enable, input [63:0] seed);
        repeat (6) @(negedge clk);
        if (dut.u_exe_stage.stable_counter !== 64'b0)
            fail("Stable Counter did not reset to zero");
        if (dut.u_csr.tid !== 32'b0)
            fail("TID did not reset to zero");
        ref_counter = 64'b0;
        monitor_active = 1'b1;
        resetn = 1'b1;
        if (seed_enable) begin
            wait (dut.reset === 1'b0);
            @(negedge clk);
            #1;
            // NOTE: ex9, 仅边界测试设置内部状态, 随后恢复正常计数, 不使用 force.
            dut.u_exe_stage.stable_counter = seed;
            ref_counter = seed;
        end
        wait (case_done);
        @(negedge clk);
        monitor_active = 1'b0;
        resetn = 1'b0;
        if (actual_stores != expected_stores)
            fail($sformatf("store count actual=%0d expected=%0d",
                actual_stores, expected_stores));
        for (integer n = 0; n < RAM_WORDS; n = n + 1)
            if (ram[n] !== ref_ram[n])
                fail($sformatf("RAM[%0d] actual=%08h expected=%08h",
                    n, ram[n], ref_ram[n]));
        $display("[PASS] %s: retired=%0d low=%0d high=%0d id=%0d stall=%0d flush=%0d carry=%0d wrap=%0d",
            case_name, retired_count, low_reads, high_reads, id_reads,
            stall_cycles, flush_cycles, carry_events, wrap_events);
        passed_cases = passed_cases + 1;
    endtask

    // NOTE: ex9, 同步 SRAM 模型, 接口行为与课程 testbench 一样在上升沿读写.
    always @(posedge clk) begin
        if (inst_en && !dut.reset) begin
            if (inst_addr < BOOT || inst_addr >= BOOT + 4 * ROM_WORDS
                    || inst_addr[1:0] != 2'b00)
                fail($sformatf("unexpected instruction address %08h", inst_addr));
            inst_rdata <= rom[(inst_addr - BOOT) >> 2];
        end
        if (inst_we !== 4'b0)
            fail("CPU tried to write instruction memory");
        if (monitor_active && !dut.reset) begin
            if (|data_we && !data_en)
                fail("data write without data_sram_en");
            if (data_en) begin
                if (data_addr < DATA_BASE || data_addr >= DATA_BASE + 4 * RAM_WORDS
                        || data_addr[1:0] != 2'b00)
                    fail($sformatf("unexpected data address %08h", data_addr));
                // 计数指令不允许额外发起数据访存.
                if ((rom[(dut.u_exe_stage.es_pc - BOOT) >> 2] & 32'hffc00000)
                        != 32'h28800000
                    && (rom[(dut.u_exe_stage.es_pc - BOOT) >> 2] & 32'hffc00000)
                        != 32'h29800000)
                    fail("non-load/store instruction issued a data request");
                data_rdata <= ram[(data_addr - DATA_BASE) >> 2];
                if (|data_we) begin
                    if (data_we !== 4'hf)
                        fail("word-store byte enables are not 1111");
                    actual_stores = actual_stores + 1;
                    for (integer b = 0; b < 4; b = b + 1)
                        if (data_we[b])
                            ram[(data_addr - DATA_BASE) >> 2][8*b +: 8]
                                <= data_wdata[8*b +: 8];
                end
            end
        end
    end

    // NOTE: ex9, 提交时按 ISA 计算期望值, 不从 DUT 的结果选择信号推导答案.
    task automatic check_retirement;
        reg [31:0] instruction, value, mask, address;
        integer rd, rj, rk, number, index, destination;
        reg writes_gpr, writes_csr;
        if (retired_count >= expected_count)
            fail("extra instruction retired");
        if (wb_pc !== expected_pc[retired_count])
            fail($sformatf("retirement PC actual=%08h expected=%08h",
                wb_pc, expected_pc[retired_count]));
        index = (wb_pc - BOOT) >> 2;
        instruction = rom[index];
        rd = instruction[4:0];
        rj = instruction[9:5];
        rk = instruction[14:10];
        destination = rd;
        value = 32'b0;
        writes_gpr = 1'b1;
        writes_csr = 1'b0;
        if (is_low(instruction) || is_high(instruction)) begin
            if (!sampled_valid[index])
                fail("counter read retired without an accepted instruction sample");
            if (is_high(instruction)) begin
                value = sampled_counter[index][63:32];
                high_reads = high_reads + 1;
            end else begin
                value = sampled_counter[index][31:0];
                low_reads = low_reads + 1;
            end
        end else if (is_id(instruction)) begin
            destination = rj;
            value = ref_csr[TID];
            id_reads = id_reads + 1;
        end else if (instruction[31:24] == 8'h04) begin
            number = instruction[23:10];
            if (number >= 128)
                fail("test reference CSR index out of range");
            value = ref_csr[number];
            writes_csr = (rj != 0);
            if (writes_csr) begin
                mask = (rj == 1) ? 32'hffffffff : ref_gpr[rj];
                ref_csr[number] = (value & ~mask) | (ref_gpr[rd] & mask);
            end
        end else if ((instruction & 32'hfe000000) == 32'h14000000) begin
            value = {instruction[24:5], 12'b0};
        end else if ((instruction & 32'hffc00000) == 32'h02800000) begin
            value = ref_gpr[rj] + {{20{instruction[21]}}, instruction[21:10]};
        end else if ((instruction & 32'hffc00000) == 32'h03800000) begin
            value = ref_gpr[rj] | {20'b0, instruction[21:10]};
        end else if (instruction == NOP) begin
            value = 32'b0;
        end else if ((instruction & 32'hffff8000) == 32'h00100000) begin
            value = ref_gpr[rj] + ref_gpr[rk];
        end else if ((instruction & 32'hffff8000) == 32'h001c0000) begin
            value = ref_gpr[rj] * ref_gpr[rk];
        end else if ((instruction & 32'hffff8000) == 32'h00200000) begin
            value = $signed(ref_gpr[rj]) / $signed(ref_gpr[rk]);
        end else if ((instruction & 32'hffc00000) == 32'h28800000
                || (instruction & 32'hffc00000) == 32'h29800000) begin
            address = ref_gpr[rj] + {{20{instruction[21]}}, instruction[21:10]};
            if (address < DATA_BASE || address >= DATA_BASE + 4 * RAM_WORDS
                    || address[1:0] != 0)
                fail("reference memory address out of range");
            if ((instruction & 32'hffc00000) == 32'h29800000) begin
                writes_gpr = 1'b0;
                ref_ram[(address - DATA_BASE) >> 2] = ref_gpr[rd];
                expected_stores = expected_stores + 1;
            end else begin
                value = ref_ram[(address - DATA_BASE) >> 2];
            end
        end else if (instruction == SYSCALL) begin
            writes_gpr = 1'b0;
            ref_csr[ERA] = wb_pc;
            if (!dut.wb_ex || dut.wb_ecode !== 6'h0b)
                fail("syscall did not report SYS at WB");
        end else if (instruction == ERTN) begin
            writes_gpr = 1'b0;
            if (!dut.ertn_flush)
                fail("ertn did not flush at WB");
        end else if (instruction[31:26] == 6'h16
                || instruction[31:26] == 6'h14) begin
            writes_gpr = 1'b0; // beq / b, PC 顺序由 expected_pc 独立检查.
        end else begin
            fail($sformatf("reference decoder lacks instruction %08h", instruction));
        end
        if (dut.csr_we !== writes_csr)
            fail($sformatf("unexpected CSR write enable for instruction %08h", instruction));
        if (writes_gpr && destination != 0) begin
            if (wb_we !== 4'hf || wb_dest !== destination[4:0] || wb_data !== value)
                fail($sformatf("GPR actual r%0d=%08h we=%h, expected r%0d=%08h, inst=%08h",
                    wb_dest, wb_data, wb_we, destination, value, instruction));
            ref_gpr[destination] = value;
        end else if (writes_gpr) begin
            // r0 允许抑制物理写口, 但绝不能误写其他 GPR.
            if (wb_we !== 4'b0 && (wb_we !== 4'hf || wb_dest !== 5'b0))
                fail("zero-destination instruction wrote another register");
        end else if (wb_we !== 4'b0) begin
            fail("non-GPR instruction wrote a GPR");
        end
        ref_gpr[0] = 32'b0;
        retired_count = retired_count + 1;
        if (wb_pc == finish_pc) begin
            if (retired_count != expected_count)
                fail("finish reached before all expected instructions retired");
            case_done = 1'b1;
        end
    endtask

    // NOTE: ex9, 独立按时钟累计时间. 既检查正常周期, 也检查 stall 和 flush 周期.
    always @(posedge clk) begin : monitor
        integer index;
        reg [31:0] instruction;
        if (monitor_active) begin
            if (dut.reset === 1'b1) begin
                next_counter = 64'b0;
            end else if (dut.reset === 1'b0) begin
                cycles = cycles + 1;
                if (cycles > 5000)
                    fail("timeout: expected instruction or completion was not reached");
                next_counter = ref_counter + 64'd1;
                if (ref_counter[31:0] == 32'hffffffff)
                    carry_events = carry_events + 1;
                if (ref_counter == 64'hffffffffffffffff)
                    wrap_events = wrap_events + 1;
                if (dut.es_valid && !dut.es_ready_go)
                    stall_cycles = stall_cycles + 1;
                if (dut.flush)
                    flush_cycles = flush_cycles + 1;
                if (dut.u_id_stage.ds_valid && !dut.flush) begin
                    instruction = rom[(dut.u_id_stage.ds_pc - BOOT) >> 2];
                    if (is_low(instruction) || is_high(instruction) || is_id(instruction))
                        if (dut.u_id_stage.src1_is_rj !== 1'b0
                                || dut.u_id_stage.src2_is_rkd !== 1'b0)
                            fail("counter read incorrectly declares a GPR source");
                end
                if (dut.ds_to_es_valid && dut.es_allowin && !dut.flush) begin
                    index = (dut.u_id_stage.ds_pc - BOOT) >> 2;
                    instruction = rom[index];
                    if (is_low(instruction) || is_high(instruction)) begin
                        sampled_counter[index] = ref_counter;
                        sampled_valid[index] = 1'b1;
                    end
                end
                if (dut.es_valid) begin
                    instruction = rom[(dut.u_exe_stage.es_pc - BOOT) >> 2];
                    if ((is_low(instruction) || is_high(instruction))
                            && dut.u_id_stage.ds_valid
                            && (dut.u_id_stage.es_fwd_en1 || dut.u_id_stage.es_fwd_en2))
                        es_count_fwd = es_count_fwd + 1;
                end
                if (dut.ms_valid) begin
                    instruction = rom[(dut.u_mem_stage.ms_pc - BOOT) >> 2];
                    if ((is_low(instruction) || is_high(instruction))
                            && dut.u_id_stage.ds_valid
                            && (dut.u_id_stage.ms_fwd_en1 || dut.u_id_stage.ms_fwd_en2))
                        ms_count_fwd = ms_count_fwd + 1;
                end
                if (dut.u_wb_stage.ws_valid) begin
                    if (is_id(rom[(wb_pc-BOOT)>>2]) && dut.u_id_stage.ds_valid
                            && (dut.u_id_stage.ws_fwd_en1 || dut.u_id_stage.ws_fwd_en2))
                        ws_tid_fwd = ws_tid_fwd + 1;
                    check_retirement();
                end
            end else begin
                fail("internal reset is unknown");
            end
            #1;
            if (dut.u_exe_stage.stable_counter !== next_counter)
                fail($sformatf("counter actual=%016h expected=%016h (including stall/flush)",
                    dut.u_exe_stage.stable_counter, next_counter));
            ref_counter = next_counter;
        end
    end

    initial begin : tests
        integer resume_ip;
        if ($test$plusargs("WAVES")) begin
            $dumpfile("ex9_topic1.vcd");
            $dumpvars(0, ex9_topic1_tb);
        end
        // 与官方 ex9_obj/test.s 中的机器码交叉核对, 防止测试编码函数写错.
        if (cnt_low(13) != 32'h0000600d || cnt_high(14) != 32'h0000640e
                || cnt_id(12) != 32'h00006180
                || csr_inst(13, 1, TID) != 32'h0401002d)
            $fatal(1, "test instruction encoding sanity check failed");

        prepare_case("TID read/write, mask, destinations and immediate dependencies");
        emit(cnt_id(12));
        emit(ri(32'h02800000, 13, 12, 1));
        emit_li(8, 32'h1111ffff);
        emit(csr_inst(8, 1, TID));
        emit(cnt_id(12));
        emit(rr(32'h00100000, 13, 12, 12));
        emit(csr_inst(14, 0, TID));
        emit_li(8, 32'hffff1111);
        emit(csr_inst(8, 1, TID));
        emit(cnt_id(15));
        emit_li(8, 32'hffffffff);
        emit(csr_inst(8, 1, TID));
        emit(cnt_id(16));
        emit_li(8, 32'h12345678);
        emit_li(9, 32'h00ff00ff);
        emit(csr_inst(8, 9, TID));
        emit(cnt_id(17));
        emit_li(9, 32'b0);
        emit_li(8, 32'b0);
        emit(csr_inst(8, 9, TID)); // mask=0 保持原 TID.
        emit(cnt_id(18));
        emit(csr_inst(19, 0, TID));
        // rdcntid 的 rj 是目的, 紧跟写同一 GPR 的 load 不应引入假源依赖.
        emit_li(10, DATA_BASE);
        emit(ri(32'h28800000, 12, 10, 0));
        emit(cnt_id(12));
        emit(rr(32'h00100000, 20, 12, 12));
        emit(ri(32'h29800000, 12, 10, 0));
        emit(ri(32'h28800000, 21, 10, 0));
        emit(csr_inst(8, 0, TID));
        emit(cnt_id(12));
        emit(32'h58000000 | (2 << 10) | (12 << 5) | 8); // beq r12,r8,+8.
        rom[ip] = ri(32'h02800000, 25, 0, 999); // 必须被跳过.
        ip = ip + 1;
        emit(cnt_low(0)); // 两种零目的别名的重叠编码.
        emit(cnt_high(0));
        emit(ri(32'h02800000, 22, 0, 1)); // 读取 r0 应仍为0.
        finish_program();
        run_case(1'b0, 64'b0);
        if (id_reads < 8 || ws_tid_fwd == 0)
            fail("TID scenarios or WB-to-ID dependency were not exercised");

        prepare_case("counter halves, carry and EXE/MEM forwarding");
        for (integer n = 0; n < 16; n = n + 1) begin
            emit(cnt_low(12));
            emit(rr(32'h00100000, 13, 12, 12)); // 紧邻 EXE 前递.
            emit(cnt_high(14));
            emit(NOP);
            emit(rr(32'h00100000, 15, 14, 14)); // 隔一条指令, MEM 前递.
        end
        finish_program();
        run_case(1'b1, 64'h12345678ffffffd0);
        if (carry_events == 0 || low_reads != 16 || high_reads != 16
                || es_count_fwd == 0 || ms_count_fwd == 0)
            fail("carry or EXE/MEM counter forwarding was not exercised");

        prepare_case("64-bit wraparound");
        for (integer n = 0; n < 32; n = n + 1) begin
            emit(cnt_low(12));
            emit(cnt_high(13));
        end
        finish_program();
        run_case(1'b1, 64'hffffffffffffffd0);
        if (wrap_events == 0 || low_reads != 32 || high_reads != 32)
            fail("64-bit wraparound was not exercised");

        prepare_case("division stall, multiply, load/store and CSR independence");
        emit_li(10, DATA_BASE);
        emit_li(8, 32'd123456);
        emit_li(9, 32'd7);
        emit(cnt_low(12));
        emit(rr(32'h00200000, 11, 8, 9));
        emit(cnt_low(13));
        emit(rr(32'h00100000, 14, 13, 13));
        emit(rr(32'h001c0000, 15, 11, 9));
        emit(rr(32'h00100000, 16, 15, 15));
        emit(ri(32'h29800000, 13, 10, 0));
        emit(ri(32'h28800000, 17, 10, 0));
        emit(rr(32'h00100000, 18, 17, 17));
        emit(csr_inst(8, 1, TID));
        emit(cnt_low(19));
        emit(csr_inst(9, 1, TCFG)); // 写 TCFG 也不能重置 Stable Counter.
        emit(cnt_low(20));
        emit(cnt_id(21));
        finish_program();
        run_case(1'b0, 64'b0);
        if (stall_cycles < 20 || low_reads < 4 || expected_stores != 1)
            fail("division stall or memory scenarios were not exercised");

        prepare_case("syscall/ertn flush, killed counter read/store/CSR write");
        emit_li(10, DATA_BASE);
        emit_li(7, 32'h55);
        emit_li(8, 32'h1111ffff);
        emit(csr_inst(8, 1, TID));
        emit_li(8, 32'hffffffff); // 错路径 CSR 写若泄漏, 会破坏 TID.
        emit_li(9, BOOT + 32'h800);
        emit(csr_inst(9, 1, EENTRY));
        emit(cnt_low(12));
        emit(SYSCALL);
        rom[ip] = cnt_id(25);
        rom[ip+1] = ri(32'h29800000, 7, 10, 0);
        rom[ip+2] = csr_inst(8, 1, TID);
        resume_ip = ip + 3;
        // 处理程序先执行, 期望提交顺序也先记录处理程序, 再记录返回后的主程序.
        ip = 'h800 / 4;
        emit(csr_inst(20, 0, ERA));
        emit(ri(32'h02800000, 20, 20, 16));
        emit(csr_inst(20, 1, ERA));
        emit(cnt_id(21));
        emit(cnt_high(22));
        emit(ERTN);
        rom[ip] = cnt_id(26); // ertn 后的年轻指令必须被清掉.
        ip = resume_ip;
        emit(cnt_low(13));
        emit(cnt_id(14));
        emit(ri(32'h28800000, 15, 10, 0));
        emit(rr(32'h00100000, 16, 25, 26)); // 两个被清除的目的 GPR 应保持0.
        finish_program();
        run_case(1'b0, 64'b0);
        if (flush_cycles != 2 || expected_stores != 0 || actual_stores != 0)
            fail("syscall/ertn flush or killed-store scenario was not exercised");

        if (passed_cases != 5)
            $fatal(1, "not all cases executed");
        $display("ALL PASS: ex9 Topic 1 (5/5 cases)");
        $finish;
    end
endmodule
