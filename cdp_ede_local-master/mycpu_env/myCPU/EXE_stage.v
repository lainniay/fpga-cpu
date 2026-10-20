`ifndef EXE_STAGE_V
`define EXE_STAGE_V

`include "mycpu_head.v"

module EXE_stage (
    input wire clk,
    input wire reset,

    // NOTE: ex8 
    input wire flush,
    // NOTE: ex8 MEM 里有一条即将重定向的指令, 本级不能访存
    input wire ms_redirect,

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
    output wire        es_res_from_mem,
    output wire        es_is_mul,        // ex7
    output wire        es_res_from_csr,  // ex8

    // NOTE: ex7
    output wire es_ready_go,

    // NOTE: ex9,
    output wire es_csr_pending
);

    // NOTE: EXE 阶段握手信号
    reg         es_valid_r;  // ex2:
    // NOTE: ex7 除法是多周期指令: 未完成时 ready_go = 0
    wire        es_is_div;
    wire        div_start;
    wire        div_done;
    wire        div_signed;
    wire        div_take_rem;
    wire [31:0] div_quotient;
    wire [31:0] div_remainder;
    reg         div_started;

    // NOTE: ex7
    assign es_ready_go    = ex_int || !es_is_div | (div_started & div_done);
    assign es_allowin     = !es_valid || (es_ready_go && ms_allowin);
    assign es_to_ms_valid = es_valid && es_ready_go;

    // 存储 ds_to_es_bus 中的瞬间信号
    reg  [`DS_TO_ES_BUS_WD-1:0] ds_to_es_bus_r;
    wire [                 1:0] cnt_sel; // NOTE: ex9, [212:211], 当前 EXE 指令的计数结果选择.
    wire [                18:0] alu_op;  // [210:192]  // ex7
    wire [                 1:0] mem_size;  // [191:190]
    wire                        mem_sign;  // [189]
    wire                        src1_is_pc;  // [188]
    wire                        src2_is_imm;  // [187]
    wire                        src2_is_4;  // [186]  reserved, imm 中已包含该常数 4
    wire                        gr_we;  // [185]
    wire                        mem_we;  // [184]
    wire [                 4:0] dest;  // [183:179]
    wire [                31:0] imm;  // [178:147]
    wire [                31:0] rj_value;  // [146:115]
    wire [                31:0] rkd_value;  // [114:83]
    wire [                31:0] es_pc;  // [82:51]
    wire [                31:0] csr_wmask;  // [50:19]  // ex8
    wire [                13:0] csr_addr;  // [18:5]  // ex8
    wire                        csr_we;  // [4]  // ex8
    wire                        res_from_csr;  // [3]  // ex8
    wire                        ex_ertn;  // [2]  // ex8
    wire                        ex_syscall;  // [1]  // ex8
    wire                        res_from_mem;  // [0]
    wire                        ex_int;
    assign {
        ex_int,
        cnt_sel, // NOTE: ex9, 与 ID 总线的最高两位对应.
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
        csr_wmask,
        csr_addr,
        csr_we,
        res_from_csr,
        ex_ertn,
        ex_syscall,
        res_from_mem
    } = ds_to_es_bus_r;


    // NOTE: ALU
    wire [31:0] alu_src1;
    wire [31:0] alu_src2;
    wire [31:0] es_alu_result;
    wire [31:0] es_mul_result;  // NOTE: ex7

    assign alu_src1 = src1_is_pc ? es_pc : rj_value;
    assign alu_src2 = src2_is_imm ? imm : rkd_value;

    alu u_alu (
        .alu_op    (alu_op),
        .alu_src1  (alu_src1),
        .alu_src2  (alu_src2),
        .alu_result(es_alu_result),  // ex7
        .mul_result(es_mul_result)   // NOTE: ex7
    );

    // NOTE: ex7
    //         (div 类指令的 src1_is_pc / src2_is_imm 均为 0, 故分别是 rj 与 rk)
    assign es_is_div    = alu_op[15] | alu_op[16] | alu_op[17] | alu_op[18];
    assign div_signed   = alu_op[15] | alu_op[16];  // div.w / mod.w
    assign div_take_rem = alu_op[16] | alu_op[18];  // mod.w / mod.wu

    // NOTE: ex7
    // NOTE: ex7
    assign div_start = es_valid && es_is_div && !ex_int && !div_started && !flush;  // ex8

    // NOTE: ex8 需要清空除法状态, 但是不需要清空除法器, 除法器正在运行的除法正常运行, 就算输出结果也会被 div_startd 拦住
    always @(posedge clk) begin
        if (reset) begin
            div_started <= 1'b0;
        end
        else if (flush) begin
            div_started <= 1'b0;
        end
        else if (div_start) begin
            div_started <= 1'b1;
        end
        else if (es_valid && es_allowin) begin
            div_started <= 1'b0;
        end
    end

    divider u_divider (
        .clk      (clk),
        .reset    (reset),
        .start    (div_start),
        .is_signed(div_signed),
        .op_a     (alu_src1),
        .op_b     (alu_src2),
        .done     (div_done),
        .quotient (div_quotient),
        .remainder(div_remainder)
    );

    // NOTE: ex7
    assign es_is_mul = alu_op[12] | alu_op[13] | alu_op[14];

    // NOTE: ex7
    wire [31:0] es_result;
    // NOTE: ex7 乘法只进入 MEM 数据通路, 流入 MEM 后续的阶段送回
    assign es_result = es_is_mul ? es_mul_result : es_fwd_data;  // ex7

    // NOTE: ex8 更老的指令要重定向时, 本级不能产生访存副作用
    //       ms_redirect 盖住 "异常指令在 MEM" 那一拍, flush 盖住 "异常指令在 WB" 那一拍
    wire ex_redirect = ms_redirect | flush;

    assign data_sram_en = es_valid && (res_from_mem | mem_we) && !ex_redirect;

    // NOTE: ex9, 自由运行计数器和当前 EXE 指令的计数快照.
    reg [63:0] stable_counter;
    reg [31:0] es_cnt_value;

    // NOTE: ex9, 采样时使用即将进入 EXE 的新指令选择字段.
    wire [1:0] ds_cnt_sel;
    assign ds_cnt_sel = ds_to_es_bus[212:211];

    

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

    // ex8: 在 redirect 
    assign data_sram_we = (es_valid && mem_we && !ex_redirect) ? mem_we_mask : 4'h0;
    assign data_sram_addr = es_alu_result;
    assign data_sram_wdata = mem_wdata;

    // EXE -> MEM
    assign es_to_ms_bus = {
        ex_int,
        es_pc,  // [156:125]
        mem_we,  // [124]
        gr_we,  // [123]
        dest,  // [122:118]
        es_result,  // [117:86]  // ex7
        rkd_value,  // [85:54]
        csr_wmask,  // [53:22]  // ex8
        csr_addr,  // [21:8]  // ex8
        csr_we,  // [7]  // ex8
        res_from_csr,  // [6]  // ex8
        ex_ertn,  // [5]  // ex8
        ex_syscall,  // [4]  // ex8
        res_from_mem,  // [3]
        mem_size,  // [2:1]
        mem_sign  // [0]
    };

    // NOTE: ex9, 独立计数, 不受 valid, stall 或 flush 控制.
    always @(posedge clk) begin
        if(reset)
            stable_counter <= 64'b0;
        else 
            stable_counter <= stable_counter + 64'd1;
    end

    // NOTE: ex9 指令进入 EXE 时取得一次固定快照
    always @(posedge clk) begin
        if(reset) begin
            es_cnt_value <= 32'b0;
        end
        else if (!flush && ds_to_es_valid && es_allowin) begin
            case (ds_cnt_sel)
                2'b01: es_cnt_value <= stable_counter[31:0];
                2'b10: es_cnt_value <= stable_counter[63:32];
                default: es_cnt_value <= 32'b0;
            endcase
        end
    end


    always @(posedge clk) begin
        if (reset) begin
            es_valid_r <= 1'b0;
        end
        // NOTE: ex8 清空流水线, 需要比 allow_in 优先
        else if (flush) begin
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

    // NOTE: Ex3 / ex7
    // NOTE: ex7 前递路径不连接乘法结果
    // NOTE: ex9, 计数快照同时供 ID 前递和后续 MEM 结果通路使用.
    assign es_fwd_data = (cnt_sel != 2'b00) ? es_cnt_value : es_is_div ? (div_take_rem ? div_remainder : div_quotient) : es_alu_result;  
    assign es_res_from_mem = res_from_mem;
    assign es_res_from_csr = res_from_csr;  // ex8

    //NOTE: ex9,
    assign es_csr_pending = es_valid && (csr_we || ex_ertn);


endmodule

`endif  // EXE_STAGE_V
