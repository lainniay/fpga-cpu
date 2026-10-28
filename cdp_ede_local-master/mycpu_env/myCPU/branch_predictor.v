`ifndef BRANCH_PREDICTOR_V
`define BRANCH_PREDICTOR_V

`define BP_ENTRY_NUM 64
`define BP_INDEX_WD 6
`define BP_TAG_WD 24

`define BP_CNT_WD 2
`define BP_CNT_STRONG_NT 2'b00
`define BP_CNT_WEAK_NT 2'b01
`define BP_CNT_WEAK_T 2'b10
`define BP_CNT_STRONG_T 2'b11

`define PRED_SEQ 1'b0
`define PRED_TAKEN 1'b1

module branch_predictor (
    input wire clk,
    input wire reset,

    input  wire [31:0] query_pc,
    output wire        pred_hit,
    output wire        pred_taken,
    output wire [31:0] pred_target,

    input wire        upd_valid,
    input wire [31:0] upd_pc,
    input wire        upd_taken,
    input wire [31:0] upd_target
);

    // todo!

endmodule

`endif
