`timescale 1ns / 1ps

module uart_echo_top (
    input  wire uart_rx,
    output wire uart_tx,
    input  wire sys_clk,
    input  wire rst_n,
    output wire [3:2] led
);

    wire clk;
    reg [7:0] rst_cnt = 8'd0;
    wire rst = (rst_cnt != 8'hff);

    BUFG u_sys_clk_bufg (
        .I(sys_clk),
        .O(clk)
    );

    always @(posedge clk) begin
        if (!rst_n)
            rst_cnt <= 8'd0;
        else if (rst_cnt != 8'hff)
            rst_cnt <= rst_cnt + 1'b1;
    end

    wire [7:0] rx_data;
    wire       rx_avail;
    wire       tx_avail;
    reg        tx_en = 1'b0;
    reg [7:0]  tx_data = 8'h00;

    uart_rx #(
        .CLK_HZ(24576000)
    ) u_rx (
        .rx         (uart_rx),
        .clk        (clk),
        .data       (rx_data),
        .data_avail (rx_avail)
    );

    uart_tx #(
        .CLK_HZ(24576000)
    ) u_tx (
        .tx             (uart_tx),
        .clk            (clk),
        .data           (tx_data),
        .transmit_en    (tx_en),
        .transmit_avail (tx_avail)
    );

    always @(posedge clk) begin
        tx_en <= 1'b0;
        if (rst) begin
            tx_data <= 8'h00;
        end else if (rx_avail && tx_avail) begin
            tx_data <= rx_data;
            tx_en <= 1'b1;
        end
    end

    reg [31:0] heartbeat = 32'd0;
    reg rx_seen = 1'b0;
    reg tx_seen = 1'b0;

    always @(posedge clk) begin
        heartbeat <= heartbeat + 1'b1;
        if (rst) begin
            rx_seen <= 1'b0;
            tx_seen <= 1'b0;
        end else begin
            if (rx_avail)
                rx_seen <= ~rx_seen;
            if (tx_en && tx_avail)
                tx_seen <= ~tx_seen;
        end
    end

    assign led = {tx_seen ^ rx_seen, heartbeat[25]};

endmodule
