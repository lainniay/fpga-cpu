`ifndef WB_STAGE_V
`define WB_STAGE_V

`include "mycpu_head.v"

module WB_stage (
    input wire clk,
    input wire reset,

    output wire                        ws_allowin,
    input  wire                        ms_to_ws_valid,
    input  wire [`MS_TO_WS_BUS_WD-1:0] ms_to_ws_bus,

    // NOTE: WB -> ID BUS, Regfile in ID
    output wire [`WS_TO_RF_BUS_WD-1:0] ws_to_rf_bus,

    // NOTE: 为了 DEBUG, trace 等输出的数据
    output wire [31:0] ws_pc,
    output wire        ws_rf_we,
    output wire [ 4:0] ws_dest,
    output wire [31:0] ws_final_result
);
    
    assign ws_allowin = 1'b1;

    reg                         ws_valid;
    reg  [`MS_TO_WS_BUS_WD-1:0] ms_to_ws_bus_r;

    wire [                31:0] ms_pc;
    wire                        gr_we;
    wire [                 4:0] dest;
    wire [                31:0] ms_final_result;

    assign {ms_pc, gr_we, dest, ms_final_result} = ms_to_ws_bus_r;

    assign ws_pc                                 = ms_pc;
    assign ws_dest                               = dest;
    assign ws_final_result                       = ms_final_result;
    assign ws_rf_we                              = ws_valid && gr_we;

    assign ws_to_rf_bus                          = {ws_rf_we, ws_dest, ws_final_result};

    always @(posedge clk) begin
        if (reset) begin
            ws_valid <= 1'b0;
        end
        else if (ws_allowin) begin
            ws_valid <= ms_to_ws_valid;
        end
        if (ms_to_ws_valid && ws_allowin) begin
            ms_to_ws_bus_r <= ms_to_ws_bus;
        end
    end

endmodule

`endif
