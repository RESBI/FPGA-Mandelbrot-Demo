`timescale 1ns / 1ps
`include "config.vh"

module uart_rx #(
    parameter CLK_HZ = `CFG_CLK_HZ,
    parameter BAUD = `CFG_UART_BAUD,
    parameter ACC_WIDTH = `CFG_UART_ACC_WIDTH,
    parameter CLOCKS_PER_BIT = CLK_HZ / BAUD
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
    reg [3:0]  bit_counter = 0;
    reg [7:0]  data_reg = 0;
    reg        rx_sync1 = 1;
    reg        rx_sync2 = 1;
    reg [15:0] clk_counter = 0;
    reg [1:0]  sample_sum = 0;

    localparam [15:0] CPB = (CLOCKS_PER_BIT < 4) ? 16'd4 : CLOCKS_PER_BIT[15:0];
    localparam [15:0] SAMPLE0 = (CPB / 2) - 1;
    localparam [15:0] SAMPLE1 = (CPB / 2);
    localparam [15:0] SAMPLE2 = (CPB / 2) + 1;
    wire sample_now = (clk_counter == SAMPLE0) || (clk_counter == SAMPLE1) || (clk_counter == SAMPLE2);
    wire bit_done = (clk_counter == CPB - 1'b1);
    wire [1:0] sample_sum_next = sample_sum + {1'b0, (sample_now ? rx_sync2 : 1'b0)};
    wire majority = (sample_sum_next >= 2);

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
                    clk_counter <= 0;
                    sample_sum <= 0;
                    bit_counter <= 0;
                    state <= STATE_START;
                end
            end

            STATE_START: begin
                if (sample_now)
                    sample_sum <= sample_sum_next;
                if (bit_done) begin
                    clk_counter <= 0;
                    sample_sum <= 0;
                    if (!majority) begin
                        state <= STATE_SAMPLE;
                    end else begin
                        state <= STATE_IDLE;
                    end
                end else begin
                    clk_counter <= clk_counter + 1'b1;
                end
            end

            STATE_SAMPLE: begin
                if (sample_now)
                    sample_sum <= sample_sum_next;
                if (bit_done) begin
                    clk_counter <= 0;
                    if (bit_counter < 8) begin
                        data_reg <= {majority, data_reg[7:1]};
                        sample_sum <= 0;
                        if (bit_counter == 4'd7) begin
                            state <= STATE_STOP;
                        end else begin
                            bit_counter <= bit_counter + 1;
                        end
                    end else begin
                        state <= STATE_STOP;
                    end
                end else begin
                    clk_counter <= clk_counter + 1'b1;
                end
            end

            STATE_STOP: begin
                if (sample_now)
                    sample_sum <= sample_sum_next;
                if (bit_done) begin
                    clk_counter <= 0;
                    sample_sum <= 0;
                    if (majority) begin
                        data <= data_reg;
                        data_avail <= 1;
                    end
                    bit_counter <= 0;
                    // At high baud with no inter-byte gap, the next start edge can
                    // arrive while this receiver is still finishing the stop bit.
                    state <= (!rx_sync2) ? STATE_START : STATE_IDLE;
                end else begin
                    clk_counter <= clk_counter + 1'b1;
                end
            end

            default: state <= STATE_IDLE;
        endcase
    end

endmodule
