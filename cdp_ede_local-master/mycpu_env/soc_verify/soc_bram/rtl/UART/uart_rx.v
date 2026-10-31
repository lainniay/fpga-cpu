`ifndef UART_RX_V
`define UART_RX_V

`define URX_IDLE 2'd0 //等待起始下降沿，检测到进入START
`define URX_START 2'd1 //正在等待半个位，确认起始位，仍为低时进入2，否则返回0
`define URX_DATA 2'd2 // 采数据，收完d7进入 3
`define URX_STOP 2'd3 // 等到停止位中心检查电平

module uart_rx #(
    parameter [15:0] DIV_9600   = 16'd10417,
    parameter [15:0] DIV_115200 = 16'd868
) (
    input wire clk,
    input wire reset,

    input  wire [1:0] baud_sel, // 波特率选择
    input  wire       uart_rx,  // 当前串行输入电平
    output wire       rx_valid, // 表示rx_data是否是本次有效接受结果
    output wire [7:0] rx_data   // 接收成功的8位字节
);

    (* ASYNC_REG = "TRUE" *) reg rx_meta;
    (* ASYNC_REG = "TRUE" *) reg rx_sync;
    reg rx_prev;

    always @(posedge clk) begin
        if(reset) begin
            rx_meta <= 1'b1;
            rx_sync <= 1'b1;
            rx_prev <= 1'b1;
        end
        else begin
            rx_meta <= uart_rx;
            rx_sync <= rx_meta;
            rx_prev <= rx_sync;
        end
    end

    wire start_edge; // 是否开始采样
    wire [15:0] selected_div; //选择波特率

    assign start_edge = rx_prev && !rx_sync;
    assign selected_div = (baud_sel == 2'd0) ? DIV_9600 : DIV_115200;

    reg [1:0] state;     // 记录当前阶段
    reg [15:0] frame_div;
    reg [15:0] baud_cnt;
    reg [2:0] bit_index; //决定写入字节的哪个bit
    reg [7:0] data_shift; // 拼出正在接收的字节

    reg [7:0] rx_data_r; // 拼完输出的rx_data
    reg rx_valid_r; //此时的rx_data是否合法

    assign rx_data = rx_data_r;
    assign rx_valid = rx_valid_r;

    always @(posedge clk) begin
        if (reset) begin
            state <= 2'b0;
            frame_div   <= DIV_115200;
            baud_cnt    <= 16'd0;
            bit_index   <= 3'b0;
            data_shift  <= 8'b0;
            rx_data_r   <= 8'b0;
            rx_valid_r  <= 1'b0;
        end
        else begin
            rx_valid_r <= 1'b0;
            case (state)
                `URX_IDLE : begin
                    if(start_edge) begin
                        state <= `URX_START;
                        frame_div   <= selected_div;
                        baud_cnt    <= (selected_div >> 1) - 16'd1;
                        bit_index   <= 3'd0;
                        data_shift  <= 8'b0;
                    end
                end

                `URX_START : begin
                    if (baud_cnt != 16'd0) begin
                        baud_cnt <= baud_cnt - 16'd1;
                    end
                    else if(!rx_sync) begin
                        baud_cnt <= frame_div - 16'd1;
                        state <= `URX_DATA;
                    end
                    else begin
                        state <= `URX_IDLE;
                    end
                end

                `URX_DATA : begin
                    if (baud_cnt != 16'd0) begin
                        //还没到中心采样点
                        baud_cnt <= baud_cnt - 16'd1;
                    end
                    else begin
                        data_shift[bit_index] <= rx_sync;
                        baud_cnt    <= frame_div - 16'd1;

                        if (bit_index != 3'd7) begin
                            bit_index   <= bit_index + 3'd1;
                        end
                        else begin
                            state   <= `URX_STOP;
                        end
                    end
                end

                `URX_STOP : begin
                    if (baud_cnt != 16'd0) begin
                        baud_cnt    <= baud_cnt - 16'd1;
                    end
                    else begin
                        if(rx_sync) begin
                            rx_data_r   <= data_shift;
                            rx_valid_r  <= 1'b1;
                        end

                        //如果还没停止：停止错位
                        state <= `URX_IDLE;
                    end
                end


                default: begin
                    state   <= `URX_IDLE;
                    baud_cnt    <= 16'd0;
                    bit_index   <= 3'd0;
                    data_shift <= 8'd0;
                end
            endcase
        end
    end





endmodule

`endif
