`ifndef UART_TX_V
`define UART_TX_V

`define UART_FRAME_WD 10

`define UART_BAUD_SEL_9600 2'd0
`define UART_BAUD_SEL_115200 2'd1
`define UART_DIV_9600 16'd10417
`define UART_DIV_115200 16'd868

`define UTX_IDLE 2'd0
`define UTX_START 2'd1
`define UTX_DATA 2'd2
`define UTX_STOP 2'd3

module uart_tx (
    input wire clk,
    input wire reset,

    input  wire [1:0] baud_sel,
    input  wire       tx_start,
    input  wire [7:0] tx_data,
    output wire       tx_busy,
    output wire       uart_tx
);

    // todo!

endmodule

`endif
