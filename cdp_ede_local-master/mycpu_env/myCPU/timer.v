`ifndef TIMER_V
`define TIMER_V

// 中断定时器
module timer (
    input wire clk,
    input wire reset,

    input wire        timer_we,
    input wire [13:0] timer_addr,
    input wire [31:0] timer_wmask,
    input wire [31:0] timer_wvalue,

    input  wire        timer_re,
    input  wire [13:0] timer_raddr,
    output reg  [31:0] timer_rvalue,

    output wire timer_irq
);

    // NOTE: 与 CSR.v 的编号定义保持一致
    localparam [13:0] TIMER_TCFG = 14'h0041;
    localparam [13:0] TIMER_TVAL = 14'h0042;
    localparam [13:0] TIMER_TICLR = 14'h0044;

    // NOTE: 停止值同时用于复位和单次到期, 使停止状态下既不递减也不重复置标志
    localparam [31:0] TIMER_STOPPED = 32'hffffffff;

    reg  [31:0] tcfg;
    reg  [31:0] timer_cnt;
    reg         ti_flag;  // estat.is[11] 表示 time interrupt 是否启用

    wire [31:0] tcfg_next;
    assign tcfg_next = (tcfg & ~timer_wmask) | (timer_wvalue & timer_wmask);

    assign timer_irq = ti_flag;  // estat.is[11] 对外的名称, 当前有一个 timer interrupt request

    always @(posedge clk) begin
        if (reset) begin
            tcfg <= 32'b0;
        end
        else if (timer_we && timer_addr == TIMER_TCFG) begin
            tcfg <= tcfg_next;
        end
    end

    always @(posedge clk) begin
        if (reset) begin
            timer_cnt <= TIMER_STOPPED;
        end
        else if (timer_we && timer_addr == TIMER_TCFG) begin
            if (tcfg_next[0]) begin
                timer_cnt <= {tcfg_next[31:2], 2'b0};
            end
        end
        else if (tcfg[0] && timer_cnt != TIMER_STOPPED) begin
            if (timer_cnt != 32'b0) begin
                timer_cnt <= timer_cnt - 32'd1;
            end
            else if (tcfg[1]) begin
                timer_cnt <= {tcfg[31:2], 2'b0};
            end
            else begin
                timer_cnt <= TIMER_STOPPED;
            end
        end
    end


    always @(posedge clk) begin
        if (reset) begin
            ti_flag <= 1'b0;
        end
        else if (tcfg[0] && timer_cnt == 32'b0) begin
            ti_flag <= 1'b1;
        end
        else if (timer_we && timer_addr == TIMER_TICLR && timer_wmask[0] && timer_wvalue[0]) begin
            ti_flag <= 1'b0;
        end
    end

    always @(*) begin
        timer_rvalue = 32'b0;
        if (timer_re) begin
            case (timer_raddr)
                TIMER_TCFG: timer_rvalue = tcfg;
                TIMER_TVAL: timer_rvalue = timer_cnt;
                default:    timer_rvalue = 32'b0;
            endcase
        end
    end

endmodule

`endif  // TIMER_V
