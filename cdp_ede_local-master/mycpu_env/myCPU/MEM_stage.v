`ifndef MEM_STAGE_V
`define MEM_STAGE_V

`include "mycpu_head.v"

module MEM_stage (
    input wire clk,
    input wire reset,

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
    output wire [31:0] ms_fwd_data
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
    wire                        res_from_mem;
    wire [                 1:0] mem_size;
    wire                        mem_sign;

    assign {
        ms_pc,
        mem_we,
        gr_we,
        dest,
        ms_alu_result,
        ms_rkd_value,
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

    assign ms_to_ws_bus = {ms_pc, gr_we, dest, ms_final_result};

    always @(posedge clk) begin
        if (reset) begin
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
    assign ms_valid = ms_valid_r;
    assign ms_gr_we = gr_we;
    assign ms_dest = dest;

    // NOTE: ex3
    assign ms_fwd_data = ms_final_result;

endmodule

`endif
