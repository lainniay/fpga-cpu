`ifndef INST_MEM_ADAPTER_V
`define INST_MEM_ADAPTER_V

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

    reg rsp_valid_r;

    assign mem_req_ready = 1'b1;
    assign mem_rsp_valid = rsp_valid_r;
    assign mem_rsp_data = inst_sram_rdata;

    assign inst_sram_en = mem_req_valid && mem_req_ready;
    assign inst_sram_we = 4'b0000;
    assign inst_sram_addr = mem_req_addr;
    assign inst_sram_wdata = 32'b0;

    always @(posedge clk) begin
        if (reset) begin
            rsp_valid_r <= 1'b0;
        end
        else begin
            rsp_valid_r <= mem_req_valid && mem_req_ready;
        end
    end

endmodule

`endif
