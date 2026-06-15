`timescale 1ns / 1ps

module uart_tx_pattern_top (
    input  wire uart_rx,
    output wire uart_tx,
    input  wire CLK_200_P,
    input  wire CLK_200_N,
    output wire [7:0] LED
);

    wire sys_clk;
    wire clk_200;
    wire clk_fb;
    wire clk_fb_unbuf;
    wire clk_100_unbuf;
    wire clk_locked;

    IBUFDS #(
        .DIFF_TERM("TRUE"),
        .IBUF_LOW_PWR("FALSE"),
        .IOSTANDARD("LVDS")
    ) u_clk_200_ibufds (
        .I(CLK_200_P),
        .IB(CLK_200_N),
        .O(clk_200)
    );

    MMCME2_BASE #(
        .CLKIN1_PERIOD(5.000),
        .CLKFBOUT_MULT_F(5.000),
        .CLKOUT0_DIVIDE_F(10.000),
        .CLKOUT0_DUTY_CYCLE(0.500)
    ) u_clk_mmcm (
        .CLKIN1(clk_200),
        .CLKFBIN(clk_fb),
        .RST(1'b0),
        .PWRDWN(1'b0),
        .CLKFBOUT(clk_fb_unbuf),
        .CLKFBOUTB(),
        .CLKOUT0(clk_100_unbuf),
        .CLKOUT0B(),
        .CLKOUT1(),
        .CLKOUT1B(),
        .CLKOUT2(),
        .CLKOUT2B(),
        .CLKOUT3(),
        .CLKOUT3B(),
        .CLKOUT4(),
        .CLKOUT5(),
        .CLKOUT6(),
        .LOCKED(clk_locked)
    );

    BUFG u_sys_clk_bufg (
        .I(clk_100_unbuf),
        .O(sys_clk)
    );

    BUFG u_clk_fb_bufg (
        .I(clk_fb_unbuf),
        .O(clk_fb)
    );

    wire [7:0] tx_data;
    wire       tx_en;
    wire       tx_avail;

    uart_tx #(
        .CLK_HZ(100000000)
    ) u_tx (
        .tx             (uart_tx),
        .clk            (sys_clk),
        .data           (tx_data),
        .transmit_en    (tx_en),
        .transmit_avail (tx_avail)
    );

    localparam PATTERN_LEN = 8;
    localparam STATE_GAP   = 2'd0;
    localparam STATE_LOAD  = 2'd1;
    localparam STATE_PULSE = 2'd2;
    localparam STATE_WAIT  = 2'd3;

    reg [1:0] state = STATE_GAP;
    reg [2:0] pattern_idx = 0;
    reg [23:0] gap_counter = 24'd100000;
    reg tx_en_r = 0;
    reg [7:0] tx_data_r = 8'h55;

    assign tx_en = tx_en_r;
    assign tx_data = tx_data_r;

    always @(posedge sys_clk) begin
        tx_en_r <= 1'b0;

        case (state)
            STATE_GAP: begin
                if (gap_counter != 0) begin
                    gap_counter <= gap_counter - 1'b1;
                end else begin
                    state <= STATE_LOAD;
                end
            end

            STATE_LOAD: begin
                case (pattern_idx)
                    3'd0: tx_data_r <= 8'h55;
                    3'd1: tx_data_r <= 8'hAA;
                    3'd2: tx_data_r <= 8'h00;
                    3'd3: tx_data_r <= 8'hFF;
                    3'd4: tx_data_r <= 8'h52;
                    3'd5: tx_data_r <= 8'h4B;
                    3'd6: tx_data_r <= 8'h01;
                    default: tx_data_r <= 8'h7E;
                endcase
                state <= STATE_PULSE;
            end

            STATE_PULSE: begin
                if (tx_avail) begin
                    tx_en_r <= 1'b1;
                    state <= STATE_WAIT;
                end
            end

            STATE_WAIT: begin
                if (!tx_avail) begin
                    if (pattern_idx == PATTERN_LEN - 1) begin
                        pattern_idx <= 0;
                        gap_counter <= 24'd100000;
                        state <= STATE_GAP;
                    end else begin
                        pattern_idx <= pattern_idx + 1'b1;
                        state <= STATE_LOAD;
                    end
                end
            end

            default: state <= STATE_GAP;
        endcase
    end

    wire unused_uart_rx = uart_rx;

    reg [31:0] heartbeat = 32'd0;
    always @(posedge sys_clk) begin
        heartbeat <= heartbeat + 1'b1;
    end

    assign LED = {pattern_idx, state, clk_locked, tx_avail, heartbeat[25]};

endmodule
