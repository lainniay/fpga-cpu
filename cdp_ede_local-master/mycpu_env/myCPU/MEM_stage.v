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
    output wire       ms_valid
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
    wire                        load_op;

    assign {
        ms_pc,
        mem_we,
        gr_we,
        dest,
        ms_alu_result,
        ms_rkd_value,
        res_from_mem,
        load_op
    } = es_to_ms_bus_r;

    wire [31:0] ms_final_result;
    // NOTE: 最终写回的数据
    assign ms_final_result = res_from_mem ? data_sram_rdata : ms_alu_result;

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

    //NOTE: ex2
    assign ms_valid = ms_valid_r;
    assign ms_gr_we = gr_we;
    assign ms_dest  = dest;

endmodule

`endif
