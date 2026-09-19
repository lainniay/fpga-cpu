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
    input  wire [`WS_TO_RF_BUS_WD-1:0] ws_to_rf_bus,

    // NOTE: ex2
    input wire [4:0] es_dest,
    input wire       es_gr_we,
    input wire       es_valid,

    input wire [4:0] ms_dest,
    input wire       ms_gr_we,
    input wire       ms_valid,

    // NOTE: ex3
    input wire        es_res_from_mem,
    input wire [31:0] es_fwd_data,
    input wire [31:0] ms_fwd_data,

    // NOTE: ex6
    input wire ms_res_from_mem
);

    // NOTE: ex2
    // wire es_conflict;
    // wire ms_conflict;
    // wire ws_conflict;

    // NOTE: ex3
    wire es_fwd_en1;
    wire ms_fwd_en1;
    wire ws_fwd_en1;
    wire es_fwd_en2;
    wire ms_fwd_en2;
    wire ws_fwd_en2;

    wire [31:0] rf_rdata1_fwd;
    wire [31:0] rf_rdata2_fwd;

    // NOTE: ID 阶段握手信号
    reg ds_valid;

    wire ds_ready_go;
    // NOTE: ex2
    // assign ds_ready_go    = !(es_conflict | ms_conflict | ws_conflict);

    // NOTE: ex3
    wire load_use;
    assign ds_ready_go    = !load_use;

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
    // 访存宽度
    wire [ 1:0] mem_size;
    // 访存符号扩展 00 => word, 01 => byte, 10 => half word
    wire        mem_sign;
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
    // NOTE: ex5 分支比较结果
    wire        rj_lt_rd;
    wire        rj_ge_rd;
    wire        rj_ltu_rd;
    wire        rj_geu_rd;
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

    // NOTE: ex2 
    wire        src1_is_rj;
    wire        src2_is_rk;
    wire        src2_is_rkd;

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
    // NOTE: ex4
    wire inst_slti;
    wire inst_sltui;
    wire inst_andi;
    wire inst_ori;
    wire inst_xori;
    wire inst_sll_w;
    wire inst_srl_w;
    wire inst_sra_w;
    wire inst_pcaddu12i;
    // NOTE: ex5
    wire inst_blt;
    wire inst_bge;
    wire inst_bltu;
    wire inst_bgeu;
    // NOTE: ex6
    wire inst_ld_b;
    wire inst_ld_h;
    wire inst_ld_bu;
    wire inst_ld_hu;
    wire inst_st_b;
    wire inst_st_h;

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
    // NOTE: ex4
    assign inst_slti = op_31_26_d[6'h00] & op_25_22_d[4'h8];
    assign inst_sltui = op_31_26_d[6'h00] & op_25_22_d[4'h9];
    assign inst_andi = op_31_26_d[6'h00] & op_25_22_d[4'hd];
    assign inst_ori = op_31_26_d[6'h00] & op_25_22_d[4'he];
    assign inst_xori = op_31_26_d[6'h00] & op_25_22_d[4'hf];
    assign inst_sll_w = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h0e];
    assign inst_srl_w = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h0f];
    assign inst_sra_w = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h10];
    assign inst_pcaddu12i = op_31_26_d[6'h07] & ~ds_inst[25];
    // NOTE: ex5
    assign inst_blt = op_31_26_d[6'h18];
    assign inst_bge = op_31_26_d[6'h19];
    assign inst_bltu = op_31_26_d[6'h1a];
    assign inst_bgeu = op_31_26_d[6'h1b];
    // NOTE: ex6 
    assign inst_ld_b = op_31_26_d[6'h0a] & op_25_22_d[4'h0];
    assign inst_ld_h = op_31_26_d[6'h0a] & op_25_22_d[4'h1];
    assign inst_ld_bu = op_31_26_d[6'h0a] & op_25_22_d[4'h8];
    assign inst_ld_hu = op_31_26_d[6'h0a] & op_25_22_d[4'h9];
    assign inst_st_b = op_31_26_d[6'h0a] & op_25_22_d[4'h4];
    assign inst_st_h = op_31_26_d[6'h0a] & op_25_22_d[4'h5];

    // ex4 / ex6
    assign alu_op[0] = inst_add_w | inst_addi_w | inst_ld_w | inst_st_w | inst_jirl | inst_bl | inst_pcaddu12i
                     | inst_ld_b | inst_ld_h | inst_ld_bu | inst_ld_hu | inst_st_b | inst_st_h;
    assign alu_op[1] = inst_sub_w;
    // ex4
    assign alu_op[2] = inst_slt | inst_slti;
    // ex4
    assign alu_op[3] = inst_sltu | inst_sltui;
    // ex4
    assign alu_op[4] = inst_and | inst_andi;
    assign alu_op[5] = inst_nor;
    // ex4
    assign alu_op[6] = inst_or | inst_ori;
    // ex4
    assign alu_op[7] = inst_xor | inst_xori;
    // ex4 
    assign alu_op[8] = inst_slli_w | inst_sll_w;
    // ex4
    assign alu_op[9] = inst_srli_w | inst_srl_w;
    // ex4
    assign alu_op[10] = inst_srai_w | inst_sra_w;
    assign alu_op[11] = inst_lu12i_w;

    // NOTE: Immediate Number 控制信号
    wire need_ui5;
    wire need_si12;
    wire need_si16;
    wire need_si20;
    wire need_si26;
    // NOTE: ex4
    wire need_ui12;

    assign need_ui5 = inst_slli_w | inst_srli_w | inst_srai_w;
    // ex4 / ex6
    assign need_si12 = inst_addi_w | inst_ld_w | inst_st_w | inst_slti | inst_sltui
                     | inst_ld_b | inst_ld_h | inst_ld_bu | inst_ld_hu | inst_st_b | inst_st_h;
    // ex5
    assign need_si16 = inst_jirl | inst_beq | inst_bne | inst_blt | inst_bge | inst_bltu | inst_bgeu;
    // ex4
    assign need_si20 = inst_lu12i_w | inst_pcaddu12i;
    assign need_si26 = inst_b | inst_bl;
    assign src2_is_4 = inst_jirl | inst_bl;
    // NOTE: ex4
    assign need_ui12 = inst_andi | inst_ori | inst_xori;

    // NOTE: ex4
    assign imm = src2_is_4 ? 32'h4                 :
                 need_si20 ? {i20[19:0], 12'b0}    :
                 need_ui5  ? {27'b0, rk}           :
                 need_ui12 ? {20'b0, i12}          :
                 {{20{i12[11]}}, i12[11:0]};

    assign br_offs = need_si26 ? {{4{i26[25]}}, i26[25:0], 2'b0} : {{14{i16[15]}}, i16[15:0], 2'b0};

    assign jirl_offs = {{14{i16[15]}}, i16[15:0], 2'b0};

    // ex5 / ex6
    assign src_reg_is_rd = inst_beq | inst_bne | inst_st_w | inst_blt | inst_bge | inst_bltu | inst_bgeu
                         | inst_st_b | inst_st_h;
    // ex4
    assign src1_is_pc = inst_jirl | inst_bl | inst_pcaddu12i;

    // ex4
    assign src2_is_imm   = inst_slli_w  |
                           inst_srli_w  |
                           inst_srai_w  |
                           inst_addi_w  |
                           inst_ld_w    |
                           inst_st_w    |
                           inst_lu12i_w |
                           inst_jirl    |
                           inst_bl      |
                           inst_slti    |
                           inst_sltui   |
                           inst_andi    |
                           inst_ori     |
                           inst_xori    |
                           inst_pcaddu12i |
                           inst_ld_b    |
                           inst_ld_h    |
                           inst_ld_bu   |
                           inst_ld_hu   |
                           inst_st_b    |
                           inst_st_h    ;

    // ex6: 所有 load 的结果都来自数据 RAM
    assign res_from_mem = inst_ld_w | inst_ld_b | inst_ld_h | inst_ld_bu | inst_ld_hu;
    // NOTE: ex6 访存宽度与符号扩展
    assign mem_size = (inst_ld_b | inst_ld_bu | inst_st_b) ? 2'b01 :
                      (inst_ld_h | inst_ld_hu | inst_st_h) ? 2'b10 : 2'b00;
    assign mem_sign = inst_ld_b | inst_ld_h;
    assign dst_is_r1 = inst_bl;

    // ex5 / ex6
    assign gr_we = ~inst_st_w & ~inst_st_b & ~inst_st_h & ~inst_beq & ~inst_bne & ~inst_b
                 & ~inst_blt & ~inst_bge & ~inst_bltu & ~inst_bgeu;
    assign mem_we = inst_st_w | inst_st_b | inst_st_h;
    // 5'd1 是 r1 寄存器编号
    assign dest = dst_is_r1 ? 5'd1 : rd;

    // NOTE: ex2
    // ex4
    assign src1_is_rj = inst_add_w | inst_sub_w | inst_slt | inst_sltu | inst_nor | inst_and | inst_or | inst_xor |
                        inst_slli_w | inst_srli_w | inst_srai_w |
                        inst_addi_w | inst_ld_w | inst_st_w | inst_jirl | inst_beq | inst_bne |
                        inst_slti | inst_sltui | inst_andi | inst_ori | inst_xori |
                        inst_sll_w | inst_srl_w | inst_sra_w |
                        inst_blt | inst_bge | inst_bltu | inst_bgeu |
                        inst_ld_b | inst_ld_h | inst_ld_bu | inst_ld_hu | inst_st_b | inst_st_h;

    // ex4
    assign src2_is_rk  = inst_add_w | inst_sub_w | inst_slt | inst_sltu | inst_nor | inst_and | inst_or | inst_xor |
                         inst_sll_w | inst_srl_w | inst_sra_w;

    // ex5 / ex6
    assign src2_is_rkd = src2_is_rk | inst_beq | inst_bne | inst_st_w | inst_st_b | inst_st_h
                         | inst_blt | inst_bge | inst_bltu | inst_bgeu;

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

    // NOTE: ex3
    assign rj_value = rf_rdata1_fwd;
    assign rkd_value = rf_rdata2_fwd;

    // NOTE: 解析跳转指令
    assign rj_eq_rd = (rj_value == rkd_value);
    // NOTE: ex5, 没有使用 ALU, 直接在 ID 内部完成计算, 否则需要先进入 EXE, 在回传
    assign rj_lt_rd = ($signed(rj_value) < $signed(rkd_value));
    assign rj_ge_rd = ($signed(rj_value) >= $signed(rkd_value));
    assign rj_ltu_rd = (rj_value < rkd_value);
    assign rj_geu_rd = (rj_value >= rkd_value);

    assign br_taken  = (   inst_beq  &&  rj_eq_rd
                        || inst_bne  && !rj_eq_rd
                        || inst_blt  &&  rj_lt_rd
                        || inst_bge  &&  rj_ge_rd
                        || inst_bltu &&  rj_ltu_rd
                        || inst_bgeu &&  rj_geu_rd
                        || inst_jirl
                        || inst_bl
                        || inst_b
                       ) && ds_valid;
    // ex5
    assign br_target = (inst_beq || inst_bne || inst_blt || inst_bge
                        || inst_bltu || inst_bgeu || inst_bl || inst_b)
                       ? (ds_pc + br_offs) : /*inst_jirl*/ (rj_value + jirl_offs);

    assign br_bus = {br_taken, br_target};


    //NOTE : 将 ID 信息传入到 EXE 阶段
    assign ds_to_es_bus = {
        alu_op,  // [153:142]
        mem_size,  // [141:140]
        mem_sign,  // [139]
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

    // NOTE: ex2 相关判断
    // es_valid 表明 exe 阶段是一条有效的指令, 不是 bubble
    // es_gr_we 不出 exe 阶段具有 通用寄存器 写使能
    // es_dest 写的不是 r0, 也就是 0寄存器
    // src1_is_rj / src2_is_rkd 表示 ID 指令是不是真的要使用 regfile, 后面的用于判断写目标是不是 ID 需要读的寄存器
    // assign es_conflict = es_valid && es_gr_we && (es_dest != 5'd0) &&
    //                   ((src1_is_rj && es_dest == rf_raddr1) || (src2_is_rkd && es_dest == rf_raddr2));

    // assign ms_conflict = ms_valid && ms_gr_we && (ms_dest != 5'd0) &&
    //                   ((src1_is_rj && ms_dest == rf_raddr1) || (src2_is_rkd && ms_dest == rf_raddr2));

    // rf_we 本来就是供给 wb 的写控制信号, rf_we = ws_valid && gr_we
    // assign ws_conflict = rf_we && (rf_waddr != 5'd0) &&
    //                   ((src1_is_rj && rf_waddr == rf_raddr1) || (src2_is_rkd && rf_waddr == rf_raddr2));

    // NOTE: ex3
    // ex3 的判断信号和上面的几乎一样, 但是需要注意的是, exe 阶段需要排除 es_res_from_mem, 也就是 load 类指令
    // ex6 由于 load 类指令在 mem 阶段回传会导致超过 50MHz 的时间限制, 因此需要加上
    assign es_fwd_en1 = es_valid && es_gr_we && !es_res_from_mem && (es_dest != 5'd0) && src1_is_rj && (es_dest == rf_raddr1);
    assign ms_fwd_en1 = ms_valid && ms_gr_we && !ms_res_from_mem && (ms_dest != 5'd0) && src1_is_rj && (ms_dest == rf_raddr1);
    assign ws_fwd_en1 = rf_we && (rf_waddr != 5'd0) && src1_is_rj && (rf_waddr == rf_raddr1);

    assign es_fwd_en2 = es_valid && es_gr_we && !es_res_from_mem && (es_dest != 5'd0) && src2_is_rkd && (es_dest == rf_raddr2);
    assign ms_fwd_en2 = ms_valid && ms_gr_we && !ms_res_from_mem && (ms_dest != 5'd0) && src2_is_rkd && (ms_dest == rf_raddr2);
    assign ws_fwd_en2 = rf_we && (rf_waddr != 5'd0) && src2_is_rkd && (rf_waddr == rf_raddr2);

    // NOTE: ex3 前递优先级 EXE > MEM > WB
    assign rf_rdata1_fwd = es_fwd_en1 ? es_fwd_data : ms_fwd_en1 ? ms_fwd_data : ws_fwd_en1 ? rf_wdata : rf_rdata1;
    assign rf_rdata2_fwd = es_fwd_en2 ? es_fwd_data : ms_fwd_en2 ? ms_fwd_data : ws_fwd_en2 ? rf_wdata : rf_rdata2;

    // NOTE: ex3 / ex6 
    assign load_use = (es_valid && es_res_from_mem && es_gr_we && (es_dest != 5'd0)
                    && ((src1_is_rj && es_dest == rf_raddr1) || (src2_is_rkd && es_dest == rf_raddr2)))
                   || (ms_valid && ms_res_from_mem && ms_gr_we && (ms_dest != 5'd0)
                    && ((src1_is_rj && ms_dest == rf_raddr1) || (src2_is_rkd && ms_dest == rf_raddr2)));

endmodule

`endif  // ID_STAGE_V   
