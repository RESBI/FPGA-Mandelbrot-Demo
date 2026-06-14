`timescale 1ns / 1ps
`include "fp_defines.vh"

module cmd_parser (
    input  wire                     clk,
    input  wire                     rst,
    input  wire [7:0]               rx_data,
    input  wire                     rx_avail,
    output reg                      compute_start,
    input  wire                     compute_busy,
    output reg  [`FP_WIDTH-1:0]     center_re,
    output reg  [`FP_WIDTH-1:0]     center_im,
    output reg  [`FP_WIDTH-1:0]     step,
    output reg  [15:0]              max_iter,
    output reg  [15:0]              rows,
    output reg  [15:0]              cols,
    output reg                      precision_mode,
    output reg                      soft_reset
);

    localparam FP_BYTES = `FP_WIDTH / 8;
    localparam CMD_LEN   = 1 + 1 + 2 + 2 + 2 + FP_BYTES*3 + 1;  // magic + prec + rows + cols + maxiter + 3*FP + crc

    localparam S_IDLE  = 0;
    localparam S_READ  = 1;
    localparam S_CHECK = 2;
    localparam S_EXEC  = 3;
    localparam S_WAIT  = 4;
    localparam [63:0] SOFT_RESET_MAGIC = 64'h5253542152535421; // "RST!RST!"

    reg [2:0]  state = S_IDLE;
    reg [8:0]  byte_idx;        // up to 256 for FP128
    reg [7:0]  checksum_calc;
    reg [63:0] reset_shift;
    wire       reset_magic_seen = rx_avail && ({reset_shift[55:0], rx_data} == SOFT_RESET_MAGIC);

    // Shift registers for FP values (little-endian assembly)
    reg [`FP_WIDTH-1:0] cre_shift, cim_shift, step_shift;
    reg [15:0] rows_shift, cols_shift, maxiter_shift;
    reg        prec_shift;

    always @(posedge clk) begin
        if (rst) begin
            state         <= S_IDLE;
            compute_start <= 0;
            rows          <= 0;
            cols          <= 0;
            max_iter      <= 0;
            precision_mode <= 0;
            byte_idx      <= 0;
            soft_reset    <= 0;
            reset_shift   <= 0;
        end else begin
            soft_reset <= 0;
            if (rx_avail)
                reset_shift <= {reset_shift[55:0], rx_data};

            if (reset_magic_seen) begin
                state <= S_IDLE;
                compute_start <= 0;
                byte_idx <= 0;
                soft_reset <= 1;
            end else case (state)
                S_IDLE: begin
                    compute_start <= 0;
                    byte_idx <= 0;
                    if (rx_avail && rx_data == 8'h4D) begin
                        checksum_calc <= 8'h4D;
                        byte_idx <= 1;
                        state <= S_READ;
                    end
                end

                S_READ: begin
                    if (rx_avail) begin
                        checksum_calc <= checksum_calc ^ rx_data;

                        // Route byte to appropriate shift register
                        case (byte_idx)
                            1:                     prec_shift <= rx_data[0];
                            2: rows_shift[7:0] <= rx_data;
                            3: rows_shift[15:8] <= rx_data;
                            4: cols_shift[7:0] <= rx_data;
                            5: cols_shift[15:8] <= rx_data;
                            6: maxiter_shift[7:0] <= rx_data;
                            7: maxiter_shift[15:8] <= rx_data;
                            default: begin
                                // FP bytes
                                if (byte_idx >= 8 && byte_idx < 8 + FP_BYTES) begin
                                    cre_shift[((byte_idx - 8) * 8) +: 8] <= rx_data;
                                end else if (byte_idx >= 8 + FP_BYTES && byte_idx < 8 + 2*FP_BYTES) begin
                                    cim_shift[((byte_idx - 8 - FP_BYTES) * 8) +: 8] <= rx_data;
                                end else if (byte_idx >= 8 + 2*FP_BYTES && byte_idx < 8 + 3*FP_BYTES) begin
                                    step_shift[((byte_idx - 8 - 2*FP_BYTES) * 8) +: 8] <= rx_data;
                                end
                            end
                        endcase

                        if (byte_idx == CMD_LEN - 1) begin
                            state <= S_CHECK;
                        end else begin
                            byte_idx <= byte_idx + 1;
                        end
                    end
                end

                S_CHECK: begin
                    // checksum_calc has XOR of all bytes including received checksum
                    // If correct, result should be 0
                    if (checksum_calc == 8'h00) begin
                        rows      <= rows_shift;
                        cols      <= cols_shift;
                        max_iter  <= maxiter_shift;
                        precision_mode <= prec_shift;
                        center_re <= cre_shift;
                        center_im <= cim_shift;
                        step      <= step_shift;
                        state <= S_EXEC;
                    end else begin
                        state <= S_IDLE;
                    end
                end

                S_EXEC: begin
                    if (!compute_busy && (rows_shift != 0) && (cols_shift != 0)) begin
                        compute_start <= 1;
                        state <= S_WAIT;
                    end else if (rows_shift == 0 || cols_shift == 0) begin
                        state <= S_IDLE;
                    end
                end

                S_WAIT: begin
                    compute_start <= 0;
                    if (!compute_busy) begin
                        state <= S_IDLE;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
