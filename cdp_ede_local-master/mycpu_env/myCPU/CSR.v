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

    // WB 必须保证这些事件来自有效指令; 软件写入和异常状态更新的优先级为异常 > 返回 > 指令写
    // NOTE: ex9, 定时器自动计数和到期置位独立执行, 不受异常/返回事件阻挡.
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
  // NOTE: ex9, TID 的 CSR 编号, 与保存的编号内容区分.
  localparam [13:0] CSR_TID = 14'h0040;
  // NOTE: ex9, 定时器配置寄存器(Timer Configuration, TCFG)的 CSR 编号.
  localparam [13:0] CSR_TCFG = 14'h0041;
  // NOTE: ex9, 定时器当前值寄存器(Timer Value, TVAL)的 CSR 编号, 软件只读.
  localparam [13:0] CSR_TVAL = 14'h0042;
  // NOTE: ex9, 定时中断清除寄存器(Timer Interrupt Clear, TICLR)的 CSR 编号.
  // NOTE: ex9, 该入口不保存数据, 软件向 bit0 有效写1表示清除, 读取恒为0.
  localparam [13:0] CSR_TICLR = 14'h0044;

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

  // NOTE: ex9, 软件可读写的计时器编号, 不保存计数值.
  reg [31:0] tid;

  // NOTE: ex9, 倒计时剩余值, 经定时器当前值寄存器(TVAL)供软件读取.
  // NOTE: ex9, 0xffffffff 表示停止, 与 EXE 中持续递增的64位 Stable Counter 相互独立.
  reg [31:0] timer_cnt;
  // NOTE: ex9, 异常状态寄存器(Exception Status, ESTAT)第11位, 保存尚未清除的定时器到期标志.
  reg estat_bit11;
  // NOTE: ex9, 保存软件配置: bit0 En启用, bit1 Periodic周期模式, bits31:2 InitVal初值字段.
  // NOTE: ex9, 实际倒计时装入值为 {InitVal, 2'b0}, 周期模式每次到期都重新装入.
  reg [31:0] tcfg; // NOTE: ex9, 定时器配置寄存器(TCFG)的内容.


  wire [31:0] crmd_rvalue = {28'b0, 1'b1, crmd_ie, crmd_plv};
  wire [31:0] prmd_rvalue = {29'b0, prmd_pie, prmd_pplv};
  // NOTE: ex9, 分散保存的异常状态字段在读取时拼接, 定时器标志放bit11, 软件中断状态仍为bits1:0.
  wire [31:0] estat_rvalue = {1'b0, estat_esubcode, estat_ecode, 4'b0, estat_bit11 ,9'b0, estat_sw_int};
  wire [31:0] eentry_rvalue = {eentry_va, 6'b0};

  wire [2:0] crmd_next = (crmd_rvalue[2:0] & ~csr_wmask[2:0]) | (csr_wvalue[2:0] & csr_wmask[2:0]);
  wire [2:0] prmd_next = (prmd_rvalue[2:0] & ~csr_wmask[2:0]) | (csr_wvalue[2:0] & csr_wmask[2:0]);
  // NOTE: ex9, 软件写异常状态寄存器只更新低两位, 不能直接改写定时器到期标志或异常码.
  wire [1:0] estat_next = (estat_sw_int & ~csr_wmask[1:0]) | (csr_wvalue[1:0] & csr_wmask[1:0]);
  wire [25:0] eentry_next = (eentry_va & ~csr_wmask[31:6]) | (csr_wvalue[31:6] & csr_wmask[31:6]);


  // NOTE: ex9, 当前已保存配置的读值, 该连线不额外保存一份配置.
  wire [31:0] tcfg_rvalue = tcfg;

  // NOTE: ex9, 掩码为1采用软件写数据, 为0保留旧配置, 得到本次写入后的候选配置.
  // NOTE: ex9, 此连线始终组合计算, 只有有效写入编号命中TCFG时才能保存它或据此重新装入.
  wire [31:0] tcfg_next = (tcfg_rvalue & ~csr_wmask) | (csr_wvalue & csr_wmask);
 

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
        CSR_TID :   csr_rvalue = tid; // NOTE: ex9, CSR 读取和 rdcntid 共用该读值.
        CSR_TCFG :  csr_rvalue = tcfg; // NOTE: ex9, 读取已保存的定时器配置.
        CSR_TVAL:   csr_rvalue = timer_cnt; // NOTE: ex9, 读取当前剩余计数, 软件写入无效果.
        // NOTE: ex9, 定时中断清除寄存器(TICLR)使用默认读零行为, 不另设存储寄存器.
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
      tid            <= 32'b0; // NOTE: ex9, 本课设将 TID 复位为0.
      tcfg           <= 32'b0; // NOTE: ex9, 复位关闭定时器, 计数和到期标志在各自时序块中复位.
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
        // NOTE: ex9, 掩码为1的位采用新值, 为0的位保留旧值.
        CSR_TID : tid <= (tid & ~csr_wmask) | (csr_wvalue & csr_wmask);
        // NOTE: ex9, 此分支仅写软件中断状态, bit11由到期检测和TICLR清除逻辑负责.
        CSR_ESTAT:  estat_sw_int <= estat_next[1:0];
        // NOTE: ex9, WB保存新配置的同一个时钟沿, 下方计数块也可按新配置装入倒计时.
        CSR_TCFG :  tcfg <= tcfg_next;
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

  // NOTE: ex9, 倒计时硬件逐拍运行, 不受流水线stall或flush停止, 软件重新配置优先于正常计数.
  always @(posedge clk) begin
    if(reset) 
      // NOTE: ex9, 停止值同时用于复位和单次到期, 防止单次结束后再次递减或重复到期.
      timer_cnt <= 32'hffffffff;
    // NOTE: ex9, 写入必须有效且编号命中TCFG, 屏蔽与异常/返回同拍的软件写入.
    else if(csr_we && !wb_ex && !ertn_flush && csr_addr == CSR_TCFG) begin
      // NOTE: ex9, 判断写入后的En, 并采用新初值, 不能在同一个沿读取尚未更新的旧tcfg.
      if(tcfg_next[0]) begin
        timer_cnt <= {tcfg_next[31:2],2'b0};
      end
      // NOTE: ex9, 新配置关闭时保持剩余值, 本拍不再减一, 也不清除已有到期标志.
    end
    // NOTE: ex9, 只有启用且未处于停止值时才推进倒计时, 关闭后保持当前值.
    else if(tcfg[0] && timer_cnt != 32'hffffffff) begin
      if(timer_cnt != 32'b0) 
        timer_cnt <= timer_cnt -1;
      // NOTE: ex9, 沿前计数已为0时处理到期, 周期模式用已保存配置开始下一轮.
      // NOTE: ex9, 此处不能使用tcfg_next, 它可能正在根据其他CSR的写数据计算.
      else if(tcfg[1] == 1)  
        timer_cnt <= {tcfg[31:2],2'b0};
      // NOTE: ex9, 单次到期后进入停止值, 保留配置中的En, 由下方独立逻辑置起到期标志.
      else 
        timer_cnt <= 32'hffffffff;
      end
  end

  // NOTE: ex9, 到期标志单独保存, 周期重装不等待软件清除, 清除也不改变剩余计数.
  always @(posedge clk) begin
    if(reset)
      estat_bit11 <= 1'b0;
    // NOTE: ex9, 用沿前配置和计数判断到期, 与清除同拍时到期优先.
    // NOTE: ex9, 与重新配置同拍的旧到期事件也保留, 不能被新配置覆盖丢失.
    else if(tcfg[0] && timer_cnt == 32'b0)
      estat_bit11 <= 1'b1;
    // NOTE: ex9, 软件写入有效且编号命中TICLR, bit0掩码和写数据均为1时才清除.
    else if(csr_we && !wb_ex && !ertn_flush
            && (csr_addr == CSR_TICLR)
            && csr_wmask[0]&csr_wvalue[0])
      estat_bit11 <= 1'b0;
    // NOTE: ex9, 其余情况保持, 关闭/重配定时器或异常/返回均不自动清除已有标志.
  end

  


endmodule

`endif  // CSR_V
