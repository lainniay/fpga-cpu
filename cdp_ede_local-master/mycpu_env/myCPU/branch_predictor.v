`ifndef BRANCH_PREDICTOR_V
`define BRANCH_PREDICTOR_V

`define BP_ENTRY_NUM 64
`define BP_INDEX_WD 6
`define BP_TAG_WD 24

`define BP_CNT_WD 2
`define BP_CNT_STRONG_NT 2'b00
`define BP_CNT_WEAK_NT 2'b01
`define BP_CNT_WEAK_T 2'b10
`define BP_CNT_STRONG_T 2'b11

`define PRED_SEQ 1'b0
`define PRED_TAKEN 1'b1

module branch_predictor (
    input wire clk,
    input wire reset,

    input  wire [31:0] query_pc,
    output wire        pred_hit,
    output wire        pred_taken,
    output wire [31:0] pred_target,

    input wire        upd_valid,
    input wire [31:0] upd_pc,
    input wire        upd_taken,
    input wire [31:0] upd_target
);

reg valid [0:63];
reg [23:0] tag [0:63];  //记录属于哪个 PC
reg [31:0] target [0:63];  //每项保存的跳转目标
reg [1:0] counter [0:63];  //每项保存的预测计数器

wire [5:0] index;  //查询预测表
assign index=query_pc[7:2];  //用于选择表项

wire [5:0] upd_index;  //更新预测表
assign upd_index=upd_pc[7:2];

integer i;
always @(posedge clk) begin
    if(reset) begin
        for(i =0;i<64;i=i+1)
        valid[i]<=1'b0;
    end

    else if(upd_valid) begin
        //新表项，或索引冲突 替换旧表项
        if(!valid[upd_index] || tag[upd_index] != upd_pc[31:8])
        begin
            valid[upd_index]<=1;
            tag[upd_index]<=upd_pc[31:8];
            target[upd_index]<=upd_target;

            //根据实际方向初始化为弱状态
            counter[upd_index]<=upd_taken?`BP_CNT_WEAK_T:`BP_CNT_WEAK_NT;
        end
        else  begin
            //已有同一分支，更新实际目标
            target[upd_index]<=upd_target;  //保存该分支的真实跳转目标，而不是这一次实际的下一条pc

            if(upd_taken==1'b1) begin
                case(counter[upd_index])
                `BP_CNT_STRONG_NT:
                counter[upd_index]<=`BP_CNT_WEAK_NT;
                `BP_CNT_WEAK_NT:
                counter[upd_index]<=`BP_CNT_WEAK_T;
                `BP_CNT_WEAK_T:
                counter[upd_index]<=`BP_CNT_STRONG_T;
                `BP_CNT_STRONG_T:
                counter[upd_index]<=`BP_CNT_STRONG_T;
                default:
                counter[upd_index]<=counter[upd_index];
                endcase
            end
            else begin
                case(counter[upd_index])
                `BP_CNT_STRONG_NT:
                counter[upd_index]<=`BP_CNT_STRONG_NT;
                `BP_CNT_WEAK_NT:
                counter[upd_index]<=`BP_CNT_STRONG_NT;
                `BP_CNT_WEAK_T:
                counter[upd_index]<=`BP_CNT_WEAK_NT;
                `BP_CNT_STRONG_T:
                counter[upd_index]<=`BP_CNT_WEAK_T;
                default:
                counter[upd_index]<=counter[upd_index];
                endcase
            end
        end
    end

end

assign pred_hit=valid[index] && (tag[index]==query_pc[31:8]);
assign pred_taken=pred_hit ? counter[index][1]:1'b0;
assign pred_target=pred_hit ? target[index] :32'b0;



endmodule

`endif
