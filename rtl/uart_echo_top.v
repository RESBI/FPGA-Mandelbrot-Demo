`timescale 1ns / 1ps

module uart_echo_top (
    input  wire uart_rx,
    output wire uart_tx,
    input  wire sys_clk
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

endmodule
