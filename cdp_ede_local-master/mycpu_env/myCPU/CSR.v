`ifndef CSR_V
`define CSR_V

// Ex8: 独立 CSR 状态模块, 在 mycpu_top 中实例化, 由 WB 发起访问
// csr_re 仅控制读值输出, 不控制写入; csrwr/csrxchg 需同时置起读和写
// 写入在时钟沿生效, 所以 WB 可在同一时钟沿将 CSR 旧值写回 rd
// 流水线 flush 不能接到 reset; 异常/返回通过独立控制端口更新状态
module CSR (
    input wire clk,
    input wire reset,

    input  wire        csr_re,
    input  wire [13:0] csr_addr,
    output reg  [31:0] csr_rvalue,
    input  wire        csr_we,
    input  wire [31:0] csr_wmask,
    input  wire [31:0] csr_wvalue,

    // WB 必须保证这些事件来自有效指令; 本模块优先级为异常 > 返回 > 指令写
    // NOTE: wb 正在提交一个 expection
    input wire        wb_ex,
    // NOTE: 触发异常的 pc
    input wire [31:0] wb_pc,
    // NOTE: 异常主码
    input wire [ 5:0] wb_ecode,
    // NOTE: 异常子码
    input wire [ 8:0] wb_esubcode,
    // NOTE: wb 告知 csr, 将从 expection 中返回
    input wire        ertn_flush,   // ertn 是 expection return 的缩写

    output wire [31:0] ex_entry,
    output wire [31:0] ertn_entry
);

  // 当前模式信息
  localparam [13:0] CSR_CRMD   = 14'h0000;
  // 异常前的模式信息
  localparam [13:0] CSR_PRMD   = 14'h0001;
  // 异常状态
  localparam [13:0] CSR_ESTAT  = 14'h0005;
  // 异常返回地址
  localparam [13:0] CSR_ERA    = 14'h0006;
  // 异常入口
  localparam [13:0] CSR_EENTRY = 14'h000c;
  // kernel 专用的寄存器组
  localparam [13:0] CSR_SAVE0  = 14'h0030;
  localparam [13:0] CSR_SAVE1  = 14'h0031;
  localparam [13:0] CSR_SAVE2  = 14'h0032;
  localparam [13:0] CSR_SAVE3  = 14'h0033;

  // crmd.plv : 当前特权等级, 0 ~ 3
  reg [1:0] crmd_plv;
  // crmd.ie : 全局中断使能(Interrupt Enable), 高有效
  reg crmd_ie;
  // prmd.pplv : 异常前的 plv
  reg [1:0] prmd_pplv;
  // prmd.pie : 异常前的 IE
  reg prmd_pie;
  // 
  reg [1:0] estat_sw_int;  // sw_int : software_interrupt
  reg [5:0] estat_ecode;
  reg [8:0] estat_esubcode;
  // Exception Return Address
  reg [31:0] era;
  // Expection Entry Virtual Address
  reg [25:0] eentry_va;

  // Regfile
  reg [31:0] save0;
  reg [31:0] save1;
  reg [31:0] save2;
  reg [31:0] save3;


  wire [31:0] crmd_rvalue = {28'b0, 1'b1, crmd_ie, crmd_plv};
  wire [31:0] prmd_rvalue = {29'b0, prmd_pie, prmd_pplv};
  wire [31:0] estat_rvalue = {1'b0, estat_esubcode, estat_ecode, 14'b0, estat_sw_int};
  wire [31:0] eentry_rvalue = {eentry_va, 6'b0};

  wire [2:0] crmd_next = (crmd_rvalue[2:0] & ~csr_wmask[2:0]) | (csr_wvalue[2:0] & csr_wmask[2:0]);
  wire [2:0] prmd_next = (prmd_rvalue[2:0] & ~csr_wmask[2:0]) | (csr_wvalue[2:0] & csr_wmask[2:0]);
  wire [1:0] estat_next = (estat_sw_int & ~csr_wmask[1:0]) | (csr_wvalue[1:0] & csr_wmask[1:0]);
  wire [25:0] eentry_next = (eentry_va & ~csr_wmask[31:6]) | (csr_wvalue[31:6] & csr_wmask[31:6]);

  assign ex_entry   = eentry_rvalue;
  // 返回地址由软件维护, ertn 不自动加 4。
  assign ertn_entry = era;

  always @(*) begin
    csr_rvalue = 32'b0;
    if (csr_re) begin
      case (csr_addr)
        CSR_CRMD:   csr_rvalue = crmd_rvalue;
        CSR_PRMD:   csr_rvalue = prmd_rvalue;
        CSR_ESTAT:  csr_rvalue = estat_rvalue;
        CSR_ERA:    csr_rvalue = era;
        CSR_EENTRY: csr_rvalue = eentry_rvalue;
        CSR_SAVE0:  csr_rvalue = save0;
        CSR_SAVE1:  csr_rvalue = save1;
        CSR_SAVE2:  csr_rvalue = save2;
        CSR_SAVE3:  csr_rvalue = save3;
        default:    csr_rvalue = 32'b0;
      endcase
    end
  end

  always @(posedge clk) begin
    if (reset) begin
      crmd_plv       <= 2'b0;
      crmd_ie        <= 1'b0;
      prmd_pplv      <= 2'b0;
      prmd_pie       <= 1'b0;
      estat_sw_int   <= 2'b0;
      estat_ecode    <= 6'b0;
      estat_esubcode <= 9'b0;
      era            <= 32'b0;
      eentry_va      <= 26'b0;
      save0          <= 32'b0;
      save1          <= 32'b0;
      save2          <= 32'b0;
      save3          <= 32'b0;
    end  // 进入内核态
    else if (wb_ex) begin
      // 存储当前的状态
      prmd_pplv      <= crmd_plv;
      prmd_pie       <= crmd_ie;
      // 更新当前的状态
      crmd_plv       <= 2'b0;
      crmd_ie        <= 1'b0;
      // 记录用户态状态
      era            <= wb_pc;
      estat_ecode    <= wb_ecode;
      estat_esubcode <= wb_esubcode;
    end  // 返回用户态
    else if (ertn_flush) begin
      // 返回之前的状态
      crmd_plv <= prmd_pplv;
      crmd_ie  <= prmd_pie;
    end else if (csr_we) begin
      case (csr_addr)
        CSR_CRMD: begin
          crmd_plv <= crmd_next[1:0];
          crmd_ie  <= crmd_next[2];
        end
        CSR_PRMD: begin
          prmd_pplv <= prmd_next[1:0];
          prmd_pie  <= prmd_next[2];
        end
        CSR_ESTAT: estat_sw_int <= estat_next[1:0];
        CSR_ERA: era <= (era & ~csr_wmask) | (csr_wvalue & csr_wmask);
        CSR_EENTRY: eentry_va <= eentry_next;
        CSR_SAVE0: save0 <= (save0 & ~csr_wmask) | (csr_wvalue & csr_wmask);
        CSR_SAVE1: save1 <= (save1 & ~csr_wmask) | (csr_wvalue & csr_wmask);
        CSR_SAVE2: save2 <= (save2 & ~csr_wmask) | (csr_wvalue & csr_wmask);
        CSR_SAVE3: save3 <= (save3 & ~csr_wmask) | (csr_wvalue & csr_wmask);
        default: begin
        end  // 未实现的 CSR: 读零, 写入无效果。
      endcase
    end
  end

endmodule

`endif  // CSR_V
