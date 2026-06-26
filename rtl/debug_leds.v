`timescale 1ns / 1ps

module debug_leds #(
    parameter UART_STRETCH_BITS = 23
) (
    input  wire        clk,
    input  wire        rst,
    input  wire [3:2]  led_state,
    input  wire        uart_rx_pulse,
    input  wire        uart_tx_pulse,
    output wire [3:2]  led
);

    reg [UART_STRETCH_BITS-1:0] rx_stretch = {UART_STRETCH_BITS{1'b0}};
    reg [UART_STRETCH_BITS-1:0] tx_stretch = {UART_STRETCH_BITS{1'b0}};

    always @(posedge clk) begin
        if (rst) begin
            rx_stretch <= {UART_STRETCH_BITS{1'b0}};
            tx_stretch <= {UART_STRETCH_BITS{1'b0}};
        end else begin
            if (uart_rx_pulse)
                rx_stretch <= {UART_STRETCH_BITS{1'b1}};
            else if (rx_stretch != 0)
                rx_stretch <= rx_stretch - 1'b1;

            if (uart_tx_pulse)
                tx_stretch <= {UART_STRETCH_BITS{1'b1}};
            else if (tx_stretch != 0)
                tx_stretch <= tx_stretch - 1'b1;
        end
    end

    assign led = led_state;

endmodule
