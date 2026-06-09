`timescale 1ns / 1ps

module uart_tx #(
    parameter CLOCKS_PER_BIT = 174
) (
    output reg          tx,
    input  wire         clk,
    input  wire [7:0]   data,
    input  wire         transmit_en,
    output reg          transmit_avail
);

    localparam IDLE      = 0;
    localparam START_BIT = 1;
    localparam DATA_BITS = 2;
    localparam STOP_BIT  = 3;

    reg [2:0]  state = IDLE;
    reg [7:0]  data_temp;
    reg [3:0]  bit_counter;
    reg [15:0] clock_counter = 0;

    always @(posedge clk) begin
        case (state)
            IDLE: begin
                transmit_avail <= 1;
                tx <= 1;
                clock_counter <= 0;
                if (transmit_en) begin
                    data_temp <= data;
                    bit_counter <= 0;
                    transmit_avail <= 0;
                    state <= START_BIT;
                end
            end

            START_BIT: begin
                tx <= 0;
                if (clock_counter == CLOCKS_PER_BIT - 1) begin
                    clock_counter <= 0;
                    state <= DATA_BITS;
                end else begin
                    clock_counter <= clock_counter + 1;
                end
            end

            DATA_BITS: begin
                tx <= data_temp[bit_counter];
                if (clock_counter == CLOCKS_PER_BIT - 1) begin
                    clock_counter <= 0;
                    if (bit_counter == 4'd7) begin
                        state <= STOP_BIT;
                    end else begin
                        bit_counter <= bit_counter + 1;
                    end
                end else begin
                    clock_counter <= clock_counter + 1;
                end
            end

            STOP_BIT: begin
                tx <= 1;
                if (clock_counter == CLOCKS_PER_BIT - 1) begin
                    clock_counter <= 0;
                    state <= IDLE;
                end else begin
                    clock_counter <= clock_counter + 1;
                end
            end

            default: state <= IDLE;
        endcase
    end

endmodule
