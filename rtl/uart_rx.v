`timescale 1ns / 1ps

module uart_rx #(
    parameter CLOCKS_PER_BIT = 200
) (
    input  wire         rx,
    input  wire         clk,
    output reg  [7:0]   data,
    output reg          data_avail
);

    localparam STATE_IDLE   = 0;
    localparam STATE_START  = 1;
    localparam STATE_SAMPLE = 2;
    localparam STATE_STOP   = 3;

    reg [2:0]  state = STATE_IDLE;
    reg [12:0] clock_counter = 0;
    reg [3:0]  bit_counter = 0;
    reg [7:0]  data_reg = 0;
    reg        rx_sync1 = 1;
    reg        rx_sync2 = 1;

    always @(posedge clk) begin
        rx_sync1 <= rx;
        rx_sync2 <= rx_sync1;
    end

    wire start_edge = (rx_sync2 == 1'b1) && (rx_sync1 == 1'b0);

    always @(posedge clk) begin
        case (state)
            STATE_IDLE: begin
                data_avail <= 0;
                if (start_edge) begin
                    clock_counter <= 0;
                    bit_counter   <= 0;
                    state <= STATE_START;
                end
            end

            STATE_START: begin
                if (clock_counter == ((CLOCKS_PER_BIT - 1) / 2)) begin
                    clock_counter <= 0;
                    state <= STATE_SAMPLE;
                end else begin
                    clock_counter <= clock_counter + 1;
                end
            end

            STATE_SAMPLE: begin
                if (clock_counter == (CLOCKS_PER_BIT - 1)) begin
                    clock_counter <= 0;
                    if (bit_counter < 8) begin
                        data_reg <= {rx_sync2, data_reg[7:1]};
                        bit_counter <= bit_counter + 1;
                    end else begin
                        state <= STATE_STOP;
                    end
                end else begin
                    clock_counter <= clock_counter + 1;
                end
            end

            STATE_STOP: begin
                if (clock_counter == ((CLOCKS_PER_BIT - 1) / 2)) begin
                    clock_counter <= 0;
                    data <= data_reg;
                    data_avail <= 1;
                    state <= STATE_IDLE;
                end else begin
                    clock_counter <= clock_counter + 1;
                end
            end

            default: state <= STATE_IDLE;
        endcase
    end

endmodule
