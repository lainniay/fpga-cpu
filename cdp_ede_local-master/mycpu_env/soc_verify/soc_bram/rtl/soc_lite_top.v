/*------------------------------------------------------------------------------
--------------------------------------------------------------------------------
Copyright (c) 2016, Loongson Technology Corporation Limited.

All rights reserved.

Redistribution and use in source and binary forms, with or without modification,
are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this 
list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice, 
this list of conditions and the following disclaimer in the documentation and/or
other materials provided with the distribution.

3. Neither the name of Loongson Technology Corporation Limited nor the names of 
its contributors may be used to endorse or promote products derived from this 
software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND 
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED 
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE 
DISCLAIMED. IN NO EVENT SHALL LOONGSON TECHNOLOGY CORPORATION LIMITED BE LIABLE
TO ANY PARTY FOR DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR 
CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE 
GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) 
HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT 
LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF
THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
--------------------------------------------------------------------------------
------------------------------------------------------------------------------*/

//*************************************************************************
//   > File Name   : soc_top.v
//   > Description : SoC, included cpu, 2 x 3 bridge,
//                   inst ram, confreg, data ram
// 
//           -------------------------
//           |           cpu         |
//           -------------------------
//         inst|                  | data
//             |                  | 
//             |        ---------------------
//             |        |    1 x 2 bridge   |
//             |        ---------------------
//             |             |            |           
//             |             |            |           
//      -------------   -----------   -----------
//      | inst ram  |   | data ram|   | confreg |
//      -------------   -----------   -----------
//
//   > Author      : LOONGSON
//   > Date        : 2017-08-04
//*************************************************************************

`default_nettype none

//for simulation:
//1. if define SIMU_USE_PLL = 1, will use clk_pll to generate cpu_clk/timer_clk,
//   and simulation will be very slow.
//2. usually, please define SIMU_USE_PLL=0 to speed up simulation by assign
//   cpu_clk/timer_clk = clk.
//   at this time, cpu_clk/timer_clk frequency are both 100MHz, same as clk.
`define SIMU_USE_PLL 0 //set 0 to speed up simulation

module soc_lite_top #(
    parameter SIMULATION = 1'b0,
    parameter INST_RAM_ADDR_MSB = 19
)
(
    input  wire        resetn, 
    input  wire        clk,

    //------uart-------
    input  wire        uart_rx,
    output wire        uart_tx,

    //------gpio-------
    output wire [15:0] led,
    output wire [1 :0] led_rg0,
    output wire [1 :0] led_rg1,
    output wire [7 :0] num_csn,
    output wire [6 :0] num_a_g,
    output wire [31:0] num_data,
    input  wire [7 :0] switch, 
    output wire [3 :0] btn_key_col,
    input  wire [3 :0] btn_key_row,
    input  wire [1 :0] btn_step
);
//debug signals
wire [31:0] debug_wb_pc;
wire [3 :0] debug_wb_rf_we;
wire [4 :0] debug_wb_rf_wnum;
wire [31:0] debug_wb_rf_wdata;

