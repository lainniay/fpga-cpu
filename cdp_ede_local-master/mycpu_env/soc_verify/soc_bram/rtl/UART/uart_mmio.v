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

    input  wire        sel,
    input  wire [ 3:0] we,
    input  wire        commit,
    input  wire [31:0] wdata,
    input  wire [ 7:0] addr_off,
    output wire [31:0] rdata,

    input  wire uart_rx,
    output wire uart_tx
);

    // todo!

endmodule

`endif
