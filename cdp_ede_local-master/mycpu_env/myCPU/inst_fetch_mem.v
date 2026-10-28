`ifndef INST_FETCH_MEM_V
`define INST_FETCH_MEM_V

// NOTE: 取指存储层, 只封装 ICache 和 SRAM 适配器, 不增加寄存器或改变握手时序
// NOTE: 子模块保留空实现, 后续分别完成缓存和 SRAM 访问逻辑
module inst_fetch_mem (
    input wire clk,
    input wire reset,

    // NOTE: IF -> 存储层, valid && ready 时接受一次取指请求
    input  wire        req_valid,
    input  wire [31:0] req_pc,
    output wire        req_ready,

    // NOTE: 存储层 -> IF, 未握手时必须保持响应有效及其内容不变
    output wire        rsp_valid,
    output wire [31:0] rsp_pc,
    output wire [31:0] rsp_inst,
    input  wire        rsp_ready,

    // Inst SRAM
    output wire        inst_sram_en,
    output wire [ 3:0] inst_sram_we,
    output wire [31:0] inst_sram_addr,
    output wire [31:0] inst_sram_wdata,
    input  wire [31:0] inst_sram_rdata
);

    // NOTE: 缓存填充使用的内部访存接口, 不再暴露给 IF
    // NOTE: 已接受请求的响应必须由 ICache 接收, 此处没有响应背压
    wire mem_req_valid, mem_req_ready, mem_rsp_valid;
    wire [31:0] mem_req_addr, mem_rsp_data;

    icache u_icache (
        .clk          (clk),
        .reset        (reset),
        .req_valid    (req_valid),
        .req_pc       (req_pc),
        .req_ready    (req_ready),
        .rsp_valid    (rsp_valid),
        .rsp_pc       (rsp_pc),
        .rsp_inst     (rsp_inst),
        .rsp_ready    (rsp_ready),
        .mem_req_valid(mem_req_valid),
        .mem_req_addr (mem_req_addr),
        .mem_req_ready(mem_req_ready),
        .mem_rsp_valid(mem_rsp_valid),
        .mem_rsp_data (mem_rsp_data)
    );

    inst_mem_adapter u_inst_mem_adapter (
        .clk            (clk),
        .reset          (reset),
        .mem_req_valid  (mem_req_valid),
        .mem_req_addr   (mem_req_addr),
        .mem_req_ready  (mem_req_ready),
        .mem_rsp_valid  (mem_rsp_valid),
        .mem_rsp_data   (mem_rsp_data),
        .inst_sram_en   (inst_sram_en),
        .inst_sram_we   (inst_sram_we),
        .inst_sram_addr (inst_sram_addr),
        .inst_sram_wdata(inst_sram_wdata),
        .inst_sram_rdata(inst_sram_rdata)
    );

endmodule

`endif  // INST_FETCH_MEM_V
