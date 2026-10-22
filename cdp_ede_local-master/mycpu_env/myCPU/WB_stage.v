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

    // NOTE: ex8 CSR 读写控制信号
    input  wire [31:0] csr_rvalue,
    output wire        csr_re,
    output wire        csr_we,
    output wire [13:0] csr_addr,
    output wire [31:0] csr_wmask,
    output wire [31:0] csr_wvalue,

    // NOTE: ex8 CSR 状态控制信号
    output wire        wb_ex,
    output wire        ertn_flush,
    output wire [31:0] wb_pc,
    output wire [ 5:0] wb_ecode,
    output wire [ 8:0] wb_esubcode,
    output wire [31:0] wb_vaddr,  //ex9 BADV所需的原始错误地址

    // NOTE: ex8
    output wire flush,

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

    // NOTE: ex8 from bus
    wire [                31:0] ms_csr_wmask;
    wire [                13:0] ms_csr_addr;
    wire                        ms_csr_we;
    wire                        ms_res_from_csr;
    wire [                31:0] ms_csr_wvalue;
    wire                        ms_ex_ertn;  // ex8
    wire                        ms_ex_syscall;  // ex8
    // NOTE: ex9 所有同步异常统一在 WB 提交
    wire ex_ale, ex_adef, ex_break, ex_ine;  // ex9
    wire [31:0] mem_vaddr;  //ex9

    assign {
        ex_ale, mem_vaddr,  //ex9
        ex_adef,  //ex9
        ex_break, ex_ine,  //ex9
        ms_pc,
        gr_we,
        dest,
        ms_final_result,
        ms_csr_wmask,
        ms_csr_addr,
        ms_csr_we,
        ms_res_from_csr,
        ms_ex_ertn,
        ms_ex_syscall,
        ms_csr_wvalue
    } = ms_to_ws_bus_r;

    // NOTE: ex8, 控制 CSR 的 syscall 和 ertn 指令
    assign wb_ex = ws_valid && (ex_adef | ms_ex_syscall | ex_break | ex_ine | ex_ale);  //ex9
    assign ertn_flush = ws_valid && ms_ex_ertn && !wb_ex;

    // NOTE: ex8 
    assign flush = wb_ex | ertn_flush;

    assign wb_pc = ms_pc;

    // NOTE: ex9 取指异常优先于译码异常, 错误取指地址：该条指令的PC
    assign wb_ecode = ex_adef ? 6'h08 : ms_ex_syscall ? 6'h0b :
                      ex_break ? 6'h0c : ex_ine ? 6'h0d : ex_ale ? 6'h09 : 6'h00;
    assign wb_vaddr = ex_adef ? ms_pc : mem_vaddr;  //ex9与选中的异常来源一致
    assign wb_esubcode = 9'b0;

    // NOTE: ex8
    assign csr_re = ws_valid && ms_res_from_csr && !wb_ex;  //ex9

    // NOTE: ex8
    assign csr_we = ws_valid && ms_csr_we && !wb_ex;
    assign csr_addr = ms_csr_addr;
    assign csr_wmask = ms_csr_wmask;

    // NOTE: ex8 写数据用的是总线上带下来的原 rd 值, 不能用 ms_final_result
    assign csr_wvalue = ms_csr_wvalue;

    // NOTE: ex8 csr 指令写回的是 CSR 旧值, 普通指令仍用 MEM 的结果
    wire [31:0] ws_wb_data;
    assign ws_wb_data = ms_res_from_csr ? csr_rvalue : ms_final_result;

    assign ws_pc = ms_pc;
    assign ws_dest = dest;
    assign ws_final_result = ws_wb_data;
    // NOTE: ex8 异常指令不能写通用寄存器
    assign ws_rf_we = ws_valid && gr_we && !wb_ex;

    assign ws_to_rf_bus = {ws_rf_we, ws_dest, ws_wb_data};

    always @(posedge clk) begin
        if (reset) begin
            ws_valid <= 1'b0;
        end
        // NOTE: ex8 : flush 影响的是下一拍, 为了阻止 MEM 的指令进入 WB
        else if (flush) begin
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
