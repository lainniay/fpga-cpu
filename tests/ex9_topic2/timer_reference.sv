`timescale 1ns / 1ps

// NOTE: ex9, 独立参考模型用绝对到期拍数计算剩余值, 不逐拍复制 RTL 的减法器.
// 约定与指导书一致: 装入 L 后, 第 L+1 个后续上升沿处理到期.
module ex9_timer_reference (
    input wire clk, reset, write_enable,
    input wire [13:0] address,
    input wire [31:0] write_mask, write_value,
    output reg [31:0] configuration = 32'b0,
    output wire [31:0] remaining,
    output reg pending = 1'b0,
    output reg [31:0] expiry_count = 32'b0,
    output reg [31:0] reload_count = 32'b0
);
    reg running = 1'b0;
    reg [31:0] frozen = 32'hffffffff;
    reg [63:0] epoch = 64'b0;
    reg [63:0] deadline = 64'b0;
    wire [63:0] distance = deadline - epoch - 64'd1;
    wire [31:0] replacement =
        (configuration & ~write_mask) | (write_value & write_mask);
    wire expires = running && (epoch + 64'd1 == deadline);
    assign remaining = running ? distance[31:0] : frozen;

    always @(posedge clk) begin
        if (reset) begin
            epoch <= 64'b0;
            deadline <= 64'b0;
            configuration <= 32'b0;
            running <= 1'b0;
            frozen <= 32'hffffffff;
            pending <= 1'b0;
            expiry_count <= 32'b0;
            reload_count <= 32'b0;
        end else begin
            epoch <= epoch + 64'd1;
            if (expires) begin
                pending <= 1'b1;
                expiry_count <= expiry_count + 32'd1;
            end else if (write_enable && address == 14'h0044
                         && write_mask[0] && write_value[0]) begin
                pending <= 1'b0;
            end

            if (write_enable && address == 14'h0041) begin
                configuration <= replacement;
                running <= replacement[0];
                if (replacement[0]) begin
                    deadline <= epoch + 64'd2 + {32'b0, replacement[31:2], 2'b0};
                end else begin
                    frozen <= remaining;
                end
            end else if (expires) begin
                if (configuration[1]) begin
                    deadline <= epoch + 64'd2 + {32'b0, configuration[31:2], 2'b0};
                    reload_count <= reload_count + 32'd1;
                end else begin
                    running <= 1'b0;
                    frozen <= 32'hffffffff;
                end
            end
        end
    end
endmodule
