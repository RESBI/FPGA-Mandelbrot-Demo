`timescale 1ns / 1ps

module uart_rx_detect_top (
    input  wire uart_rx,
    output wire uart_tx,
    input  wire sys_clk,
    input  wire rst_n,
    output wire [3:2] led
);

    wire clk;
    BUFG u_sys_clk_bufg (.I(sys_clk), .O(clk));

    reg [7:0] rst_cnt = 8'd0;
    wire rst = (rst_cnt != 8'hff);
    always @(posedge clk) begin
        if (rst_cnt != 8'hff)
            rst_cnt <= rst_cnt + 1'b1;
    end

    reg rx_d1 = 1'b1;
    reg rx_d2 = 1'b1;
    reg seen = 1'b0;
    reg [23:0] gap = 24'd0;
    reg tx_en = 1'b0;
    wire tx_avail;

    uart_tx #(.CLK_HZ(24576000)) u_tx (
        .tx             (uart_tx),
        .clk            (clk),
        .data           (8'hA5),
        .transmit_en    (tx_en),
        .transmit_avail (tx_avail)
    );

    always @(posedge clk) begin
        tx_en <= 1'b0;
        rx_d1 <= uart_rx;
        rx_d2 <= rx_d1;

        if (rst) begin
            seen <= 1'b0;
            gap <= 24'd0;
        end else begin
            if (rx_d2 && !rx_d1)
                seen <= 1'b1;

            if (seen) begin
                if (gap != 0) begin
                    gap <= gap - 1'b1;
                end else if (tx_avail) begin
                    tx_en <= 1'b1;
                    gap <= 24'd250000;
                end
            end
        end
    end

    wire unused_rst_n = rst_n;
    assign led = {seen, tx_avail};

endmodule
