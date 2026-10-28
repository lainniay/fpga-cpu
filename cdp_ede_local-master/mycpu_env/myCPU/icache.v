`ifndef ICACHE_V
`define ICACHE_V

`define IC_LINE_WD 4
`define IC_SET_NUM 64
`define IC_INDEX_WD 6
`define IC_OFF_WD 2
`define IC_TAG_WD 22

`define IC_IDLE 2'd0
`define IC_FILL 2'd1
`define IC_RESP 2'd2

module icache (
    input wire clk,
    input wire reset,

    input  wire        req_valid,
    input  wire [31:0] req_pc,
    output wire        req_ready,

    output wire        rsp_valid,
    output wire [31:0] rsp_pc,
    output wire [31:0] rsp_inst,
    input  wire        rsp_ready,

    output wire        mem_req_valid,
    output wire [31:0] mem_req_addr,
    input  wire        mem_req_ready,
    input  wire        mem_rsp_valid,
    input  wire [31:0] mem_rsp_data
);

    // todo!

endmodule


`endif
