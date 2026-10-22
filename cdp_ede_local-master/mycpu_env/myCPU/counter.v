`ifndef COUNTER_V
`define COUNTER_V

// NOTE: ex9, 自由运行的 64 位稳定计数器(Stable Counter).
//       每拍自增 1, 不因 valid, stall 或 flush 停止.
//       数值只在 EXE 阶段被 rdcntvl.w / rdcntvh.w 读取, 所以作为 EXE 的
//       子模块例化, 不占用顶层端口.
module counter (
    input  wire        clk,
    input  wire        reset,
    output wire [63:0] cnt_value
);

    reg [63:0] stable_counter;

    always @(posedge clk) begin
        if (reset) begin
            stable_counter <= 64'b0;
        end
        else begin
            stable_counter <= stable_counter + 64'd1;
        end
    end

    assign cnt_value = stable_counter;

endmodule

`endif  // COUNTER_V
