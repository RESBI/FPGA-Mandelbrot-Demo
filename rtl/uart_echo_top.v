`timescale 1ns / 1ps

module uart_echo_top (
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
        .LOCKED()
    );

    BUFG u_sys_clk_bufg (
        .I(clk_100_unbuf),
        .O(sys_clk)
    );

    BUFG u_clk_fb_bufg (
        .I(clk_fb_unbuf),
        .O(clk_fb)
    );

    wire [7:0] rx_data;
    wire       rx_avail;
    wire       tx_avail;
    reg        tx_en = 1'b0;
    reg [7:0]  tx_data = 8'h00;

    uart_rx u_rx (
        .rx         (uart_rx),
        .clk        (sys_clk),
        .data       (rx_data),
        .data_avail (rx_avail)
    );

    uart_tx u_tx (
        .tx             (uart_tx),
        .clk            (sys_clk),
        .data           (tx_data),
        .transmit_en    (tx_en),
        .transmit_avail (tx_avail)
    );

    always @(posedge sys_clk) begin
        tx_en <= 1'b0;
        if (rx_avail && tx_avail) begin
            tx_data <= rx_data;
            tx_en <= 1'b1;
        end
    end

    reg [31:0] heartbeat = 32'd0;
    reg rx_seen = 1'b0;
    reg tx_seen = 1'b0;

    always @(posedge sys_clk) begin
        heartbeat <= heartbeat + 1'b1;
        if (rx_avail)
            rx_seen <= ~rx_seen;
        if (tx_en && tx_avail)
            tx_seen <= ~tx_seen;
    end

    assign LED = {4'b0000, tx_seen, rx_seen, tx_avail, heartbeat[25]};

endmodule
