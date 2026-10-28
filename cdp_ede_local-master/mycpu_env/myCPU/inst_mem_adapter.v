`ifndef INST_MEM_ADAPTER_V
`define INST_MEM_ADAPTER_V

`define IMA_IDLE 2'd0
`define IMA_REQ 2'd1
`define IMA_RESP 2'd2

`define IMA_RD_LATENCY 1

module inst_mem_adapter (
    input wire clk,
    input wire reset,

    input  wire        mem_req_valid,
    input  wire [31:0] mem_req_addr,
    output wire        mem_req_ready,
    output wire        mem_rsp_valid,
    output wire [31:0] mem_rsp_data,

    output wire        inst_sram_en,
    output wire [ 3:0] inst_sram_we,
    output wire [31:0] inst_sram_addr,
    output wire [31:0] inst_sram_wdata,
    input  wire [31:0] inst_sram_rdata
);


    // todo!


endmodule

`endif
