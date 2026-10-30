`ifndef ICACHE_V
`define ICACHE_V

`define IC_LINE_WD 4
`define IC_SET_NUM 64
`define IC_INDEX_WD 6
`define IC_OFF_WD 2
`define IC_TAG_WD 22

// 空闲等待
`define IC_IDLE 2'd0
// ICache Miss 正在填充 ICache
`define IC_FILL 2'd1
// 返回 Response
`define IC_RESP 2'd3

module icache (
    input wire clk,
    input wire reset,

    input  wire        req_valid,
    input  wire [31:0] req_pc,
    output wire        req_ready,

    output wire        rsp_valid,
    output wire [31:0] rsp_pc,
    output wire [31:0] rsp_inst,
    input  wire        rsp_ready,

    output wire        mem_req_valid,
    output wire [31:0] mem_req_addr,
    input  wire        mem_req_ready,
    input  wire        mem_rsp_valid,
    input  wire [31:0] mem_rsp_data
);

    reg [1:0] state;

    reg valid[0:`IC_SET_NUM-1];
    reg [`IC_TAG_WD-1:0] tag[0:`IC_SET_NUM-1];
    reg [31:0] data[0:`IC_SET_NUM-1][0:`IC_LINE_WD-1];

    reg [31:0] request_pc;
    reg [31:0] response_inst;
    // request 读取的 offset
    reg [`IC_OFF_WD-1:0] fill_req_offset;
    // repsonse 返回的 offset
    reg [`IC_OFF_WD-1:0] fill_rsp_offset;
    reg fill_req_done;

    // index
    wire [`IC_INDEX_WD-1:0] query_index = req_pc[9:4];
    // offset
    wire [`IC_OFF_WD-1:0] query_offset = req_pc[3:2];
    // tag
    wire [`IC_TAG_WD-1:0] query_tag = req_pc[31:10];
    // cache hit
    wire query_hit = valid[query_index] && (tag[query_index] == query_tag);

    // Cache Miss 的时候, 填充的行
    wire [`IC_INDEX_WD-1:0] fill_index = request_pc[9:4];
    wire [`IC_OFF_WD-1:0] request_offset = request_pc[3:2];

    wire accept_req = req_valid && req_ready;
    wire miss_now = accept_req && !query_hit;

    // 在返回 repsonse 的同时, 允许接受 request
    assign req_ready = (state == `IC_IDLE) || ((state == `IC_RESP) && rsp_ready);
    assign rsp_valid = (state == `IC_RESP);
    assign rsp_pc = request_pc;
    assign rsp_inst = response_inst;

    assign mem_req_valid = ((state == `IC_FILL) && !fill_req_done) || miss_now;

    assign mem_req_addr = (state == `IC_FILL)
                        ? {request_pc[31:4], fill_req_offset, 2'b00}
                        : {req_pc[31:4], 4'b0000};

    integer i;
    always @(posedge clk) begin
        if (reset) begin
            state <= `IC_IDLE;
            request_pc <= 32'b0;
            response_inst <= 32'b0;
            fill_req_offset <= {`IC_OFF_WD{1'b0}};
            fill_rsp_offset <= {`IC_OFF_WD{1'b0}};
            fill_req_done <= 1'b0;
            for (i = 0; i < `IC_SET_NUM; i = i + 1) begin
                valid[i] <= 1'b0;
            end
        end
        else begin
            case (state)
                `IC_IDLE: begin
                    if (req_valid && req_ready) begin
                        request_pc <= req_pc;
                        if (query_hit) begin
                            response_inst <= data[query_index][query_offset];
                            state <= `IC_RESP;
                        end
                        else begin
                            valid[query_index] <= 1'b0;
                            // 从 Cache Line 的第一个 Word 开始
                            fill_rsp_offset <= {`IC_OFF_WD{1'b0}};
                            fill_req_done <= 1'b0;
                            // 第一个 IMem Request 需要在 IDLE 请求
                            if (mem_req_valid && mem_req_ready) begin  // 如果请求被接受, 那么下一拍就变成 01
                                fill_req_offset <= {{(`IC_OFF_WD - 1) {1'b0}}, 1'b1};
                            end
                            else begin  // 如果没有被接受下一拍还是 00
                                fill_req_offset <= {`IC_OFF_WD{1'b0}};
                            end
                            state <= `IC_FILL;
                        end
                    end
                end
                `IC_FILL: begin
                    if (mem_req_valid && mem_req_ready) begin
                        if (fill_req_offset == {`IC_OFF_WD{1'b1}}) begin
                            fill_req_done <= 1'b1;
                        end
                        else begin
                            fill_req_offset <= fill_req_offset + 1'b1;
                        end
                    end
                    if (mem_rsp_valid) begin
                        data[fill_index][fill_rsp_offset] <= mem_rsp_data;
                        if (fill_rsp_offset == {`IC_OFF_WD{1'b1}}) begin // 填充 ICache 对应的 Cache Line 完成
                            tag[fill_index] <= request_pc[31:10];
                            valid[fill_index] <= 1'b1;
                            // 由于在这个时钟沿, Cache Line 的最后一个 Word 里面还是旧的数据
                            // 因此不能直接使用 data 里面的数据
                            response_inst <= (request_offset == fill_rsp_offset)
                                           ? mem_rsp_data
                                           : data[fill_index][request_offset];
                            state <= `IC_RESP;
                        end
                        else begin
                            fill_rsp_offset <= fill_rsp_offset + 1'b1;
                        end
                    end
                end
                `IC_RESP: begin
                    if (rsp_valid && rsp_ready) begin
                        if (accept_req) begin
                            request_pc <= req_pc;
                            if (query_hit) begin
                                response_inst <= data[query_index][query_offset];
                                state <= `IC_RESP;
                            end
                            else begin
                                valid[query_index] <= 1'b0;
                                fill_rsp_offset <= {`IC_OFF_WD{1'b0}};
                                fill_req_done <= 1'b0;
                                if (mem_req_valid && mem_req_ready) begin
                                    fill_req_offset <= {{(`IC_OFF_WD - 1) {1'b0}}, 1'b1};
                                end
                                else begin
                                    fill_req_offset <= {`IC_OFF_WD{1'b0}};
                                end
                                state <= `IC_FILL;
                            end
                        end
                        else begin
                            state <= `IC_IDLE;
                        end
                    end
                end
                default: begin
                    state <= `IC_IDLE;
                end
            endcase
        end
    end

endmodule


`endif