//clk and resetn
wire cpu_clk;
wire timer_clk;
(* ASYNC_REG = "TRUE" *) reg [1:0] cpu_resetn_sync;
wire cpu_resetn;
always @(posedge cpu_clk or negedge resetn)
begin
    if (!resetn)
        cpu_resetn_sync <= 2'b00;
    else
        cpu_resetn_sync <= {cpu_resetn_sync[0], 1'b1};
end
assign cpu_resetn = cpu_resetn_sync[1];
generate if(SIMULATION && `SIMU_USE_PLL==0)
begin: speedup_simulation
    assign cpu_clk   = clk;
    assign timer_clk = clk;
end
else
begin: pll
    clk_pll clk_pll
    (
        .clk_in1 (clk),
        .cpu_clk (cpu_clk),
        .timer_clk (timer_clk)
    );
end
endgenerate

//cpu inst sram
wire        cpu_inst_en;
wire [3 :0] cpu_inst_we;
wire [31:0] cpu_inst_addr;
wire [31:0] cpu_inst_wdata;
wire [31:0] cpu_inst_rdata;
//cpu data sram
wire        cpu_data_en;
wire [3 :0] cpu_data_we;
wire [31:0] cpu_data_addr;
wire [31:0] cpu_data_wdata;
wire [31:0] cpu_data_rdata;

//data sram
wire        data_sram_en;
wire [3 :0] data_sram_we;
wire [31:0] data_sram_addr;
wire [31:0] data_sram_wdata;
wire [31:0] data_sram_rdata;
//conf
wire        conf_en;
wire [3 :0] conf_we;
wire [31:0] conf_addr;
wire [31:0] conf_wdata;
wire [31:0] conf_rdata;

//uart
localparam [31:0] UART_ADDR_BASE     = 32'h1faf_1000;
localparam [31:0] UART_ADDR_MASK     = 32'h1fff_ff00;
localparam [15:0] UART_DIV_9600_50M  = 16'd5208;
localparam [15:0] UART_DIV_115200_50M = 16'd434;

wire        uart_sel;
wire [31:0] uart_rdata;
wire [31:0] bridge_rdata;
wire        cpu_data_en_gated;
wire        uart_read;
reg         uart_read_sel_r;
reg  [31:0] uart_rdata_r;

assign uart_sel = (cpu_data_addr & UART_ADDR_MASK) == UART_ADDR_BASE;
assign uart_read = uart_sel && cpu_data_en && (cpu_data_we == 4'b0000);
assign cpu_data_en_gated = cpu_data_en && !uart_sel;
assign cpu_data_rdata = uart_read_sel_r ? uart_rdata_r : bridge_rdata;

always @(posedge cpu_clk) begin
    if (!cpu_resetn) begin
        uart_read_sel_r <= 1'b0;
        uart_rdata_r <= 32'b0;
    end
    else begin
        uart_read_sel_r <= uart_read;
        if (uart_read) begin
            uart_rdata_r <= uart_rdata;
        end
    end
end

//cpu
mycpu_top cpu(
    .clk              (cpu_clk   ),
    .resetn           (cpu_resetn),  //low active

    .inst_sram_en     (cpu_inst_en   ),
    .inst_sram_we     (cpu_inst_we   ),
    .inst_sram_addr   (cpu_inst_addr ),
    .inst_sram_wdata  (cpu_inst_wdata),
    .inst_sram_rdata  (cpu_inst_rdata),
    
    .data_sram_en     (cpu_data_en   ),
    .data_sram_we     (cpu_data_we   ),
    .data_sram_addr   (cpu_data_addr ),
    .data_sram_wdata  (cpu_data_wdata),
    .data_sram_rdata  (cpu_data_rdata),

    //debug
    .debug_wb_pc      (debug_wb_pc      ),
    .debug_wb_rf_we   (debug_wb_rf_we   ),
    .debug_wb_rf_wnum (debug_wb_rf_wnum ),
    .debug_wb_rf_wdata(debug_wb_rf_wdata)
);

//inst ram
inst_ram inst_ram
(
    .clka  (cpu_clk            ),   
    .ena   (cpu_inst_en        ),
    .wea   (cpu_inst_we        ),   //3:0
    .addra (cpu_inst_addr[INST_RAM_ADDR_MSB:2]),
    .dina  (cpu_inst_wdata     ),   //31:0
    .douta (cpu_inst_rdata     )    //31:0
);

bridge_1x2 bridge_1x2(
    .clk             ( cpu_clk         ), // i, 1                 
    .resetn          ( cpu_resetn      ), // i, 1                 

    .cpu_data_en     ( cpu_data_en_gated), // i, 4
    .cpu_data_we     ( cpu_data_we     ), // i, 4                 
    .cpu_data_addr   ( cpu_data_addr   ), // i, 32                
    .cpu_data_wdata  ( cpu_data_wdata  ), // i, 32                
    .cpu_data_rdata  ( bridge_rdata   ), // o, 32

    .data_sram_en    ( data_sram_en    ), // o, 4                 
    .data_sram_we    ( data_sram_we    ), // o, 4                 
    .data_sram_addr  ( data_sram_addr  ), // o, `DATA_RAM_ADDR_LEN
    .data_sram_wdata ( data_sram_wdata ), // o, 32                
    .data_sram_rdata ( data_sram_rdata ), // i, 32                

    .conf_en         ( conf_en         ), // o, 1                 
    .conf_we         ( conf_we         ), // o, 4                 
    .conf_addr       ( conf_addr       ), // o, 32                
    .conf_wdata      ( conf_wdata      ), // o, 32                
    .conf_rdata      ( conf_rdata      )  // i, 32                
 );

//data ram
data_ram data_ram
(
    .clka  (cpu_clk             ),   
    .ena   (data_sram_en        ),
    .wea   (data_sram_we        ),   //3:0
    .addra (data_sram_addr[17:2]),   //15:0
    .dina  (data_sram_wdata     ),   //31:0
    .douta (data_sram_rdata     )    //31:0
);

//uart
uart_mmio #(
    .DIV_9600   (UART_DIV_9600_50M),
    .DIV_115200 (UART_DIV_115200_50M)
) u_uart (
    .clk        ( cpu_clk        ),
    .reset      ( ~cpu_resetn    ),
    .sel        ( uart_sel       ),
    .we         ( cpu_data_we    ),
    .commit     ( cpu_data_en    ),
    .wdata      ( cpu_data_wdata ),
    .addr_off   ( cpu_data_addr[7:0] ),
    .rdata      ( uart_rdata     ),
    .uart_rx    ( uart_rx        ),
    .uart_tx    ( uart_tx        )
);

//confreg
confreg #(.SIMULATION(SIMULATION)) u_confreg
(
    .clk         ( cpu_clk    ),  // i, 1   
    .timer_clk   ( timer_clk  ),  // i, 1   
    .resetn      ( cpu_resetn ),  // i, 1    
    .conf_en     ( conf_en    ),  // i, 1      
    .conf_we     ( conf_we    ),  // i, 4      
    .conf_addr   ( conf_addr  ),  // i, 32        
    .conf_wdata  ( conf_wdata ),  // i, 32         
    .conf_rdata  ( conf_rdata ),  // o, 32         
    .led         ( led        ),  // o, 16   
    .led_rg0     ( led_rg0    ),  // o, 2      
    .led_rg1     ( led_rg1    ),  // o, 2      
    .num_csn     ( num_csn    ),  // o, 8      
    .num_a_g     ( num_a_g    ),  // o, 7      
    .num_data    ( num_data   ),  // o, 32
    .switch      ( switch     ),  // i, 8     
    .btn_key_col ( btn_key_col),  // o, 4          
    .btn_key_row ( btn_key_row),  // i, 4           
    .btn_step    ( btn_step   )   // i, 2   
);

endmodule

