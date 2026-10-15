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
    wire                        es_ready_go;  // ex7
    wire                        es_is_mul;  // ex7
    wire                        es_res_from_csr;  // ex8
    wire [                31:0] ms_fwd_data;
    wire                        ms_res_from_mem;
    wire                        ms_res_from_csr;  // ex8

    // NOTE: ex8 CSR 访问端口, 以及 CSR 模块的输出
    wire [                31:0] csr_rvalue;
    wire                        csr_re;
    wire                        csr_we;
    wire [                13:0] csr_addr;
    wire [                31:0] csr_wmask;
    wire [                31:0] csr_wvalue;
    wire                        wb_ex;
    wire                        ertn_flush;
    wire [                31:0] wb_pc;
    wire [                 5:0] wb_ecode;
    wire [                 8:0] wb_esubcode;
    wire [                31:0] ex_entry;
    wire [                31:0] ertn_entry;

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
        .es_fwd_data    (es_fwd_data),
        .es_ready_go    (es_ready_go),      // ex7
        .es_is_mul      (es_is_mul),        // ex7
        .es_res_from_csr(es_res_from_csr),  // ex8
        .ms_fwd_data    (ms_fwd_data),
        .ms_res_from_mem(ms_res_from_mem),
        .ms_res_from_csr(ms_res_from_csr)   // ex8
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
        .es_res_from_mem(es_res_from_mem),
        .es_ready_go    (es_ready_go),      // ex7
        .es_is_mul      (es_is_mul),        // ex7
        .es_res_from_csr(es_res_from_csr)   // ex8
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
        .ms_res_from_mem(ms_res_from_mem),
        .ms_res_from_csr(ms_res_from_csr)   // ex8
    );

    WB_stage u_wb_stage (
        .clk            (clk),
        .reset          (reset),
        .ws_allowin     (ws_allowin),
        .ms_to_ws_valid (ms_to_ws_valid),
        .ms_to_ws_bus   (ms_to_ws_bus),
        .ws_to_rf_bus   (ws_to_rf_bus),
        // NOTE: ex8
        .csr_rvalue     (csr_rvalue),
        .csr_re         (csr_re),
        .csr_we         (csr_we),
        .csr_addr       (csr_addr),
        .csr_wmask      (csr_wmask),
        .csr_wvalue     (csr_wvalue),
        .wb_ex          (wb_ex),
        .ertn_flush     (ertn_flush),
        .wb_pc          (wb_pc),
        .wb_ecode       (wb_ecode),
        .wb_esubcode    (wb_esubcode),
        .ws_pc          (ws_pc),
        .ws_rf_we       (ws_rf_we),
        .ws_dest        (ws_dest),
        .ws_final_result(ws_final_result)
    );

    // NOTE: ex8 异常和中断还没实现跳转, 先只把 WB 的事件接过来改 CSR
    //       ex_entry / ertn_entry 也要等做 flush 和取指重定向时再接入 IF
    CSR u_csr (
        .clk        (clk),
        .reset      (reset),
        .csr_re     (csr_re),
        .csr_addr   (csr_addr),
        .csr_rvalue (csr_rvalue),
        .csr_we     (csr_we),
        .csr_wmask  (csr_wmask),
        .csr_wvalue (csr_wvalue),
        .wb_ex      (wb_ex),
        .wb_pc      (wb_pc),
        .wb_ecode   (wb_ecode),
        .wb_esubcode(wb_esubcode),
        .ertn_flush (ertn_flush),
        .ex_entry   (ex_entry),
        .ertn_entry (ertn_entry)
    );

    assign debug_wb_pc       = ws_pc;
    assign debug_wb_rf_we    = {4{ws_rf_we}};
    assign debug_wb_rf_wnum  = ws_dest;
    assign debug_wb_rf_wdata = ws_final_result;

endmodule
