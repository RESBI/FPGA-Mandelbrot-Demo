`timescale 1ns / 1ps

module raster_merge_static_rows #(
    parameter CORE_COUNT = 4
) (
    input  wire                     clk,
    input  wire                     rst,
    input  wire                     start,
    input  wire [15:0]              rows,
    input  wire [15:0]              cols,
    output reg                      done,

    output reg  [CORE_COUNT-1:0]    core_fifo_rd,
    input  wire [CORE_COUNT-1:0]    core_fifo_avail,
    input  wire [CORE_COUNT*16-1:0] core_fifo_data,

    output reg  [15:0]              fifo_data,
    output reg                      fifo_wr,
    input  wire                     fifo_full
);

    localparam S_IDLE      = 3'd0;
    localparam S_WAIT      = 3'd1;
    localparam S_READ_WAIT = 3'd2;
    localparam S_WRITE     = 3'd3;
    localparam S_DONE      = 3'd4;

    reg [2:0]  state = S_IDLE;
    reg [15:0] row;
    reg [15:0] col;
    reg [31:0] pixels_written;
    reg [31:0] total_pixels;
    reg [15:0] selected_pixel;
    reg [7:0]  src_core;

    integer j;

    always @(*) begin
        src_core = row % CORE_COUNT;
    end

    always @(posedge clk) begin
        if (rst) begin
            state <= S_IDLE;
            done <= 0;
            fifo_wr <= 0;
            core_fifo_rd <= 0;
        end else begin
            fifo_wr <= 0;
            core_fifo_rd <= 0;

            case (state)
                S_IDLE: begin
                    done <= 0;
                    if (start) begin
                        row <= 0;
                        col <= 0;
                        pixels_written <= 0;
                        total_pixels <= {16'd0, rows} * {16'd0, cols};
                        state <= (rows == 0 || cols == 0) ? S_DONE : S_WAIT;
                    end
                end

                S_WAIT: begin
                    if (pixels_written >= total_pixels) begin
                        state <= S_DONE;
                    end else if (!fifo_full && core_fifo_avail[src_core]) begin
                        for (j = 0; j < CORE_COUNT; j = j + 1)
                            core_fifo_rd[j] <= (j == src_core);
                        state <= S_READ_WAIT;
                    end
                end

                S_READ_WAIT: begin
                    state <= S_WRITE;
                end

                S_WRITE: begin
                    if (!fifo_full) begin
                        selected_pixel = core_fifo_data[src_core*16 +: 16];
                        fifo_data <= selected_pixel;
                        fifo_wr <= 1;
                        pixels_written <= pixels_written + 1;

                        if ((col + 1) >= cols) begin
                            col <= 0;
                            row <= row + 1;
                        end else begin
                            col <= col + 1;
                        end

                        if ((pixels_written + 1) >= total_pixels)
                            state <= S_DONE;
                        else
                            state <= S_WAIT;
                    end
                end

                S_DONE: begin
                    done <= 1;
                    state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
