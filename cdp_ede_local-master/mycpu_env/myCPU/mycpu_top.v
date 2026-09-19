`include "mycpu_head.v"
`include "tools.v"

module mycpu_top (
    input  wire        clk,
    input  wire        resetn,
    output wire        inst_sram_en,
    output wire [ 3:0] inst_sram_we,
    output wire [31:0] inst_sram_addr,
    output wire [31:0] inst_sram_wdata,
    input  wire [31:0] inst_sram_rdata,
    output wire        data_sram_en,
    output wire [ 3:0] data_sram_we,
    output wire [31:0] data_sram_addr,
    output wire [31:0] data_sram_wdata,
    input  wire [31:0] data_sram_rdata,
    output wire [31:0] debug_wb_pc,
    output wire [ 3:0] debug_wb_rf_we,
    output wire [ 4:0] debug_wb_rf_wnum,
    output wire [31:0] debug_wb_rf_wdata
);

    reg reset;
    always @(posedge clk) reset <= ~resetn;

    wire [      `BR_BUS_WD-1:0] br_bus;
    wire [`FS_TO_DS_BUS_WD-1:0] fs_to_ds_bus;
    wire [`DS_TO_ES_BUS_WD-1:0] ds_to_es_bus;
    wire [`ES_TO_MS_BUS_WD-1:0] es_to_ms_bus;
    wire [`MS_TO_WS_BUS_WD-1:0] ms_to_ws_bus;
    wire [`WS_TO_RF_BUS_WD-1:0] ws_to_rf_bus;

    wire                        fs_to_ds_valid;
    wire                        ds_to_es_valid;
    wire                        es_to_ms_valid;
    wire                        ms_to_ws_valid;

    wire                        ds_allowin;
    wire                        es_allowin;
    wire                        ms_allowin;
    wire                        ws_allowin;

    wire [                31:0] ws_pc;
    wire                        ws_rf_we;
    wire [                 4:0] ws_dest;
    wire [                31:0] ws_final_result;

    wire [                 4:0] es_dest;
    wire                        es_gr_we;
    wire                        es_valid;

    wire [                 4:0] ms_dest;
    wire                        ms_gr_we;
    wire                        ms_valid;

    wire [                31:0] es_fwd_data;
    wire                        es_res_from_mem;
    wire [                31:0] ms_fwd_data;
    wire                        ms_res_from_mem;

    IF_stage u_if_stage (
        .clk            (clk),
        .reset          (reset),
        .ds_allowin     (ds_allowin),
        .fs_to_ds_valid (fs_to_ds_valid),
        .fs_to_ds_bus   (fs_to_ds_bus),
        .br_bus         (br_bus),
        .inst_sram_en   (inst_sram_en),
        .inst_sram_we   (inst_sram_we),
        .inst_sram_addr (inst_sram_addr),
        .inst_sram_wdata(inst_sram_wdata),
        .inst_sram_rdata(inst_sram_rdata)
    );

    ID_stage u_id_stage (
        .clk           (clk),
        .reset         (reset),
        .es_allowin    (es_allowin),
        .ds_to_es_valid(ds_to_es_valid),
        .ds_to_es_bus  (ds_to_es_bus),
        .ds_allowin    (ds_allowin),
        .fs_to_ds_valid(fs_to_ds_valid),
        .fs_to_ds_bus  (fs_to_ds_bus),
        .br_bus        (br_bus),
        .ws_to_rf_bus  (ws_to_rf_bus),
        // NOTE: ex2
        .es_dest       (es_dest),
        .es_gr_we      (es_gr_we),
        .es_valid      (es_valid),
        .ms_dest       (ms_dest),
        .ms_gr_we      (ms_gr_we),
        .ms_valid      (ms_valid),

        .es_res_from_mem(es_res_from_mem),
        .es_fwd_data   (es_fwd_data),
        .ms_fwd_data   (ms_fwd_data),
        .ms_res_from_mem(ms_res_from_mem)
    );

    EXE_stage u_exe_stage (
        .clk            (clk),
        .reset          (reset),
        .ms_allowin     (ms_allowin),
        .es_to_ms_valid (es_to_ms_valid),
        .es_to_ms_bus   (es_to_ms_bus),
        .ds_to_es_valid (ds_to_es_valid),
        .ds_to_es_bus   (ds_to_es_bus),
        .es_allowin     (es_allowin),
        .data_sram_en   (data_sram_en),
        .data_sram_we   (data_sram_we),
        .data_sram_addr (data_sram_addr),
        .data_sram_wdata(data_sram_wdata),
        // NOTE: ex2
        .es_dest        (es_dest),
        .es_gr_we       (es_gr_we),
        .es_valid       (es_valid),

        .es_fwd_data    (es_fwd_data),
        .es_res_from_mem(es_res_from_mem)
    );

    MEM_stage u_mem_stage (
        .clk            (clk),
        .reset          (reset),
        .ws_allowin     (ws_allowin),
        .ms_to_ws_valid (ms_to_ws_valid),
        .ms_to_ws_bus   (ms_to_ws_bus),
        .es_to_ms_valid (es_to_ms_valid),
        .es_to_ms_bus   (es_to_ms_bus),
        .ms_allowin     (ms_allowin),
        .data_sram_rdata(data_sram_rdata),
        // NOTE: ex2
        .ms_dest        (ms_dest),
        .ms_gr_we       (ms_gr_we),
        .ms_valid       (ms_valid),

        .ms_fwd_data    (ms_fwd_data),
        .ms_res_from_mem(ms_res_from_mem)
    );

    WB_stage u_wb_stage (
        .clk            (clk),
        .reset          (reset),
        .ws_allowin     (ws_allowin),
        .ms_to_ws_valid (ms_to_ws_valid),
        .ms_to_ws_bus   (ms_to_ws_bus),
        .ws_to_rf_bus   (ws_to_rf_bus),
        .ws_pc          (ws_pc),
        .ws_rf_we       (ws_rf_we),
        .ws_dest        (ws_dest),
        .ws_final_result(ws_final_result)
    );

    assign debug_wb_pc       = ws_pc;
    assign debug_wb_rf_we    = {4{ws_rf_we}};
    assign debug_wb_rf_wnum  = ws_dest;
    assign debug_wb_rf_wdata = ws_final_result;

endmodule
