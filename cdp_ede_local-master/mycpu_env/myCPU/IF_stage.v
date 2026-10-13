`ifndef IF_STAGE_V
`define IF_STAGE_V

`include "mycpu_head.v"

module IF_stage (
    input wire clk,
    input wire reset,

    // IF -> ID 
    input  wire                        ds_allowin,
    output wire                        fs_to_ds_valid,
    output wire [`FS_TO_DS_BUS_WD-1:0] fs_to_ds_bus,

    // ID -> IF, 指导指令跳转
    input wire [`BR_BUS_WD-1:0] br_bus,

    // Inst SRAM
    output wire        inst_sram_en,
    output wire [ 3:0] inst_sram_we,
    output wire [31:0] inst_sram_addr,
    output wire [31:0] inst_sram_wdata,
    input  wire [31:0] inst_sram_rdata
);

    reg  fs_valid;
    wire fs_ready_go;
    wire fs_allowin;
    wire to_fs_valid;

    wire [31:0] seq_pc, next_pc;
    wire br_taken;
    wire [31:0] br_target;
    assign {br_taken, br_target} = br_bus;

    // NOTE: fs_pc 是 IF 实际上的 PC
    reg  [31:0] fs_pc;
    wire [31:0] fs_inst = inst_sram_rdata;
    assign fs_to_ds_bus   = {fs_inst, fs_pc};

    assign to_fs_valid    = ~reset;
    // NOTE: 正常情况下 IF 的下一个 PC
    assign seq_pc         = fs_pc + 32'h4;
    // NOTE: next_pc 是 IF 的下一个 PC
    assign next_pc        = br_taken ? br_target : seq_pc;

    assign fs_ready_go    = 1'b1;
    assign fs_allowin     = !fs_valid || (fs_ready_go && ds_allowin);
    assign fs_to_ds_valid = fs_valid && fs_ready_go && !br_taken;

    always @(posedge clk) begin
        if (reset) begin
            fs_valid <= 1'b0;
        end
        else if (fs_allowin) begin
            fs_valid <= to_fs_valid;
        end
    end

    always @(posedge clk) begin
        if (reset) begin
            fs_pc <= 32'h1bfffffc;
        end
        else if (to_fs_valid && fs_allowin) begin
            fs_pc <= next_pc;
        end
    end

    assign inst_sram_en    = to_fs_valid && fs_allowin;
    // NOTE: IF 不写入 SRAM
    assign inst_sram_we    = 4'h0;
    assign inst_sram_addr  = next_pc;
    assign inst_sram_wdata = 32'b0;

endmodule

`endif  // IF_STAGE_V
