`ifndef DIVIDER_V
`define DIVIDER_V

module divider (
    input  wire        clk,
    input  wire        reset,
    input  wire        start,      // 单周期启动脉冲
    input  wire        is_signed,
    input  wire [31:0] op_a,       // 被除数
    input  wire [31:0] op_b,       // 除数
    output wire        done,
    output wire [31:0] quotient,
    output wire [31:0] remainder
);

    wire        dividend_neg;
    wire        divisor_neg;
    wire [31:0] dividend_abs;
    wire [31:0] divisor_abs;

    assign dividend_neg = is_signed && op_a[31];
    assign divisor_neg  = is_signed && op_b[31];
    assign dividend_abs = dividend_neg ? (~op_a + 32'd1) : op_a;
    assign divisor_abs  = divisor_neg ? (~op_b + 32'd1) : op_b;

    reg  [31:0] quotient_r;
    reg  [31:0] remainder_r;
    reg  [31:0] divisor_r;
    reg  [ 5:0] iteration_count;
    reg         quotient_neg;
    reg         remainder_neg;
    reg         busy;
    reg         done_r;

    wire [31:0] shifted_remainder;
    wire        can_subtract;

    assign shifted_remainder = {remainder_r[30:0], quotient_r[31]};
    assign can_subtract      = (shifted_remainder >= divisor_r);

    always @(posedge clk) begin
        if (reset) begin
            quotient_r      <= 32'd0;
            remainder_r     <= 32'd0;
            divisor_r       <= 32'd0;
            iteration_count <= 6'd0;
            quotient_neg    <= 1'b0;
            remainder_neg   <= 1'b0;
            busy            <= 1'b0;
            done_r          <= 1'b0;
        end
        else if (start) begin
            quotient_r      <= dividend_abs;
            remainder_r     <= 32'd0;
            divisor_r       <= divisor_abs;
            iteration_count <= 6'd32;
            quotient_neg    <= dividend_neg ^ divisor_neg;
            remainder_neg   <= dividend_neg;
            busy            <= 1'b1;
            done_r          <= 1'b0;
        end
        else if (busy) begin
            quotient_r <= {quotient_r[30:0], can_subtract};
            remainder_r <= can_subtract ? shifted_remainder - divisor_r : shifted_remainder;
            iteration_count <= iteration_count - 6'd1;

            if (iteration_count == 6'd1) begin
                busy   <= 1'b0;
                done_r <= 1'b1;
            end
        end
    end

    assign quotient = quotient_neg ? (~quotient_r + 32'd1) : quotient_r;
    assign remainder = remainder_neg ? (~remainder_r + 32'd1) : remainder_r;
    assign done = done_r;

endmodule

`endif  // DIVIDER_V
