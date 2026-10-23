`timescale 1ns/1ps

// NOTE: ex9 另存的测试调度程序仅调用 n48, n50, n52~n57.
// 官方函数体和异常处理程序逐字保留, 原始 mif 和官方比较器均不修改.
module ex9_1_official_tb;
    reg clk = 0;
    always #5 clk = ~clk;
    reg resetn = 0;
    integer count = 0;
    integer cycles = 0;
    integer expected [0:7];
    wire [31:0] num_data;
    soc_lite_top #(.SIMULATION(1'b1)) soc (
        .clk(clk), .resetn(resetn), .switch(8'hff),
        .btn_key_row(4'b0), .btn_step(2'b11), .num_data(num_data)
    );

    initial begin
        expected[0]=48; expected[1]=50; expected[2]=52; expected[3]=53;
        expected[4]=54; expected[5]=55; expected[6]=56; expected[7]=57;
        repeat (10) @(negedge clk);
        resetn = 1;
    end

    always @(posedge clk) if (resetn) begin
        cycles = cycles + 1;
        if (cycles > 200000)
            $fatal(1, "official subset timeout, pc=%h, passed=%0d", soc.debug_wb_pc, count);
        // NOTE: ex9 每个官方函数仅在其内部全部检查成功后累加低位通过计数.
        if (soc.conf_en && soc.conf_we == 4'hf && soc.conf_addr == 32'hbfaff050 && soc.conf_wdata != 0) begin
            if (count >= 8) $fatal(1, "unexpected extra official result");
            if (soc.conf_wdata[31:24] !== expected[count][7:0] ||
                soc.conf_wdata[23:0] !== (count + 1))
                $fatal(1, "official n%0d failed, result=%h, pc=%h", expected[count], soc.conf_wdata, soc.debug_wb_pc);
            $display("PASS official n%0d (unaltered function)", expected[count]);
            count = count + 1;
        end
        if (soc.debug_wb_pc == 32'h1c010088) begin
            if (count != 8) $fatal(1, "official subset ended early");
            $display("PASS official ex9_1 subset: 8 points, %0d cycles", cycles);
            $finish;
        end
    end
endmodule

// NOTE: ex9 独立仿真内存使用同样的同步读/字节写接口, 不读取或覆盖 func/obj.
module inst_ram (
    input wire clka, ena,
    input wire [3:0] wea,
    input wire [17:0] addra,
    input wire [31:0] dina,
    output reg [31:0] douta
);
    reg [31:0] ram [0:262143];
    integer lane;
    function [31:0] bl(input [31:0] pc, input [31:0] target);
        reg [25:0] offset;
        begin
            offset = (target - pc) >> 2;
            bl = {6'h15, offset[15:0], offset[25:16]};
        end
    endfunction
    initial begin
        $readmemb("for_test_obj/ex9_obj/inst_ram.mif", ram);
        if (ram['h4014] !== 32'h56380000 || ram['h1c842] !== 32'h028006f7)
            $fatal(1, "official image layout changed; inspect dispatcher before using subset");
        ram['h4014] = bl(32'h1c010050, 32'h1c0102d8); // test4_init
        ram['h4015] = bl(32'h1c010054, 32'h1c0102f0); // test5_init
        ram['h4016] = 32'h0280bc17;                  // r23 = 47
        ram['h4017] = bl(32'h1c01005c, 32'h1c072108); // n48
        ram['h4018] = 32'h0280c417;                  // r23 = 49
        ram['h4019] = bl(32'h1c010064, 32'h1c074d08); // n50
        ram['h401a] = 32'h0280cc17;                  // r23 = 51
        ram['h401b] = bl(32'h1c01006c, 32'h1c075108); // n52
        ram['h401c] = bl(32'h1c010070, 32'h1c075348); // n53
        ram['h401d] = bl(32'h1c010074, 32'h1c075620); // n54
        ram['h401e] = bl(32'h1c010078, 32'h1c0758f8); // n55
        ram['h401f] = bl(32'h1c01007c, 32'h1c075bd8); // n56
        ram['h4020] = bl(32'h1c010080, 32'h1c075ed0); // n57
        ram['h4021] = 32'h02800000;
        ram['h4022] = 32'h50000000;                  // 独立结束点.
        $writememb("build/ex9_1/subset-inst.mif", ram);
    end
    always @(posedge clka) begin
        if (ena) douta <= ram[addra];
        for (lane = 0; lane < 4; lane = lane + 1)
            if (wea[lane]) ram[addra][8*lane +: 8] <= dina[8*lane +: 8];
    end
endmodule

module data_ram (
    input wire clka, ena,
    input wire [3:0] wea,
    input wire [15:0] addra,
    input wire [31:0] dina,
    output reg [31:0] douta
);
    reg [31:0] ram [0:65535];
    integer lane;
    initial $readmemb("for_test_obj/ex9_obj/data_ram.mif", ram);
    always @(posedge clka) begin
        if (ena) douta <= ram[addra];
        for (lane = 0; lane < 4; lane = lane + 1)
            if (wea[lane]) ram[addra][8*lane +: 8] <= dina[8*lane +: 8];
    end
endmodule
