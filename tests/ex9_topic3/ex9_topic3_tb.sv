`timescale 1ns / 1ps

// NOTE: ex9, Topic 3 独立整核测试. 指令解释器检查提交, 参考流水记录接收时的中断决定.
// NOTE: ex9, 测试只通过真实指令配置中断, 不 force 或修改 DUT 内部状态.
module ex9_topic3_tb;
    localparam [31:0] BOOT = 32'h1c000000, DATA_BASE = 32'h00001000;
    localparam [31:0] NOP = 32'h03400000, SYSCALL = 32'h002b0000, ERTN = 32'h06483800;
    localparam [13:0] CRMD = 14'h0000, PRMD = 14'h0001, ECFG = 14'h0004;
    localparam [13:0] ESTAT = 14'h0005, ERA = 14'h0006, EENTRY = 14'h000c;
    localparam [13:0] TID = 14'h0040, TCFG = 14'h0041, TVAL = 14'h0042, TICLR = 14'h0044;
    localparam integer WORDS = 2048, RAM_WORDS = 16;
    localparam integer HANDLER_INDEX = 1536, RESUME_INDEX = 512;
    localparam integer CASES = 18;

    reg clk = 1'b0, resetn = 1'b0;
    always #5 clk = ~clk;
    wire inst_en, data_en;
    wire [3:0] inst_we, data_we, wb_we;
    wire [31:0] inst_addr, inst_wdata, data_addr, data_wdata, wb_pc, wb_data;
    wire [4:0] wb_dest;
    reg [31:0] inst_rdata = NOP, data_rdata = 32'b0;
    reg [31:0] rom [0:WORDS-1];
    reg [31:0] ram [0:RAM_WORDS-1], reference_ram [0:RAM_WORDS-1];
    reg [31:0] registers [0:31], csrs [0:127];
    reg [31:0] next_pc = BOOT, finish_pc, victim_pc;
    reg monitor_active = 1'b0, case_done = 1'b0;
    string case_name = "startup";
    integer ip, case_id, passed = 0, cycles, retired;
    integer interrupts, syscalls, returns, expected_interrupts, expected_syscalls, expected_returns;
    integer actual_stores, committed_stores, actual_loads, committed_loads;
    integer csr_waits, pending_during_csr_wait, pending_during_division, late_interrupt_waits;
    integer ms_memory_blocks, wb_memory_blocks;
    integer total_csr_waits = 0, total_ms_blocks = 0, total_wb_blocks = 0;
    integer total_pending_division = 0, total_late_waits = 0;
    reg [63:0] stable_expected = 64'b0;

    // NOTE: ex9, 参考级仅随接收/传递握手推进. 标志来自独立CSR参考状态, 不复制DUT标志.
    reg es_reference_valid = 1'b0, ms_reference_valid = 1'b0, ws_reference_valid = 1'b0;
    reg es_interrupt = 1'b0, ms_interrupt = 1'b0, ws_interrupt = 1'b0;
    reg [31:0] es_pc_reference = BOOT, ms_pc_reference = BOOT, ws_pc_reference = BOOT;
    reg [31:0] es_instruction = NOP, ms_instruction = NOP, ws_instruction = NOP;
    wire [31:0] timer_configuration, timer_remaining, timer_expiries, timer_reloads;
    wire timer_pending;

    mycpu_top dut (
        .clk(clk), .resetn(resetn),
        .inst_sram_en(inst_en), .inst_sram_we(inst_we),
        .inst_sram_addr(inst_addr), .inst_sram_wdata(inst_wdata), .inst_sram_rdata(inst_rdata),
        .data_sram_en(data_en), .data_sram_we(data_we), .data_sram_addr(data_addr),
        .data_sram_wdata(data_wdata), .data_sram_rdata(data_rdata),
        .debug_wb_pc(wb_pc), .debug_wb_rf_we(wb_we),
        .debug_wb_rf_wnum(wb_dest), .debug_wb_rf_wdata(wb_data)
    );
    // NOTE: ex9, 每个实际CSR写端口先由解释器核对, 再由独立绝对到期拍模型推进定时器.
    ex9_timer_reference reference_timer (
        .clk(clk), .reset(!resetn || dut.reset),
        .write_enable(dut.csr_we && !dut.wb_ex && !dut.ertn_flush),
        .address(dut.csr_addr), .write_mask(dut.csr_wmask), .write_value(dut.csr_wvalue),
        .configuration(timer_configuration), .remaining(timer_remaining),
        .pending(timer_pending), .expiry_count(timer_expiries), .reload_count(timer_reloads)
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
    function automatic [31:0] bne_inst(input integer rj, rd, word_offset);
        bne_inst = 32'h5c000000 | ((word_offset & 65535) << 10) | (rj << 5) | rd;
    endfunction
    function automatic is_load(input [31:0] instruction);
        is_load = ((instruction & 32'hffc00000) == 32'h28800000);
    endfunction
    function automatic is_store(input [31:0] instruction);
        is_store = ((instruction & 32'hffc00000) == 32'h29800000);
    endfunction
    function automatic is_division(input [31:0] instruction);
        is_division = ((instruction & 32'hffff8000) == 32'h00200000);
    endfunction
    function automatic changes_csr(input [31:0] instruction);
        changes_csr = ((instruction[31:24] == 8'h04) && (instruction[9:5] != 0))
                      || (instruction == ERTN);
    endfunction
    function automatic [31:0] read_csr(input [13:0] number);
        case (number)
            ESTAT: read_csr = (csrs[ESTAT] & 32'h7fff0003)
                             | (timer_pending ? 32'h00000800 : 32'b0);
            TCFG: read_csr = timer_configuration;
            TVAL: read_csr = timer_remaining;
            TICLR: read_csr = 32'b0;
            default: read_csr = (number < 128) ? csrs[number] : 32'b0;
        endcase
    endfunction
    function automatic wants_interrupt;
        reg [31:0] status;
        status = read_csr(ESTAT);
        wants_interrupt = csrs[CRMD][2] && ((status[12:0] & csrs[ECFG][12:0]) != 0);
    endfunction

    task automatic fail(input string message);
        $display("[FAIL] case=%0d %s cycle=%0d retired=%0d WB=%08h next=%08h: %s",
            case_id, case_name, cycles, retired, wb_pc, next_pc, message);
        $fatal(1, "ex9 Topic 3 failed");
    endtask
    task automatic equal_word(input [31:0] actual, expected, input string description);
        if (actual !== expected)
            fail($sformatf("%s actual=%08h expected=%08h", description, actual, expected));
    endtask
    task automatic emit(input [31:0] instruction);
        if (ip >= WORDS) $fatal(1, "Topic 3 local ROM overflow");
        rom[ip] = instruction;
        ip = ip + 1;
    endtask
    task automatic li(input integer rd, input [31:0] value);
        emit(32'h14000000 | ((value >> 12) << 5) | rd);
        emit(ri(32'h03800000, rd, rd, value[11:0]));
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
    task automatic nops(input integer count);
        repeat (count) emit(NOP);
    endtask

    task automatic prepare_case(input integer number, input string name,
                                input integer irq_count, syscall_count, return_count);
        @(negedge clk);
        monitor_active = 1'b0;
        resetn = 1'b0;
        case_done = 1'b0;
        case_id = number;
        case_name = name;
        expected_interrupts = irq_count;
        expected_syscalls = syscall_count;
        expected_returns = return_count;
        ip = 0;
        cycles = 0;
        retired = 0;
        interrupts = 0;
        syscalls = 0;
        returns = 0;
        actual_stores = 0;
        committed_stores = 0;
        actual_loads = 0;
        committed_loads = 0;
        csr_waits = 0;
        pending_during_csr_wait = 0;
        pending_during_division = 0;
        late_interrupt_waits = 0;
        ms_memory_blocks = 0;
        wb_memory_blocks = 0;
        next_pc = BOOT;
        finish_pc = 32'hffffffff;
        victim_pc = 32'hffffffff;
        stable_expected = 64'b0;
        es_reference_valid = 1'b0;
        ms_reference_valid = 1'b0;
        ws_reference_valid = 1'b0;
        es_interrupt = 1'b0;
        ms_interrupt = 1'b0;
        ws_interrupt = 1'b0;
        for (integer n = 0; n < WORDS; n = n + 1) rom[n] = NOP;
        for (integer n = 0; n < RAM_WORDS; n = n + 1) begin
            ram[n] = 32'h10203040 + n;
            reference_ram[n] = 32'h10203040 + n;
        end
        for (integer n = 0; n < 32; n = n + 1) registers[n] = 32'b0;
        for (integer n = 0; n < 128; n = n + 1) csrs[n] = 32'b0;
        csrs[CRMD] = 32'h8;
        // GPR没有硬件复位, 用真实指令初始化.
        for (integer n = 1; n < 32; n = n + 1) emit(ri(32'h02800000, n, 0, 0));
        li(10, DATA_BASE);
        li(11, 32'd1000);
        li(13, 32'h55667788);
        li(15, 32'd7);
        li(21, 32'd1);
        write_value(EENTRY, BOOT + 4 * HANDLER_INDEX);
    endtask

    task automatic finish_program;
        finish_pc = BOOT + 4 * ip;
        emit(ri(32'h02800000, 31, 0, 12'h5a5));
        rom[ip] = 32'h50000000;
    endtask

    // NOTE: ex9, 处理程序使用r23~r28作测试专用寄存器, 主程序不把它们当普通工作寄存器.
    // 默认保持ERA以重新执行被中断取消的指令; 特定优先级/SYS用例由软件主动加4.
    task automatic build_handler(input bit advance_era);
        integer saved_ip;
        saved_ip = ip;
        ip = HANDLER_INDEX;
        emit(csr_inst(24, 0, CRMD));
        emit(csr_inst(25, 0, PRMD));
        emit(csr_inst(26, 0, ESTAT));
        emit(csr_inst(27, 0, ERA));
        emit(ri(32'h02800000, 23, 23, 1));
        emit(csr_inst(0, 1, ESTAT));
        emit(ri(32'h02800000, 28, 0, 1));
        emit(csr_inst(28, 1, TICLR));
        if (advance_era) begin
            emit(ri(32'h02800000, 27, 27, 4));
            emit(csr_inst(27, 1, ERA));
        end
        emit(ERTN);
        rom[ip] = ri(32'h29800000, 11, 10, 12);
        rom[ip + 1] = csr_inst(13, 1, TID);
        ip = saved_ip;
    endtask

    task automatic run_case;
        repeat (6) @(negedge clk);
        monitor_active = 1'b1;
        resetn = 1'b1;
        wait (case_done);
        @(negedge clk);
        monitor_active = 1'b0;
        resetn = 1'b0;
        if (interrupts != expected_interrupts || syscalls != expected_syscalls
            || returns != expected_returns) fail("required interrupt/SYS/ERTN count differs");
        if (actual_stores != committed_stores || actual_loads != committed_loads)
            fail("data requests do not match normally committed memory instructions");
        for (integer n = 0; n < RAM_WORDS; n = n + 1)
            equal_word(ram[n], reference_ram[n], $sformatf("RAM[%0d]", n));
        if (case_id == 10 && pending_during_division == 0)
            fail("timer interrupt did not become pending during normal division");
        if (case_id == 11 && timer_reloads < 3)
            fail("periodic timer did not reload at least three times");
        if (case_id == 17 && late_interrupt_waits == 0)
            fail("interrupt with an unavailable GPR operand was not exercised");
        if (case_id >= 12 && case_id <= 14 && pending_during_csr_wait == 0)
            fail("request did not overlap an older CSR state update");
        total_csr_waits = total_csr_waits + csr_waits;
        total_ms_blocks = total_ms_blocks + ms_memory_blocks;
        total_wb_blocks = total_wb_blocks + wb_memory_blocks;
        total_pending_division = total_pending_division + pending_during_division;
        total_late_waits = total_late_waits + late_interrupt_waits;
        passed = passed + 1;
        $display("[PASS] %0d/%0d %s: IRQ=%0d SYS=%0d ERTN=%0d retired=%0d csr_wait=%0d",
            passed, CASES, case_name, interrupts, syscalls, returns, retired, csr_waits);
    endtask

    task automatic check_retirement;
        reg [31:0] instruction, result, following_pc, old_value, mask, candidate, address;
        reg gpr_write, csr_reading, csr_writing;
        integer rd, rj, rk, number;
        instruction = ws_instruction;
        equal_word(wb_pc, next_pc, "architectural next PC");
        following_pc = next_pc + 32'd4;
        rd = instruction[4:0];
        rj = instruction[9:5];
        rk = instruction[14:10];
        result = 32'b0;
        gpr_write = 1'b1;
        csr_reading = 1'b0;
        csr_writing = 1'b0;
        if (ws_interrupt || instruction == SYSCALL) begin
            gpr_write = 1'b0;
            if (ws_interrupt) begin
                if (interrupts == 0 && victim_pc != 32'hffffffff)
                    equal_word(wb_pc, victim_pc, "first interrupted instruction PC");
                interrupts = interrupts + 1;
            end else begin
                syscalls = syscalls + 1;
            end
            csrs[PRMD] = csrs[CRMD] & 32'h7;
            csrs[CRMD] = 32'h8;
            csrs[ERA] = wb_pc;
            csrs[ESTAT] = (csrs[ESTAT] & 32'd3) | (ws_interrupt ? 32'b0 : 32'h000b0000);
            following_pc = csrs[EENTRY];
        end else if (instruction == ERTN) begin
            gpr_write = 1'b0;
            csrs[CRMD] = 32'h8 | (csrs[PRMD] & 32'h7);
            following_pc = csrs[ERA];
            returns = returns + 1;
        end else if (instruction[31:24] == 8'h04) begin
            number = instruction[23:10];
            result = read_csr(number[13:0]);
            csr_reading = 1'b1;
            csr_writing = (rj != 0);
            if (dut.csr_addr !== number[13:0]) fail("wrong CSR address");
            if (csr_writing) begin
                old_value = registers[rd];
                mask = (rj == 1) ? 32'hffffffff : registers[rj];
                equal_word(dut.csr_wmask, mask, "CSR write mask");
                equal_word(dut.csr_wvalue, old_value, "CSR original GPR write data");
                candidate = (result & ~mask) | (old_value & mask);
                case (number)
                    CRMD: csrs[CRMD] = 32'h8 | (candidate & 32'h7);
                    PRMD: csrs[PRMD] = candidate & 32'h7;
                    ECFG: csrs[ECFG] = candidate & 32'h00001bff;
                    ESTAT: csrs[ESTAT] = (csrs[ESTAT] & ~32'd3) | (candidate & 32'd3);
                    ERA, TID: csrs[number] = candidate;
                    EENTRY: csrs[EENTRY] = candidate & 32'hffffffc0;
                    TCFG, TVAL, TICLR: begin end
                    default: fail("test interpreter lacks CSR");
                endcase
            end
        end else if ((instruction & 32'hfe000000) == 32'h14000000) begin
            result = {instruction[24:5], 12'b0};
        end else if ((instruction & 32'hffc00000) == 32'h02800000) begin
            result = registers[rj] + {{20{instruction[21]}}, instruction[21:10]};
        end else if ((instruction & 32'hffc00000) == 32'h03800000) begin
            result = registers[rj] | {20'b0, instruction[21:10]};
        end else if ((instruction & 32'hffff8000) == 32'h00100000) begin
            result = registers[rj] + registers[rk];
        end else if ((instruction & 32'hffff8000) == 32'h001c0000) begin
            result = registers[rj] * registers[rk];
        end else if (is_division(instruction)) begin
            result = $signed(registers[rj]) / $signed(registers[rk]);
        end else if (is_load(instruction) || is_store(instruction)) begin
            address = registers[rj] + {{20{instruction[21]}}, instruction[21:10]};
            if (address < DATA_BASE || address >= DATA_BASE + 4 * RAM_WORDS || address[1:0] != 0)
                fail("interpreter memory address outside local RAM");
            if (is_store(instruction)) begin
                gpr_write = 1'b0;
                reference_ram[(address - DATA_BASE) >> 2] = registers[rd];
                committed_stores = committed_stores + 1;
            end else begin
                result = reference_ram[(address - DATA_BASE) >> 2];
                committed_loads = committed_loads + 1;
            end
        end else if (instruction[31:26] == 6'h14) begin
            gpr_write = 1'b0;
            following_pc = next_pc + {{4{instruction[9]}}, instruction[9:0], instruction[25:10], 2'b0};
        end else if (instruction[31:26] == 6'h16 || instruction[31:26] == 6'h17) begin
            gpr_write = 1'b0;
            if ((instruction[31:26] == 6'h16 && registers[rj] == registers[rd])
                || (instruction[31:26] == 6'h17 && registers[rj] != registers[rd]))
                following_pc = next_pc + {{14{instruction[25]}}, instruction[25:10], 2'b0};
        end else if (instruction == NOP) begin
            result = 32'b0;
        end else begin
            fail($sformatf("test interpreter lacks instruction %08h", instruction));
        end

        if (dut.csr_re !== csr_reading || dut.csr_we !== csr_writing)
            fail("CSR read/write enables differ from instruction semantics");
        if (gpr_write && rd != 0) begin
            if (wb_we !== 4'hf || wb_dest !== rd[4:0] || wb_data !== result)
                fail($sformatf("GPR actual r%0d=%08h we=%h expected r%0d=%08h inst=%08h",
                    wb_dest, wb_data, wb_we, rd, result, instruction));
            registers[rd] = result;
        end else if (gpr_write) begin
            if (wb_we !== 4'b0 && (wb_we !== 4'hf || wb_dest !== 5'b0))
                fail("zero-destination instruction wrote another GPR");
        end else if (wb_we !== 4'b0) begin
            fail("cancelled/exception/non-GPR instruction wrote a GPR");
        end
        registers[0] = 32'b0;
        next_pc = following_pc;
        retired = retired + 1;
        if (wb_pc == finish_pc && !ws_interrupt) case_done = 1'b1;
    endtask

    // Synchronous SRAM: 上升沿请求, 随后一个周期返回数据.
    always @(posedge clk) begin
        if (monitor_active && !dut.reset) begin
            if (inst_en) begin
                if (inst_addr < BOOT || inst_addr >= BOOT + 4 * WORDS || inst_addr[1:0] != 0)
                    fail("fetch outside local ROM");
                inst_rdata <= rom[(inst_addr - BOOT) >> 2];
            end
            if (data_en && data_addr >= DATA_BASE && data_addr < DATA_BASE + 4 * RAM_WORDS) begin
                data_rdata <= ram[(data_addr - DATA_BASE) >> 2];
                if (|data_we) ram[(data_addr - DATA_BASE) >> 2] <= data_wdata;
            end
        end
    end

    always @(posedge clk) begin : monitor
        reg gold_has_int, busy_expected, flush_expected, exception_expected, return_expected;
        reg id_interrupt_expected, accepted, ms_redirect_expected, memory_allowed;
        reg [31:0] id_instruction, expected_address;
        integer rd, rj;
        if (monitor_active) begin
            if (dut.reset === 1'b1) begin
                stable_expected = 64'b0;
                es_reference_valid <= 1'b0;
                ms_reference_valid <= 1'b0;
                ws_reference_valid <= 1'b0;
            end else if (dut.reset === 1'b0) begin
                cycles = cycles + 1;
                if (cycles > 6000) fail("timeout: required interrupt, return or finish did not occur");
                stable_expected = stable_expected + 64'd1;

                // 必须先保存沿前中断判断, 再处理同一沿的WB状态更新.
                gold_has_int = wants_interrupt();
                busy_expected =
                    (es_reference_valid && !es_interrupt && changes_csr(es_instruction))
                    || (ms_reference_valid && !ms_interrupt && changes_csr(ms_instruction))
                    || (ws_reference_valid && !ws_interrupt && changes_csr(ws_instruction));
                exception_expected = ws_reference_valid && (ws_interrupt || ws_instruction == SYSCALL);
                return_expected = ws_reference_valid && !ws_interrupt && ws_instruction == ERTN;
                flush_expected = exception_expected || return_expected;
                ms_redirect_expected = ms_reference_valid
                    && (ms_interrupt || ms_instruction == SYSCALL || ms_instruction == ERTN);
                if (dut.es_valid !== es_reference_valid || dut.ms_valid !== ms_reference_valid
                    || dut.u_wb_stage.ws_valid !== ws_reference_valid)
                    fail("stage valid differs from reference transfer history");
                if (es_reference_valid) begin
                    equal_word(dut.u_exe_stage.es_pc, es_pc_reference, "EXE PC");
                    if (dut.u_exe_stage.ex_int !== es_interrupt) fail("interrupt flag changed/lost in EXE");
                    if ((es_interrupt || !is_division(es_instruction)) && dut.es_ready_go !== 1'b1)
                        fail("cancelled/non-division instruction unnecessarily blocked EXE");
                    if (es_interrupt && dut.u_exe_stage.div_start !== 1'b0)
                        fail("cancelled division started an unnecessary operation");
                end
                if (ms_reference_valid) begin
                    equal_word(dut.u_mem_stage.ms_pc, ms_pc_reference, "MEM PC");
                    if (dut.u_mem_stage.ex_int !== ms_interrupt) fail("interrupt flag changed/lost in MEM");
                end
                if (ws_reference_valid) begin
                    equal_word(wb_pc, ws_pc_reference, "WB PC");
                    if (dut.u_wb_stage.ex_int !== ws_interrupt) fail("interrupt flag changed/lost in WB");
                end
                if (dut.has_int !== gold_has_int) fail("has_int differs from reference CSR status/enables");
                if (dut.wb_ex !== exception_expected || dut.ertn_flush !== return_expected
                    || dut.flush !== flush_expected) fail("wrong WB exception/return/flush decision");
                if (dut.ms_redirect !== ms_redirect_expected) fail("wrong MEM early redirect protection");
                if (exception_expected) begin
                    if (dut.wb_ecode !== (ws_interrupt ? 6'h00 : 6'h0b)
                        || dut.wb_esubcode !== 9'b0) fail("wrong exception code/subcode or priority");
                end

                id_instruction = NOP;
                if (dut.u_id_stage.ds_valid) begin
                    if (dut.u_id_stage.ds_pc < BOOT || dut.u_id_stage.ds_pc >= BOOT + 4 * WORDS
                        || dut.u_id_stage.ds_pc[1:0] != 0) fail("ID PC outside ROM");
                    id_instruction = rom[(dut.u_id_stage.ds_pc - BOOT) >> 2];
                end
                id_interrupt_expected = dut.u_id_stage.ds_valid && gold_has_int
                                        && !busy_expected && !flush_expected;
                if (dut.u_id_stage.csr_pending !== busy_expected)
                    fail("CSR wait misses an older write/ERTN or uses invalid instruction state");
                if (dut.u_id_stage.ex_int !== id_interrupt_expected)
                    fail("ID interrupt decision uses stale CSR state or wrong valid/flush condition");
                if (busy_expected && dut.u_id_stage.ds_ready_go !== 1'b0)
                    fail("ID advanced before older CSR/ERTN completed");
                if (id_interrupt_expected && dut.u_id_stage.ds_ready_go !== 1'b1)
                    fail("interrupt waited for operands of a cancelled instruction");
                if ((busy_expected || id_interrupt_expected || flush_expected) && dut.br_bus[32] !== 1'b0)
                    fail("blocked/cancelled branch redirected IF");
                accepted = dut.ds_to_es_valid && dut.es_allowin && !flush_expected;
                if (dut.u_id_stage.ds_valid && busy_expected) begin
                    csr_waits = csr_waits + 1;
                    if (gold_has_int) pending_during_csr_wait = pending_during_csr_wait + 1;
                end
                if (es_reference_valid && is_division(es_instruction)
                    && !es_interrupt && !dut.es_ready_go && gold_has_int)
                    pending_during_division = pending_during_division + 1;
                if (id_interrupt_expected && dut.u_id_stage.late_use)
                    late_interrupt_waits = late_interrupt_waits + 1;

                // 存储器请求发生在EXE, 不能只在WB看到GPR未写就判为取消成功.
                memory_allowed = es_reference_valid && !es_interrupt
                    && (is_load(es_instruction) || is_store(es_instruction))
                    && !ms_redirect_expected && !flush_expected;
                if (data_en !== memory_allowed) fail("unexpected or missing data SRAM request");
                if (inst_we !== 4'b0) fail("CPU tried to write instruction ROM");
                if (memory_allowed) begin
                    rd = es_instruction[4:0];
                    rj = es_instruction[9:5];
                    // 测试中的访存基址与存数源在开启中断之前初始化, 此后保持不变.
                    expected_address = registers[rj] + {{20{es_instruction[21]}}, es_instruction[21:10]};
                    equal_word(data_addr, expected_address, "EXE memory address");
                    if (expected_address < DATA_BASE || expected_address >= DATA_BASE + 4 * RAM_WORDS
                        || expected_address[1:0] != 0) fail("EXE address outside local RAM");
                    if (is_store(es_instruction)) begin
                        if (data_we !== 4'hf) fail("wrong store write mask");
                        equal_word(data_wdata, registers[rd], "EXE store data");
                        actual_stores = actual_stores + 1;
                    end else begin
                        if (data_we !== 4'b0) fail("load asserted write enables");
                        actual_loads = actual_loads + 1;
                    end
                end else if (data_we !== 4'b0) begin
                    fail("cancelled/younger/invalid instruction asserted SRAM write enables");
                end
                if (es_reference_valid && !es_interrupt
                    && (is_load(es_instruction) || is_store(es_instruction))) begin
                    if (ms_redirect_expected) ms_memory_blocks = ms_memory_blocks + 1;
                    if (flush_expected) wb_memory_blocks = wb_memory_blocks + 1;
                end

                if (ws_reference_valid) begin
                    check_retirement();
                end else if (dut.csr_we !== 1'b0 || dut.csr_re !== 1'b0 || wb_we !== 4'b0) begin
                    fail("invalid WB stage produced a side effect");
                end

                if (flush_expected) begin
                    es_reference_valid <= 1'b0;
                    ms_reference_valid <= 1'b0;
                    ws_reference_valid <= 1'b0;
                end else begin
                    ws_reference_valid <= ms_reference_valid;
                    ws_pc_reference <= ms_pc_reference;
                    ws_instruction <= ms_instruction;
                    ws_interrupt <= ms_interrupt;
                    ms_reference_valid <= es_reference_valid && dut.es_ready_go;
                    ms_pc_reference <= es_pc_reference;
                    ms_instruction <= es_instruction;
                    ms_interrupt <= es_interrupt;
                    if (dut.es_allowin) begin
                        es_reference_valid <= accepted;
                        if (accepted) begin
                            es_pc_reference <= dut.u_id_stage.ds_pc;
                            es_instruction <= id_instruction;
                            es_interrupt <= id_interrupt_expected;
                        end
                    end
                end

                #1;
                equal_word(dut.u_csr.crmd_rvalue, csrs[CRMD], "CRMD after clock");
                equal_word(dut.u_csr.prmd_rvalue, csrs[PRMD], "PRMD after clock");
                equal_word({19'b0, dut.u_csr.ecfg_lie}, csrs[ECFG], "ECFG after clock");
                equal_word(dut.u_csr.estat_rvalue, read_csr(ESTAT), "ESTAT after clock");
                equal_word(dut.u_csr.era, csrs[ERA], "ERA after clock");
                equal_word(dut.u_csr.eentry_rvalue, csrs[EENTRY], "EENTRY after clock");
                equal_word(dut.u_csr.tid, csrs[TID], "TID after clock");
                equal_word(dut.u_csr.u_timer.tcfg, timer_configuration, "TCFG after clock");
                equal_word(dut.u_csr.u_timer.timer_cnt, timer_remaining, "TVAL after clock");
                if (dut.has_int !== wants_interrupt()) fail("has_int did not reflect updated CSR state");
                if (dut.u_exe_stage.u_counter.stable_counter !== stable_expected)
                    fail("Stable Counter stopped/reset during wait or interrupt flush");
            end else begin
                fail("internal reset is unknown");
            end
        end
    end

    initial begin : directed_cases
        integer saved_loop, kind;
        if ($test$plusargs("WAVES")) begin
            $dumpfile("ex9_topic3.vcd");
            $dumpvars(0, ex9_topic3_tb);
        end
        if (csr_inst(13, 1, TID) != 32'h0401002d
            || bne_inst(2, 3, -1) != 32'h5ffffc43)
            $fatal(1, "Topic 3 instruction encoding sanity check failed");

        prepare_case(0, "local/global masks, reserved bit and inactive sources", 0, 0, 0);
        write_value(ECFG, 32'hffffffff);
        emit(csr_inst(7, 0, ECFG));
        exchange(ECFG, 32'h00001bff, 32'h00000802);
        exchange(ECFG, 32'b0, 32'hffffffff);
        emit(csr_inst(7, 0, ECFG));
        write_value(ESTAT, 32'd3);
        nops(8); // 全局关闭, 两个软件请求均不能进入处理程序.
        write_value(ECFG, 32'b0);
        write_value(CRMD, 32'd4);
        nops(8); // 全局开启但局部关闭.
        write_value(ECFG, 32'h00001bfc);
        nops(12); // 只允许没有请求的定时器/外部来源.
        finish_program();
        build_handler(1'b0);
        run_case();

        // 三种置起顺序分别验证: 打开全局允许, 打开局部允许, 软件写请求.
        for (kind = 1; kind <= 9; kind = kind + 1) begin
            case (kind)
                1: prepare_case(kind, "SWI0 cancels ADD, then retries once", 1, 0, 1);
                2: prepare_case(kind, "SWI1 cancels LOAD, then retries once", 1, 0, 1);
                3: prepare_case(kind, "two software requests cancel STORE, then retry once", 1, 0, 1);
                4: prepare_case(kind, "interrupt cancels CSR write and preserves original GPR", 1, 0, 1);
                5: prepare_case(kind, "cancelled DIV neither starts nor blocks EXE", 1, 0, 1);
                6: prepare_case(kind, "interrupt cancels MUL, then retries once", 1, 0, 1);
                7: prepare_case(kind, "cancelled branch does not redirect, retry takes target", 1, 0, 1);
                8: prepare_case(kind, "interrupt has priority over same-instruction SYSCALL", 1, 0, 1);
                9: prepare_case(kind, "interrupt has priority over same-instruction ERTN", 1, 0, 1);
            endcase
            if (kind == 2) begin
                write_value(ESTAT, 32'd2);
                write_value(CRMD, 32'd4);
                write_value(ECFG, 32'd2);
            end else if (kind == 3) begin
                write_value(ECFG, 32'd3);
                write_value(CRMD, 32'd4);
                write_value(ESTAT, 32'd3);
            end else begin
                write_value(ECFG, 32'd1);
                write_value(ESTAT, 32'd1);
                write_value(CRMD, 32'd4);
            end
            victim_pc = BOOT + 4 * ip;
            case (kind)
                1: emit(rr(32'h00100000, 12, 11, 11));
                2: emit(ri(32'h28800000, 12, 10, 0));
                3: emit(ri(32'h29800000, 11, 10, 0));
                4: emit(csr_inst(13, 1, TID));
                5: emit(rr(32'h00200000, 12, 11, 15));
                6: emit(rr(32'h001c0000, 12, 11, 11));
                7: emit(32'h50000800); // b +8, 正常重执行时跳过第一条store.
                8: emit(SYSCALL);
                9: emit(ERTN);
            endcase
            emit(ri(32'h29800000, 11, 10, 4));
            emit(ri(32'h29800000, 11, 10, 8));
            emit(csr_inst(13, 1, TID));
            emit(rr(32'h00100000, 16, 12, 12));
            finish_program();
            build_handler(kind == 8 || kind == 9);
            run_case();
        end

        for (kind = 10; kind <= 11; kind = kind + 1) begin
            if (kind == 10)
                prepare_case(kind, "one-shot timer pending while EXE runs an older DIV", 1, 0, 1);
            else
                prepare_case(kind, "periodic timer enters and returns three times", 3, 0, 3);
            li(22, (kind == 10) ? 32'd1 : 32'd3);
            write_value(ECFG, 32'h00000800);
            write_value(CRMD, 32'd4);
            write_value(TCFG, (kind == 10) ? 32'd9 : 32'h00000083);
            saved_loop = ip;
            emit(rr(32'h00200000, 14, 11, 15));
            emit(rr(32'h00100000, 12, 14, 14));
            emit(bne_inst(23, 22, saved_loop - ip));
            finish_program();
            build_handler(1'b0);
            run_case();
        end

        // 初值0的请求在配置提交后的下一拍置起. 紧随的关闭/清除指令此时已经接收,
        // 年轻ID必须等它完成, 不能根据中途的旧has_int制造多余中断.
        for (kind = 12; kind <= 14; kind = kind + 1) begin
            case (kind)
                12: prepare_case(kind, "older CRMD close wins over newly pending timer", 0, 0, 0);
                13: prepare_case(kind, "older ECFG close wins over newly pending timer", 0, 0, 0);
                14: prepare_case(kind, "older TICLR clear wins over newly pending timer", 0, 0, 0);
            endcase
            li(9, 32'd1);
            write_value(ECFG, 32'h00000800);
            write_value(CRMD, 32'd4);
            write_value(TCFG, 32'd1); // 返回旧TCFG=0到r4, 为紧邻关闭指令准备写数据.
            case (kind)
                12: emit(csr_inst(4, 1, CRMD));
                13: emit(csr_inst(4, 1, ECFG));
                14: emit(csr_inst(9, 1, TICLR));
            endcase
            nops(16);
            emit(csr_inst(7, 0, ESTAT));
            emit(csr_inst(8, 0, CRMD));
            emit(csr_inst(9, 0, ECFG));
            finish_program();
            build_handler(1'b0);
            run_case();
        end

        prepare_case(15, "older SYSCALL blocks unmarked young stores in MEM and WB", 0, 1, 1);
        emit(SYSCALL);
        emit(ri(32'h29800000, 11, 10, 4));
        emit(ri(32'h29800000, 11, 10, 8));
        finish_program();
        build_handler(1'b1);
        run_case();

        prepare_case(16, "ERTN restores PLV3/IE before next instruction interrupt decision", 1, 0, 2);
        write_value(ECFG, 32'd1);
        write_value(ESTAT, 32'd1);
        write_value(PRMD, 32'd7);
        write_value(ERA, BOOT + 4 * RESUME_INDEX);
        emit(ERTN);
        rom[ip] = ri(32'h29800000, 11, 10, 4);
        ip = RESUME_INDEX;
        victim_pc = BOOT + 4 * ip;
        emit(rr(32'h00100000, 12, 11, 11));
        emit(rr(32'h00100000, 16, 12, 12));
        finish_program();
        build_handler(1'b0);
        run_case();

        prepare_case(17, "interrupt bypasses late GPR operand from an older LOAD", 1, 0, 1);
        write_value(ECFG, 32'h00000800);
        write_value(CRMD, 32'd4);
        write_value(TCFG, 32'd1);
        // 配置提交时计数装入0, 下一沿LOAD进入EXE且请求置起, 再下一沿ADD无需等LOAD结果.
        emit(ri(32'h28800000, 12, 10, 0));
        victim_pc = BOOT + 4 * ip;
        emit(rr(32'h00100000, 16, 12, 12));
        finish_program();
        build_handler(1'b0);
        run_case();

        if (passed != CASES || total_csr_waits == 0 || total_ms_blocks == 0
            || total_wb_blocks == 0 || total_pending_division == 0 || total_late_waits == 0)
            $fatal(1, "Topic 3 coverage incomplete: passed=%0d csr=%0d ms=%0d wb=%0d div=%0d late=%0d",
                passed, total_csr_waits, total_ms_blocks, total_wb_blocks,
                total_pending_division, total_late_waits);
        $display("ALL PASS: ex9 Topic 3 (18/18 cases; CSR waits=%0d MEM/WB blocked memory=%0d/%0d)",
            total_csr_waits, total_ms_blocks, total_wb_blocks);
        $finish;
    end

    initial begin
        #1500000;
        $fatal(1, "Topic 3 global watchdog timeout");
    end
endmodule
