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

module uart_tx #(
    parameter [15:0] DIV_9600   = `UART_DIV_9600,
    parameter [15:0] DIV_115200 = `UART_DIV_115200
) (
    input wire clk,
    input wire reset,

    input  wire [1:0] baud_sel,
    input  wire       tx_start,
    input  wire [7:0] tx_data,
    output wire       tx_busy,
    output wire       uart_tx
);

//8N1
reg [7:0] data_reg;


reg [1:0] state;
reg [13:0] baud_cnt;
reg [13:0] baud_div;
reg [2:0] bit_cnt;

always @(posedge clk) begin
    if(reset) begin
        state<=`UTX_IDLE;
        bit_cnt<=3'b0;
        baud_cnt<=14'b0;
        baud_div<=14'b0;
        data_reg<=8'b0;
    end
    else begin
        case(state)
            `UTX_IDLE:
            if(tx_start==1'b1 && tx_busy==1'b0) begin
                baud_div<=(baud_sel==2'b0) ? DIV_9600 : DIV_115200;
                baud_cnt<=14'b0;
                data_reg<=tx_data;
                state<=`UTX_START;
            end
            `UTX_START:begin
                if(baud_cnt==baud_div-1) begin
                    baud_cnt<=14'b0;
                    bit_cnt<=3'b0;
                    state<=`UTX_DATA;
                end
                else baud_cnt<=baud_cnt+1;
            end
            `UTX_DATA:begin
                if(baud_cnt==baud_div-1)begin
                    bit_cnt<=bit_cnt+1;
                    if(bit_cnt==3'b111) begin
                    baud_cnt<=14'b0;
                    state<=`UTX_STOP;
                    end
                    else baud_cnt<=14'b0;
                end
                else
                baud_cnt<=baud_cnt+1;
            end
            `UTX_STOP:begin
                if(baud_cnt==baud_div-1) begin
                    baud_cnt<=14'b0;
                    state<=`UTX_IDLE;
                end
                else
                baud_cnt<=baud_cnt+1;
            end
            default: begin
                    state<=`UTX_IDLE;
            end
        endcase
        end
    end

assign tx_busy=~(state==`UTX_IDLE);
assign uart_tx= (state==`UTX_START) ? 1'b0:
(state==`UTX_DATA) ? data_reg[bit_cnt] : 1'b1;
endmodule

`endif
