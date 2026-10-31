`timescale 1ns/1ps
module remote_top_tb;
    localparam integer BIT_NS = 8680;

    reg clk_50M = 0;
    always #10 clk_50M = ~clk_50M;
    reg clk_11M0592 = 0;

    reg clock_btn = 0;
    reg reset_btn = 1;
    reg [3:0] touch_btn = 4'd0;
    reg [31:0] dip_sw = 32'd0;
    reg rxd = 1;
    wire txd;

    wire [15:0] leds;
    wire [7:0] dpy0;
    wire [7:0] dpy1;
    wire uart_rdn;
    wire uart_wrn;
    wire uart_dataready;
    wire uart_tbre;
    wire uart_tsre;
    wire [31:0] base_ram_data;
    wire [19:0] base_ram_addr;
    wire [3:0] base_ram_be_n;
    wire base_ram_ce_n;
    wire base_ram_oe_n;
    wire base_ram_we_n;
    wire [31:0] ext_ram_data;
    wire [19:0] ext_ram_addr;
    wire [3:0] ext_ram_be_n;
    wire ext_ram_ce_n;
    wire ext_ram_oe_n;
    wire ext_ram_we_n;
    wire [22:0] flash_a;
    wire [15:0] flash_d;
    wire flash_rp_n;
    wire flash_vpen;
    wire flash_ce_n;
    wire flash_oe_n;
    wire flash_we_n;
    wire flash_byte_n;
    wire [2:0] video_red;
    wire [2:0] video_green;
    wire [1:0] video_blue;
    wire video_hsync;
    wire video_vsync;
    wire video_clk;
    wire video_de;

    reg [7:0] expected [0:15];
    integer round_id;

    task send_byte(input [7:0] data);
        integer i;
        begin
            @(negedge clk_50M);
            rxd = 0;
            repeat (434) @(negedge clk_50M);
            for (i = 0; i < 8; i = i + 1) begin
                rxd = data[i];
                repeat (434) @(negedge clk_50M);
            end
            rxd = 1;
            repeat (434) @(negedge clk_50M);
        end
    endtask
    reg [7:0] tx_byte;
    integer tx_count = 0;
    integer k;

    loongson_remote_top #(.SIMULATION(1'b1)) dut (
        .clk_50M(clk_50M),
        .clk_11M0592(clk_11M0592),
        .clock_btn(clock_btn),
        .reset_btn(reset_btn),
        .touch_btn(touch_btn),
        .dip_sw(dip_sw),
        .leds(leds),
        .dpy0(dpy0),
        .dpy1(dpy1),
        .uart_rdn(uart_rdn),
        .uart_wrn(uart_wrn),
        .uart_dataready(uart_dataready),
        .uart_tbre(uart_tbre),
        .uart_tsre(uart_tsre),
        .base_ram_data(base_ram_data),
        .base_ram_addr(base_ram_addr),
        .base_ram_be_n(base_ram_be_n),
        .base_ram_ce_n(base_ram_ce_n),
        .base_ram_oe_n(base_ram_oe_n),
        .base_ram_we_n(base_ram_we_n),
        .ext_ram_data(ext_ram_data),
        .ext_ram_addr(ext_ram_addr),
        .ext_ram_be_n(ext_ram_be_n),
        .ext_ram_ce_n(ext_ram_ce_n),
        .ext_ram_oe_n(ext_ram_oe_n),
        .ext_ram_we_n(ext_ram_we_n),
        .txd(txd),
        .rxd(rxd),
        .flash_a(flash_a),
        .flash_d(flash_d),
        .flash_rp_n(flash_rp_n),
        .flash_vpen(flash_vpen),
        .flash_ce_n(flash_ce_n),
        .flash_oe_n(flash_oe_n),
        .flash_we_n(flash_we_n),
        .flash_byte_n(flash_byte_n),
        .video_red(video_red),
        .video_green(video_green),
        .video_blue(video_blue),
        .video_hsync(video_hsync),
        .video_vsync(video_vsync),
        .video_clk(video_clk),
        .video_de(video_de)
    );

    initial begin
        expected[0] = 8'h55;
        expected[1] = 8'h41;
        expected[2] = 8'h52;
        expected[3] = 8'h54;
        expected[4] = 8'h20;
        expected[5] = 8'h4f;
        expected[6] = 8'h4b;
        expected[7] = 8'h0d;
        expected[8] = 8'h0a;
        expected[9] = 8'h41;
        expected[10] = 8'h7a;
        expected[11] = 8'h00;
        expected[12] = 8'hff;
        expected[13] = 8'h55;
        expected[14] = 8'h0d;
        expected[15] = 8'h0a;
    end

    initial begin
        repeat (5) @(posedge clk_50M);
        #1 reset_btn = 0;
    end

    initial begin
        for (round_id = 0; round_id < 2; round_id = round_id + 1) begin
            wait (tx_count == 9);
            #BIT_NS;
            send_byte(8'h41);
            send_byte(8'h7a);
            send_byte(8'h00);
            send_byte(8'hff);
            send_byte(8'h55);
            send_byte(8'h0d);
            send_byte(8'h0a);
            wait (tx_count == 16);
            if (round_id == 0) begin
                @(negedge clk_50M);
                reset_btn = 1;
                repeat (10) @(negedge clk_50M);
                tx_count = 0;
                reset_btn = 0;
            end
        end
        if (uart_rdn !== 1 || uart_wrn !== 1 ||
            base_ram_ce_n !== 1 || ext_ram_ce_n !== 1 || flash_ce_n !== 1)
            $fatal(1, "unused peripherals not disabled");
        $display("PASS: remote top UART banner, binary echo and reset");
        $finish;
    end

    initial begin
        @(negedge reset_btn);
        repeat (5) @(posedge clk_50M);
        forever begin
            @(negedge txd);
            #(BIT_NS + BIT_NS / 2);
            for (k = 0; k < 8; k = k + 1) begin
                tx_byte[k] = txd;
                #BIT_NS;
            end
            if (txd !== 1'b1) $fatal(1, "remote UART stop bit is not high");
            if (tx_count >= 16) $fatal(1, "unexpected extra UART output");
            if (tx_byte !== expected[tx_count])
                $fatal(1, "remote banner byte %0d=%h expected=%h", tx_count, tx_byte, expected[tx_count]);
            tx_count = tx_count + 1;

        end
    end

    initial begin
        #4000000;
        $fatal(1, "remote top UART timeout: tx_count=%0d", tx_count);
    end
endmodule
