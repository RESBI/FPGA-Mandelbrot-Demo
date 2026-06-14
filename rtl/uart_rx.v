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
    reg [ACC_WIDTH-1:0] baud_acc = 0;

    localparam [ACC_WIDTH-1:0] BAUD_INC = ((BAUD * (64'd1 << ACC_WIDTH)) + (CLK_HZ / 2)) / CLK_HZ;
    localparam [ACC_WIDTH-1:0] HALF_BIT = (64'd1 << (ACC_WIDTH - 1));
    wire [ACC_WIDTH:0] baud_sum = {1'b0, baud_acc} + {1'b0, BAUD_INC};
    wire baud_tick = baud_sum[ACC_WIDTH];

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
                    baud_acc <= HALF_BIT;
                    bit_counter   <= 0;
                    state <= STATE_START;
                end
            end

            STATE_START: begin
                if (baud_tick) begin
                    baud_acc <= baud_sum[ACC_WIDTH-1:0];
                    if (!rx_sync2) begin
                        state <= STATE_SAMPLE;
                    end else begin
                        state <= STATE_IDLE;
                    end
                end else begin
                    baud_acc <= baud_sum[ACC_WIDTH-1:0];
                end
            end

            STATE_SAMPLE: begin
                if (baud_tick) begin
                    baud_acc <= baud_sum[ACC_WIDTH-1:0];
                    if (bit_counter < 8) begin
                        data_reg <= {rx_sync2, data_reg[7:1]};
                        if (bit_counter == 4'd7) begin
                            state <= STATE_STOP;
                        end else begin
                            bit_counter <= bit_counter + 1;
                        end
                    end else begin
                        state <= STATE_STOP;
                    end
                end else begin
                    baud_acc <= baud_sum[ACC_WIDTH-1:0];
                end
            end

            STATE_STOP: begin
                if (baud_tick) begin
                    baud_acc <= baud_sum[ACC_WIDTH-1:0];
                    if (rx_sync2) begin
                        data <= data_reg;
                        data_avail <= 1;
                    end
                    state <= STATE_IDLE;
                end else begin
                    baud_acc <= baud_sum[ACC_WIDTH-1:0];
                end
            end

            default: state <= STATE_IDLE;
        endcase
    end

endmodule
