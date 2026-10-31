module sync_ram #(
    parameter ADDR_WIDTH = 16,
    parameter DATA_WIDTH = 32,
    parameter DEPTH = 1 << ADDR_WIDTH
)(
    input  wire                  clk,
    input  wire [ADDR_WIDTH-1:0] address,
    input  wire [DATA_WIDTH/8-1:0] we,
    input  wire                  en,
    input  wire [DATA_WIDTH-1:0] wdata,
    output reg  [DATA_WIDTH-1:0] rdata
);
    reg [DATA_WIDTH-1:0] ram [0:DEPTH-1];
    genvar i;
    for (i = 0; i < DATA_WIDTH/8; i = i + 1) begin
        always @(posedge clk) begin
            if (we[i]) ram[address][i*8 +: 8] <= wdata[i*8 +: 8];
        end
    end
    always @(posedge clk) begin
        if (en) rdata <= ram[address];
    end
endmodule

module inst_ram #(
    parameter ADDR_WIDTH = 18,
    parameter DATA_WIDTH = 32,
    parameter DEPTH = 1 << ADDR_WIDTH
)(
    input  wire clka,
    input  wire ena,
    input  wire [3:0] wea,
    input  wire [ADDR_WIDTH-1:0] addra,
    input  wire [DATA_WIDTH-1:0] dina,
    output wire [DATA_WIDTH-1:0] douta
);
    reg [1023:0] inst_mif;
    sync_ram #(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH), .DEPTH(DEPTH))
        u_ram(
            .clk(clka),
            .address(addra),
            .we(wea),
            .en(ena),
            .wdata(dina),
            .rdata(douta)
        );
    initial begin
        if (!$value$plusargs("INST_MIF=%s", inst_mif))
            inst_mif = "build/combo_e2e/inst_ram.mif";
        $readmemb(inst_mif, u_ram.ram);
    end
endmodule

module data_ram #(
    parameter ADDR_WIDTH = 16,
    parameter DATA_WIDTH = 32,
    parameter DEPTH = 1 << ADDR_WIDTH
)(
    input  wire clka,
    input  wire ena,
    input  wire [3:0] wea,
    input  wire [ADDR_WIDTH-1:0] addra,
    input  wire [DATA_WIDTH-1:0] dina,
    output wire [DATA_WIDTH-1:0] douta
);
    sync_ram #(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH), .DEPTH(DEPTH))
        u_ram(
            .clk(clka),
            .address(addra),
            .we(wea),
            .en(ena),
            .wdata(dina),
            .rdata(douta)
        );
endmodule
