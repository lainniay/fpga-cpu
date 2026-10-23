`timescale 1ns/1ps
`include "mycpu_head.v"

// NOTE: ex9 单独覆盖 IF 的背压, 错误 PC 保持, flush 优先级和同步 RAM 旧数据.
module ex9_if_tb;
    reg clk = 0;
    always #5 clk = ~clk;
    reg reset = 1, ds_allowin = 1, flush = 0;
    reg [31:0] redirect_pc = 0;
    reg [`BR_BUS_WD-1:0] br_bus = 0;
    wire valid, en;
    wire [`FS_TO_DS_BUS_WD-1:0] bus_value;
    wire [31:0] addr, wdata;
    wire [3:0] we;
    reg [31:0] rdata = 32'h06483800;
    IF_stage dut (
        .clk(clk), .reset(reset), .ds_allowin(ds_allowin),
        .fs_to_ds_valid(valid), .fs_to_ds_bus(bus_value),
        .flush(flush), .redirect_pc(redirect_pc), .br_bus(br_bus),
        .inst_sram_en(en), .inst_sram_we(we), .inst_sram_addr(addr),
        .inst_sram_wdata(wdata), .inst_sram_rdata(rdata)
    );
    always @(posedge clk) if (en) rdata <= 32'h06483800;
    task check(input [31:0] pc, input fault);
        begin
            if (valid !== 1 || bus_value[31:0] !== pc || bus_value[64] !== fault)
                $fatal(1, "IF PC/exception pairing failed: %h", bus_value);
            if (fault && bus_value[63:32] !== 0) $fatal(1, "stale SRAM data reached ID");
        end
    endtask
    initial begin
        repeat (3) @(negedge clk);
        reset = 0;
        @(negedge clk);
        check(32'h1c000000, 0);
        br_bus = {1'b1, 32'h80000203};
        #1;
        if (en !== 0) $fatal(1, "unaligned branch issued a fetch");
        @(negedge clk);
        br_bus = 0;
        ds_allowin = 0;
        #1;
        check(32'h80000203, 1);
        repeat (4) begin
            @(negedge clk);
            check(32'h80000203, 1);
            if (en !== 0) $fatal(1, "stalled IF issued a fetch");
        end
        // NOTE: ex9 背压期间 flush 仍必须锁存新的错误返回地址.
        flush = 1;
        redirect_pc = 32'h90000101;
        #1;
        if (en !== 0) $fatal(1, "unaligned redirect issued a fetch");
        @(negedge clk);
        flush = 0;
        #1;
        check(32'h90000101, 1);
        flush = 1;
        redirect_pc = 32'h1c001000;
        #1;
        if (en !== 1 || addr !== redirect_pc) $fatal(1, "flush failed to override backpressure");
        @(negedge clk);
        flush = 0;
        #1;
        check(32'h1c001000, 0);
        if (bus_value[63:32] !== 32'h06483800) $fatal(1, "redirect fetch data mismatch");
        $display("PASS IF ADEF/backpressure/flush");
        $finish;
    end
endmodule
