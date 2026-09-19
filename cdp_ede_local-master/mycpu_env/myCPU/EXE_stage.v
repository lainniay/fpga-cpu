`ifndef EXE_STAGE_V
`define EXE_STAGE_V

`include "mycpu_head.v"

module EXE_stage (
    input wire clk,
    input wire reset,

    // EXE -> MEM 阶段握手信号
    input  wire                        ms_allowin,
    output wire                        es_to_ms_valid,
    output wire [`ES_TO_MS_BUS_WD-1:0] es_to_ms_bus,

    // ID -> EXE 阶段握手信号
    input  wire                        ds_to_es_valid,
    input  wire [`DS_TO_ES_BUS_WD-1:0] ds_to_es_bus,
    output wire                        es_allowin,

    // Data SRAM, for EXE
    output wire        data_sram_en,
    output wire [ 3:0] data_sram_we,
    output wire [31:0] data_sram_addr,
    output wire [31:0] data_sram_wdata,

    // NOTE: Ex2: 
    output wire [4:0] es_dest,
    output wire       es_gr_we,
    output wire       es_valid,

    // NOTE: Ex3
    output wire [31:0] es_fwd_data,
    output wire        es_res_from_mem
);

    // NOTE: EXE 阶段握手信号
    reg  es_valid_r;  // ex2: 
    wire es_ready_go;
    // todo ex1: EXE 中所有指令一拍完成
    assign es_ready_go    = 1'b1;
    assign es_allowin     = !es_valid || (es_ready_go && ms_allowin);
    assign es_to_ms_valid = es_valid && es_ready_go;

    // 存储 ds_to_es_bus 中的瞬间信号
    reg  [`DS_TO_ES_BUS_WD-1:0] ds_to_es_bus_r;

    wire [                11:0] alu_op;  // [153:142]
    wire [                 1:0] mem_size;  // [141:140]
    wire                        mem_sign;  // [139]
    wire                        src1_is_pc;  // [138]
    wire                        src2_is_imm;  // [137]
    wire                        src2_is_4;  // [136]  reserved, imm 中已包含该常数 4
    wire                        gr_we;  // [135]
    wire                        mem_we;  // [134]
    wire [                 4:0] dest;  // [133:129]
    wire [                31:0] imm;  // [128:97]
    wire [                31:0] rj_value;  // [96:65]
    wire [                31:0] rkd_value;  // [64:33]
    wire [                31:0] es_pc;  // [32:1]
    wire                        res_from_mem;  // [0]

    assign {
        alu_op,
        mem_size,
        mem_sign,
        src1_is_pc,
        src2_is_imm,
        src2_is_4,
        gr_we,
        mem_we,
        dest,
        imm,
        rj_value,
        rkd_value,
        es_pc,
        res_from_mem
    } = ds_to_es_bus_r;


    // NOTE: ALU 
    wire [31:0] alu_src1;
    wire [31:0] alu_src2;
    wire [31:0] es_alu_result;

    assign alu_src1 = src1_is_pc ? es_pc : rj_value;
    assign alu_src2 = src2_is_imm ? imm : rkd_value;

    alu u_alu (
        .alu_op    (alu_op),
        .alu_src1  (alu_src1),
        .alu_src2  (alu_src2),
        .alu_result(es_alu_result)
    );

    // 
    assign data_sram_en = es_valid && (res_from_mem | mem_we);

    // NOTE: ex6 按访存宽度和地址低两位生成字节写使能
    wire [ 3:0] mem_we_byte;
    wire [ 3:0] mem_we_half;
    wire [ 3:0] mem_we_mask;
    wire [31:0] mem_wdata;

    assign mem_we_byte = (es_alu_result[1:0] == 2'b00) ? 4'b0001 :
                         (es_alu_result[1:0] == 2'b01) ? 4'b0010 :
                         (es_alu_result[1:0] == 2'b10) ? 4'b0100 :
                                                         4'b1000;

    assign mem_we_half = es_alu_result[1] ? 4'b1100 : 4'b0011;

    assign mem_we_mask = (mem_size == 2'b01) ? mem_we_byte :
                         (mem_size == 2'b10) ? mem_we_half : 4'hf;

    // NOTE: ex6 写数据按宽度复制到各字节通道, 具体写哪个通道由 we 决定
    assign mem_wdata = (mem_size == 2'b01) ? {4{rkd_value[ 7: 0]}} :
                       (mem_size == 2'b10) ? {2{rkd_value[15: 0]}} :
                       rkd_value;

    assign data_sram_we = (es_valid && mem_we) ? mem_we_mask : 4'h0;
    assign data_sram_addr = es_alu_result;
    assign data_sram_wdata = mem_wdata;

    // EXE -> MEM
    assign es_to_ms_bus = {
        es_pc,  // [106:75]
        mem_we,  // [74]
        gr_we,  // [73]
        dest,  // [72:68]
        es_alu_result,  // [67:36]
        rkd_value,  // [35:4]
        res_from_mem,  // [3]
        mem_size,  // [2:1]
        mem_sign  // [0]
    };

    always @(posedge clk) begin
        if (reset) begin
            es_valid_r <= 1'b0;
        end
        else if (es_allowin) begin
            es_valid_r <= ds_to_es_valid;
        end
        if (ds_to_es_valid && es_allowin) begin
            ds_to_es_bus_r <= ds_to_es_bus;
        end
    end

    // NOTE: Ex2
    assign es_valid = es_valid_r;
    assign es_dest = dest;
    assign es_gr_we = gr_we;

    // NOTE: Ex3, 将 exe 计算的输出导出去
    assign es_fwd_data = es_alu_result;
    assign es_res_from_mem = res_from_mem;

endmodule

`endif  // EXE_STAGE_V
