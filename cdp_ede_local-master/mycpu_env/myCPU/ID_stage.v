`ifndef ID_STAGE_V
`define ID_STAGE_V

`include "mycpu_head.v"
`include "tools.v"

module ID_stage (
    input wire clk,
    input wire reset,

    // ID -> EXE
    input  wire                        es_allowin,
    output wire                        ds_to_es_valid,
    output wire [`DS_TO_ES_BUS_WD-1:0] ds_to_es_bus,

    // IF -> ID
    output wire                        ds_allowin,
    input  wire                        fs_to_ds_valid,
    input  wire [`FS_TO_DS_BUS_WD-1:0] fs_to_ds_bus,

    // NOTE: 跳转指令, ID -> IF
    output wire [      `BR_BUS_WD-1:0] br_bus,
    // NOTE: WB -> ID, 这是由于 Regfile 放在 ID, WB 写回需要交给 ID
    input  wire [`WS_TO_RF_BUS_WD-1:0] ws_to_rf_bus
);

    // NOTE: ID 阶段握手信号
    reg  ds_valid;
    wire ds_ready_go;
    // todo ex1 只要求一次
    assign ds_ready_go    = 1'b1;
    assign ds_allowin     = !ds_valid || (ds_ready_go && es_allowin);
    assign ds_to_es_valid = ds_valid && ds_ready_go;

    // NOTE: 由于 IF -> ID(通过 fs_to_ds_bus) 的信号不稳定
    // NOTE: 因此需要先存放到 register 中
    reg  [`FS_TO_DS_BUS_WD-1:0] fs_to_ds_bus_r;
    // NOTE: ID 阶段执行的指令
    wire [                31:0] ds_inst;
    // NOTE: ID 阶段的 PC
    wire [                31:0] ds_pc;
    assign {ds_inst, ds_pc} = fs_to_ds_bus_r;

    always @(posedge clk) begin
        if (reset) begin
            ds_valid <= 1'b0;
        end
        else if (ds_allowin) begin
            ds_valid <= fs_to_ds_valid;
        end
        if (fs_to_ds_valid && ds_allowin) begin
            fs_to_ds_bus_r <= fs_to_ds_bus;
        end
    end


    // NOTE: Decoder 控制信号
    // alu 控制信号, 使用 onehot 形式
    wire [11:0] alu_op;
    // load 类指令的标识位
    wire        load_op;
    // src1 来自 pc
    wire        src1_is_pc;
    // src2 来自 imm
    wire        src2_is_imm;
    // src2 是常数 4
    wire        src2_is_4;
    // res 来自 MEM
    wire        res_from_mem;
    // 目标寄存器是 r1
    wire        dst_is_r1;
    // 通用寄存器写使能
    wire        gr_we;
    // 内存写使能
    wire        mem_we;
    // src2 来自 inst 的 rd 字段
    wire        src_reg_is_rd;
    // 目标寄存器
    wire [ 4:0] dest;
    // NOTE: LoongArch 的两个操作数, 第一个通常来自 rj, 而第二个可能来自 rk 或 rd
    // Reg[rj] 和 Reg[rd] 是否相等
    wire        rj_eq_rd;
    // Reg[rj] 的值
    wire [31:0] rj_value;
    // Reg[rk] 或者是 Reg[rd] 的值
    wire [31:0] rkd_value;
    // NOTE: imm 立即数
    wire [31:0] imm;
    // NOTE: 相对于 PC 偏移量
    wire [31:0] br_offs;
    // NOTE: 相对于 Reg[rj] 的偏移量
    wire [31:0] jirl_offs;
    // NOTE: 是否是跳转类指令, 包含 jirl
    wire        br_taken;
    // NOTE: 跳转类指令的目标, 包含 jirl
    wire [31:0] br_target;

    // NOTE: 指令字段拆解
    wire [ 5:0] op_31_26;
    wire [ 3:0] op_25_22;
    wire [ 1:0] op_21_20;
    wire [ 4:0] op_19_15;

    wire [ 4:0] rd;
    wire [ 4:0] rj;
    wire [ 4:0] rk;

    wire [11:0] i12;
    wire [19:0] i20;
    wire [15:0] i16;
    wire [25:0] i26;

    wire [63:0] op_31_26_d;
    wire [15:0] op_25_22_d;
    wire [ 3:0] op_21_20_d;
    wire [31:0] op_19_15_d;

    assign op_31_26 = ds_inst[31:26];
    assign op_25_22 = ds_inst[25:22];
    assign op_21_20 = ds_inst[21:20];
    assign op_19_15 = ds_inst[19:15];

    assign rd       = ds_inst[4:0];
    assign rj       = ds_inst[9:5];
    assign rk       = ds_inst[14:10];

    assign i12      = ds_inst[21:10];
    assign i20      = ds_inst[24:5];
    assign i16      = ds_inst[25:10];
    assign i26      = {ds_inst[9:0], ds_inst[25:10]};

    // 修改为 Onehot 编码
    decoder_6_64 u_dec0 (
        .in (op_31_26),
        .out(op_31_26_d)
    );
    decoder_4_16 u_dec1 (
        .in (op_25_22),
        .out(op_25_22_d)
    );
    decoder_2_4 u_dec2 (
        .in (op_21_20),
        .out(op_21_20_d)
    );
    decoder_5_32 u_dec3 (
        .in (op_19_15),
        .out(op_19_15_d)
    );

    // NOTE: 控制信号, 用于控制是否是对应的指令
    wire inst_add_w;
    wire inst_sub_w;
    wire inst_slt;
    wire inst_sltu;
    wire inst_nor;
    wire inst_and;
    wire inst_or;
    wire inst_xor;
    wire inst_slli_w;
    wire inst_srli_w;
    wire inst_srai_w;
    wire inst_addi_w;
    wire inst_ld_w;
    wire inst_st_w;
    wire inst_jirl;
    wire inst_b;
    wire inst_bl;
    wire inst_beq;
    wire inst_bne;
    wire inst_lu12i_w;

    assign inst_add_w = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h00];
    assign inst_sub_w = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h02];
    assign inst_slt = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h04];
    assign inst_sltu = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h05];
    assign inst_nor = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h08];
    assign inst_and = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h09];
    assign inst_or = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h0a];
    assign inst_xor = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h0b];
    assign inst_slli_w  = op_31_26_d[6'h00] & op_25_22_d[4'h1] & op_21_20_d[2'h0] & op_19_15_d[5'h01];
    assign inst_srli_w  = op_31_26_d[6'h00] & op_25_22_d[4'h1] & op_21_20_d[2'h0] & op_19_15_d[5'h09];
    assign inst_srai_w  = op_31_26_d[6'h00] & op_25_22_d[4'h1] & op_21_20_d[2'h0] & op_19_15_d[5'h11];
    assign inst_addi_w = op_31_26_d[6'h00] & op_25_22_d[4'ha];
    assign inst_ld_w = op_31_26_d[6'h0a] & op_25_22_d[4'h2];
    assign inst_st_w = op_31_26_d[6'h0a] & op_25_22_d[4'h6];
    assign inst_jirl = op_31_26_d[6'h13];
    assign inst_b = op_31_26_d[6'h14];
    assign inst_bl = op_31_26_d[6'h15];
    assign inst_beq = op_31_26_d[6'h16];
    assign inst_bne = op_31_26_d[6'h17];
    assign inst_lu12i_w = op_31_26_d[6'h05] & ~ds_inst[25];

    assign alu_op[0] = inst_add_w | inst_addi_w | inst_ld_w | inst_st_w | inst_jirl | inst_bl;
    assign alu_op[1] = inst_sub_w;
    assign alu_op[2] = inst_slt;
    assign alu_op[3] = inst_sltu;
    assign alu_op[4] = inst_and;
    assign alu_op[5] = inst_nor;
    assign alu_op[6] = inst_or;
    assign alu_op[7] = inst_xor;
    assign alu_op[8] = inst_slli_w;
    assign alu_op[9] = inst_srli_w;
    assign alu_op[10] = inst_srai_w;
    assign alu_op[11] = inst_lu12i_w;

    // NOTE: Immediate Number 控制信号
    wire need_ui5;
    wire need_si12;
    wire need_si16;
    wire need_si20;
    wire need_si26;

    assign need_ui5 = inst_slli_w | inst_srli_w | inst_srai_w;
    assign need_si12 = inst_addi_w | inst_ld_w | inst_st_w;
    assign need_si16 = inst_jirl | inst_beq | inst_bne;
    assign need_si20 = inst_lu12i_w;
    assign need_si26 = inst_b | inst_bl;
    assign src2_is_4 = inst_jirl | inst_bl;


    assign imm = src2_is_4 ? 32'h4 : need_si20 ? {i20[19:0], 12'b0} : need_ui5 ? {27'b0, rk} :
        /*need_si12*/{{20{i12[11]}}, i12[11:0]};

    assign br_offs = need_si26 ? {{4{i26[25]}}, i26[25:0], 2'b0} : {{14{i16[15]}}, i16[15:0], 2'b0};

    assign jirl_offs = {{14{i16[15]}}, i16[15:0], 2'b0};

    assign src_reg_is_rd = inst_beq | inst_bne | inst_st_w;
    assign src1_is_pc = inst_jirl | inst_bl;

    assign src2_is_imm   = inst_slli_w  |
                           inst_srli_w  |
                           inst_srai_w  |
                           inst_addi_w  |
                           inst_ld_w    |
                           inst_st_w    |
                           inst_lu12i_w |
                           inst_jirl    |
                           inst_bl      ;

    assign res_from_mem = inst_ld_w;
    assign load_op = inst_ld_w;
    assign dst_is_r1 = inst_bl;
    assign gr_we = ~inst_st_w & ~inst_beq & ~inst_bne & ~inst_b;
    assign mem_we = inst_st_w;
    // 5'd1 是 r1 寄存器编号
    assign dest = dst_is_r1 ? 5'd1 : rd;


    // NOTE: 寄存器堆
    wire [ 4:0] rf_raddr1;
    wire [31:0] rf_rdata1;
    wire [ 4:0] rf_raddr2;
    wire [31:0] rf_rdata2;
    wire        rf_we;
    wire [ 4:0] rf_waddr;
    wire [31:0] rf_wdata;

    assign rf_raddr1 = rj;
    assign rf_raddr2 = src_reg_is_rd ? rd : rk;

    regfile u_regfile (
        .clk   (clk),
        .raddr1(rf_raddr1),
        .rdata1(rf_rdata1),
        .raddr2(rf_raddr2),
        .rdata2(rf_rdata2),
        .we    (rf_we),
        .waddr (rf_waddr),
        .wdata (rf_wdata)
    );

    assign {rf_we, rf_waddr, rf_wdata} = ws_to_rf_bus;

    assign rj_value = rf_rdata1;
    assign rkd_value = rf_rdata2;

    // NOTE: 解析跳转指令
    assign rj_eq_rd = (rj_value == rkd_value);
    assign br_taken  = (   inst_beq  &&  rj_eq_rd
                        || inst_bne  && !rj_eq_rd
                        || inst_jirl
                        || inst_bl
                        || inst_b
                       ) && ds_valid;
    assign br_target = (inst_beq || inst_bne || inst_bl || inst_b) ? (ds_pc + br_offs) :
        /*inst_jirl*/ (rj_value + jirl_offs);

    assign br_bus = {br_taken, br_target};


    //NOTE : 将 ID 信息传入到 EXE 阶段
    assign ds_to_es_bus = {
        alu_op,  // [151:140]
        load_op,  // [139]
        src1_is_pc,  // [138]
        src2_is_imm,  // [137]
        src2_is_4,  // [136]
        gr_we,  // [135]
        mem_we,  // [134]
        dest,  // [133:129]
        imm,  // [128:97]
        rj_value,  // [96:65]
        rkd_value,  // [64:33]
        ds_pc,  // [32:1]
        res_from_mem
    };  // [0]

endmodule

`endif  // ID_STAGE_V
