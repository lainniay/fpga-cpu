`ifndef MEM_STAGE_V
`define MEM_STAGE_V

`include "mycpu_head.v"

module MEM_stage (
    input wire clk,
    input wire reset,

    // NOTE: ex8
    input wire flush,

    // MEM -> WB
    input  wire                        ws_allowin,
    output wire                        ms_to_ws_valid,
    output wire [`MS_TO_WS_BUS_WD-1:0] ms_to_ws_bus,

    // EXE -> MEM
    input  wire                        es_to_ms_valid,
    input  wire [`ES_TO_MS_BUS_WD-1:0] es_to_ms_bus,
    output wire                        ms_allowin,

    input wire [31:0] data_sram_rdata,

    // NOTE: ex2
    output wire [4:0] ms_dest,
    output wire       ms_gr_we,
    output wire       ms_valid,

    // NOTE: ex3
    output wire [31:0] ms_fwd_data,

    // NOTE: ex6 timing: 告诉 ID 本级的 MEM 指令是否是 load
    output wire ms_res_from_mem,

    // NOTE: ex8 告诉 ID 本级的 MEM 指令是否是 csr 指令
    output wire ms_res_from_csr,

    // NOTE: ex8 由于此时, EXE 阶段的 store 会发生访存, 因此需要 syscall/ertn 在 mem 阶段就阻止
    output wire ms_redirect,

    // NOTE: ex9
    output wire ms_csr_pending
);

    // 基本握手协议
    reg  ms_valid_r;
    wire ms_ready_go;
    assign ms_ready_go    = 1'b1;
    assign ms_allowin     = !ms_valid || (ms_ready_go && ws_allowin);
    assign ms_to_ws_valid = ms_valid && ms_ready_go;

    reg  [`ES_TO_MS_BUS_WD-1:0] es_to_ms_bus_r;

    wire [                31:0] ms_pc;
    wire                        mem_we;
    wire                        gr_we;
    wire [                 4:0] dest;
    wire [                31:0] ms_alu_result;
    wire [                31:0] ms_rkd_value;
    wire [                31:0] csr_wmask;  // ex8
    wire [                13:0] csr_addr;  // ex8
    wire                        csr_we;  // ex8
    wire                        res_from_csr;  // ex8
    wire                        ex_ertn;  // ex8
    wire                        ex_syscall;  // ex8
    wire                        res_from_mem;
    wire [                 1:0] mem_size;
    wire                        mem_sign;
    wire                        ex_int;

    assign {
        ex_int,
        ms_pc,
        mem_we,
        gr_we,
        dest,
        ms_alu_result,
        ms_rkd_value,
        csr_wmask,
        csr_addr,
        csr_we,
        res_from_csr,
        ex_ertn,
        ex_syscall,
        res_from_mem,
        mem_size,
        mem_sign
    } = es_to_ms_bus_r;

    // NOTE: ex6
    wire [ 7:0] ms_byte;
    wire [15:0] ms_half;
    wire [31:0] ms_load_data;

    assign ms_byte = (ms_alu_result[1:0] == 2'b00) ? data_sram_rdata[ 7: 0] :
                     (ms_alu_result[1:0] == 2'b01) ? data_sram_rdata[15: 8] :
                     (ms_alu_result[1:0] == 2'b10) ? data_sram_rdata[23:16] :
                                                     data_sram_rdata[31:24];

    assign ms_half = ms_alu_result[1] ? data_sram_rdata[31:16] : data_sram_rdata[15:0];

    // NOTE: ex6 按 mem_size 选宽度, 按 mem_sign 决定扩展方式
    // NOTE: mem_size = 00 => word, 01 => byte, 10 => half word
    assign ms_load_data = (mem_size == 2'b01) ? (mem_sign ? {{24{ms_byte[7] }}, ms_byte} : {24'b0, ms_byte}) :
                          (mem_size == 2'b10) ? (mem_sign ? {{16{ms_half[15]}}, ms_half} : {16'b0, ms_half}) :
                          data_sram_rdata;

    wire [31:0] ms_final_result;
    // NOTE: 最终写回的数据
    assign ms_final_result = res_from_mem ? ms_load_data : ms_alu_result;

    // NOTE: ex8 csr 写数据取原 rd 值, ms_final_result 对 csr 指令是无效的
    assign ms_to_ws_bus = {
        ex_int,  // [121]
        ms_pc,  // [151:120]
        gr_we,  // [119]
        dest,  // [118:114]
        ms_final_result,  // [113:82]
        csr_wmask,  // [81:50]  // ex8
        csr_addr,  // [49:36]  // ex8
        csr_we,  // [35]  // ex8
        res_from_csr,  // [34]  // ex8
        ex_ertn,  // [33]  // ex8
        ex_syscall,  // [32]  // ex8
        ms_rkd_value  // [31:0]  // ex8 csr_wvalue
    };

    always @(posedge clk) begin
        if (reset) begin
            ms_valid_r <= 1'b0;
        end
        // NOTE: ex8 
        else if (flush) begin
            ms_valid_r <= 1'b0;
        end
        else if (ms_allowin) begin
            ms_valid_r <= es_to_ms_valid;
        end
        if (es_to_ms_valid && ms_allowin) begin
            es_to_ms_bus_r <= es_to_ms_bus;
        end
    end

    // NOTE: ex2
    assign ms_valid        = ms_valid_r;
    assign ms_gr_we        = gr_we;
    assign ms_dest         = dest;

    // NOTE: ex8 提前一拍通知 EXE 不要访存, ms_valid 防止 bubble 误报
    assign ms_redirect     = ms_valid && (ex_syscall | ex_ertn | ex_int);

    // NOTE: ex3
    // NOTE: ex6 timing: 只前递已寄存的 ALU 结果; load 数据要等到 WB 才能前递,
    //                  否则 data_ram -> 前递 -> ID 分支比较 -> IF 的组合路径过长
    assign ms_fwd_data     = ms_alu_result;
    assign ms_res_from_mem = res_from_mem;
    assign ms_res_from_csr = res_from_csr;  // ex8

    // NOTE: ex9,
    assign ms_csr_pending  = ms_valid && (csr_we || ex_ertn);

endmodule

`endif
