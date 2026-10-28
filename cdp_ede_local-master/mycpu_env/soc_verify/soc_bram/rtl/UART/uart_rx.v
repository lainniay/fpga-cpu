`ifndef UART_RX_V
`define UART_RX_V

`define URX_IDLE 2'd0
`define URX_START 2'd1
`define URX_DATA 2'd2
`define URX_STOP 2'd3

module uart_rx (
    input wire clk,
    input wire reset,

    input  wire [1:0] baud_sel,
    input  wire       uart_rx,
    output wire       rx_valid,
    output wire [7:0] rx_data
);

    // todo!

endmodule

`endif
