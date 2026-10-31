`ifndef UART_MMIO_V
`define UART_MMIO_V

`define UART_REG_STATUS 8'h00
`define UART_REG_TXDATA 8'h04
`define UART_REG_RXDATA 8'h08

`define UART_STAT_TX_READY 0
`define UART_STAT_RX_VALID 1

module uart_mmio (
    input wire clk,
    input wire reset,

    input  wire        sel,     // 本次地址是否选中了UART
    input  wire [ 3:0] we,      // 写TXDATA时是能we[0]
    input  wire        commit,  // 当前上升沿是否真正完成一次访问
    input  wire [31:0] wdata,   // 提交给TX的发送数据，使用低8位
    input  wire [ 7:0] addr_off,
    output wire [31:0] rdata,

    input  wire uart_rx,
    output wire uart_tx
);

    // 连接 TX 模块
    wire    tx_busy;
    wire    tx_start;

    // RX 新字节通知
    wire    rx_pulse;
    wire    [7:0] rx_byte;

    reg     [7:0] rx_buf;
    reg     rx_pending;

    // 组合逻辑产生输出
    reg [31:0] rdata_r;

    wire    access_fire;
    wire    read_rx;

    assign access_fire = sel && commit;

    assign read_rx = access_fire
                  && (we == 4'b0000)
                  && (addr_off == `UART_REG_RXDATA);

    assign tx_start = !reset
                      && access_fire
                      && (addr_off == `UART_REG_TXDATA)
                      && we[0]
                      && !tx_busy;

    uart_tx u_tx(
        .clk        (clk),
        .reset      (reset),
        .baud_sel   (2'd1),
        .tx_start   (tx_start),
        .tx_busy    (tx_busy),
        .tx_data    (wdata[7:0]),
        .uart_tx    (uart_tx)
    );

    uart_rx u_rx (
        .clk        (clk),
        .reset      (reset),
        .baud_sel   (2'd1),
        .uart_rx    (uart_rx),
        .rx_valid   (rx_pulse),
        .rx_data    (rx_byte)
    );


    // 缓冲区更新
    always @(posedge clk) begin
        if(reset) begin
            rx_buf      <= 8'd0;
            rx_pending  <= 1'd0;
        end
        else begin
            if(read_rx) begin
                rx_pending <= 1'b0;
            end

            //有新写入且有空间
            if(rx_pulse && (!rx_pending || read_rx)) begin
                rx_pending  <= 1'b1;
                rx_buf      <= rx_byte;
            end
        end
    end


    always @(*) begin
        rdata_r = 32'd0;

        if(sel) begin
            case (addr_off)
                `UART_REG_STATUS : begin
                    rdata_r[`UART_STAT_TX_READY] = !tx_busy;
                    rdata_r[`UART_STAT_RX_VALID] = rx_pending;
                end

                `UART_REG_RXDATA: begin
                    if(rx_pending) begin
                        rdata_r = {24'b0,rx_buf};
                    end
                end

                default:begin
                    rdata_r = 32'd0;
                end
            endcase
        end
    end

    assign rdata = rdata_r;

endmodule

`endif
