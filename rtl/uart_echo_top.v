`timescale 1ns / 1ps

module uart_echo_top (
    input  wire uart_rx,
    output wire uart_tx,
    input  wire sys_clk,
    output wire [3:2] led
);

    wire sys_clk_i;

    BUFG u_sys_clk_bufg (
        .I(sys_clk),
        .O(sys_clk_i)
    );

    wire [7:0] rx_data;
    wire       rx_avail;
    wire       tx_avail;
    reg        tx_en = 1'b0;
    reg [7:0]  tx_data = 8'h00;

    uart_rx #(
        .CLK_HZ(200000000)
    ) u_rx (
        .rx         (uart_rx),
        .clk        (sys_clk_i),
        .data       (rx_data),
        .data_avail (rx_avail)
    );

    uart_tx #(
        .CLK_HZ(200000000)
    ) u_tx (
        .tx             (uart_tx),
        .clk            (sys_clk_i),
        .data           (tx_data),
        .transmit_en    (tx_en),
        .transmit_avail (tx_avail)
    );

    always @(posedge sys_clk_i) begin
        tx_en <= 1'b0;
        if (rx_avail && tx_avail) begin
            tx_data <= rx_data;
            tx_en <= 1'b1;
        end
    end

    reg [31:0] heartbeat = 32'd0;
    reg rx_seen = 1'b0;
    reg tx_seen = 1'b0;

    always @(posedge sys_clk_i) begin
        heartbeat <= heartbeat + 1'b1;
        if (rx_avail)
            rx_seen <= ~rx_seen;
        if (tx_en && tx_avail)
            tx_seen <= ~tx_seen;
    end

    assign led[2] = heartbeat[25];
    assign led[3] = rx_seen ^ tx_seen;

endmodule
