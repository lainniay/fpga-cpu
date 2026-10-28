`ifndef IF_STAGE_V
`define IF_STAGE_V

`include "mycpu_head.v"

module IF_stage (
    input wire clk,
    input wire reset,

    // IF -> ID 
    input  wire                        ds_allowin,
    output wire                        fs_to_ds_valid,
    output wire [`FS_TO_DS_BUS_WD-1:0] fs_to_ds_bus,

    // NOTE: ex8 
    input wire        flush,       // 清空流水线
    input wire [31:0] redirect_pc, // 重定向 pc

    // ID -> IF, 指导指令跳转
    input wire [`BR_BUS_WD-1:0] br_bus,

    // Inst SRAM
    output wire        inst_sram_en,
    output wire [ 3:0] inst_sram_we,
    output wire [31:0] inst_sram_addr,
    output wire [31:0] inst_sram_wdata,
    input  wire [31:0] inst_sram_rdata
);

    reg fs_valid;
    wire fs_ready_go;
    wire fs_allowin;
    wire to_fs_valid;

    wire mispredict;
    wire [31:0] actual_next_pc;
    wire upd_valid, upd_taken;
    wire [31:0] upd_pc, upd_target;
    assign {mispredict, actual_next_pc, upd_valid, upd_pc, upd_taken, upd_target} = br_bus;

    // NOTE: ex8 异常重定向优先于分支纠错
    wire redirect = flush || mispredict;
    wire [31:0] redirect_target = flush ? redirect_pc : actual_next_pc;

    // 下一条 pc, 实际上向
    reg [31:0] fetch_pc;
    // if 阶段的 pc
    reg [31:0] fs_pc;
    // if 猜测的下一个 pc
    reg [31:0] fs_pred_next_pc;

    // NOTE: 当前任务的请求尚未被存储层接受, 需要保持请求直到握手
    reg req_pending;
    // 当前的 if 取值作废
    reg fs_killed;

    reg ex_adef;
    wire next_ex_adef = |fetch_pc[1:0];

    wire pred_hit, pred_taken;
    wire [31:0] pred_target;
    wire [31:0] seq_pc = fetch_pc + 32'd4;
    wire [31:0] next_pc = pred_hit && pred_taken ? pred_target : seq_pc;

    branch_predictor u_branch_predictor (
        .clk        (clk),
        .reset      (reset),
        .query_pc   (fetch_pc),
        .pred_hit   (pred_hit),
        .pred_taken (pred_taken),
        .pred_target(pred_target),
        .upd_valid  (upd_valid),
        .upd_pc     (upd_pc),
        .upd_taken  (upd_taken),
        .upd_target (upd_target)
    );

    // _valid 表示有请求, _ready 表示接受请求
    wire req_valid, req_ready;
    wire rsp_valid, rsp_ready;
    // rsp_pc 并不是逻辑上必须的, 只是为了让 repsonse 带有身份信息
    wire [31:0] rsp_pc, rsp_inst;

    // 当前还有没有被 指令请求模块 接受的请求
    wire held_req_valid = fs_valid && req_pending;
    // 下一条指令可以开始请求
    wire new_req_valid = to_fs_valid && fs_allowin && !next_ex_adef;
    // 如果是当前的请求还没有被接受, 那么就继续请求当前的 pc, 否则就请求下一个 pc
    wire [31:0] req_pc = held_req_valid ? fs_pc : fetch_pc;

    assign req_valid = held_req_valid || new_req_valid;
    // 本拍请求被消费
    wire req_fire = req_valid && req_ready;

    // 响应被接受
    wire req_accepted = !req_pending;
    // 本拍响应被消费
    wire rsp_fire = rsp_valid && rsp_ready;

    // NOTE: 提前发送下一地址, 背压时改用锁存的 fs_pc 保持同一个请求
    inst_fetch_mem u_inst_fetch_mem (
        .clk            (clk),
        .reset          (reset),
        .req_valid      (req_valid),
        .req_pc         (req_pc),
        .req_ready      (req_ready),
        .rsp_valid      (rsp_valid),
        .rsp_pc         (rsp_pc),
        .rsp_inst       (rsp_inst),
        .rsp_ready      (rsp_ready),
        .inst_sram_en   (inst_sram_en),
        .inst_sram_we   (inst_sram_we),
        .inst_sram_addr (inst_sram_addr),
        .inst_sram_wdata(inst_sram_wdata),
        .inst_sram_rdata(inst_sram_rdata)
    );

    wire [31:0] fs_inst = ex_adef ? 32'b0 : rsp_inst;
    assign fs_to_ds_bus = {fs_pred_next_pc, ex_adef, fs_inst, fs_pc};

    // 当前指令没对齐, 那么直接启动
    // 如果指令合法, 那么要求, 当前的响应有效, 而且被接受
    assign fs_ready_go = ex_adef || (req_accepted && rsp_valid);

    assign fs_to_ds_valid = fs_valid && fs_ready_go && !fs_killed && !redirect;
    assign rsp_ready = fs_valid && !ex_adef && req_accepted && (fs_killed || redirect || ds_allowin);

    assign fs_allowin = !fs_valid || (fs_ready_go && ds_allowin);
    assign to_fs_valid = !reset && !redirect && !fs_killed;
    // 当前的取值结束
    wire fs_done = fs_valid && (ex_adef ? (ds_allowin || redirect || fs_killed) : rsp_fire);

    // NOTE: 有效位按流水线握手更新, 作废响应则独立释放, 不依赖 ID 是否接收
    always @(posedge clk) begin
        if (reset) begin
            fs_valid <= 1'b0;
        end
        else if (fs_done && (fs_killed || redirect)) begin
            fs_valid <= 1'b0;
        end
        else if (fs_allowin) begin
            fs_valid <= to_fs_valid;
        end
    end

    always @(posedge clk) begin
        if (reset) begin
            req_pending <= 1'b0;
            fs_killed <= 1'b0;
            fetch_pc <= 32'h1c000000;
            fs_pc <= 32'h1bfffffc;
            fs_pred_next_pc <= 32'h1c000000;
            ex_adef <= 1'b0;
        end
        else begin
            if (req_fire) begin
                req_pending <= 1'b0;
            end
            if (redirect && fs_valid) begin
                fs_killed <= 1'b1;
            end
            if (fs_done) begin
                req_pending <= 1'b0;
                fs_killed   <= 1'b0;
            end
            if (to_fs_valid && fs_allowin) begin
                fs_pc <= fetch_pc;
                fs_pred_next_pc <= next_ex_adef ? seq_pc : next_pc;
                ex_adef <= next_ex_adef;
                req_pending <= !next_ex_adef && !req_ready;
                fs_killed <= 1'b0;
                fetch_pc <= next_ex_adef ? seq_pc : next_pc;
            end
            if (redirect) begin
                fetch_pc <= redirect_target;
            end
        end
    end

endmodule

`endif  // IF_STAGE_V
