`timescale 1ns / 1ps
`include "config.vh"

module tx_ctrl #(
    parameter RESPONSE_TILE_COLS = `CFG_RESPONSE_TILE_COLS,
    parameter RESPONSE_TILE_GAP_CYCLES = `CFG_RESPONSE_TILE_GAP_CYCLES
) (
    input  wire         clk,
    input  wire         rst,
    input  wire         start,
    input  wire [15:0]  rows,
    input  wire [15:0]  cols,
    output reg          done,

    output reg          fifo_rd,
    input  wire [15:0]  fifo_data,
    input  wire         fifo_avail,

    output reg  [7:0]   tx_data,
    output reg          tx_en,
    input  wire         tx_avail
);

    localparam S_IDLE           = 5'd0;
    localparam S_FRAME_HDR_BYTE = 5'd1;
    localparam S_FRAME_HDR_ACK  = 5'd2;
    localparam S_TILE_HDR_BYTE  = 5'd3;
    localparam S_TILE_HDR_ACK   = 5'd4;
    localparam S_READ_FIFO      = 5'd5;
    localparam S_READ_WAIT      = 5'd6;
    localparam S_SEND_LO        = 5'd7;
    localparam S_SEND_LO_ACK    = 5'd8;
    localparam S_SEND_HI        = 5'd9;
    localparam S_SEND_HI_ACK    = 5'd10;
    localparam S_TILE_CKSUM     = 5'd11;
    localparam S_TILE_CKSUM_ACK = 5'd12;
    localparam S_TILE_GAP       = 5'd13;
    localparam S_END_BYTE       = 5'd14;
    localparam S_END_ACK        = 5'd15;
    reg [4:0]  state = S_IDLE;
    reg [2:0]  frame_hdr_idx;
    reg [3:0]  tile_hdr_idx;
    reg [2:0]  end_idx;
    reg [15:0] row_idx;
    reg [15:0] tile_col_start;
    reg [15:0] col_idx;
    reg [15:0] current_pixel;
    reg [7:0]  checksum;
    reg [31:0] gap_count;
    reg [7:0]  frame_hdr_byte;
    reg [7:0]  tile_hdr_byte;
    reg [7:0]  end_byte;

    wire [15:0] remaining_cols = cols - tile_col_start;
    wire [15:0] tile_cols = (remaining_cols > RESPONSE_TILE_COLS) ? RESPONSE_TILE_COLS : remaining_cols;

    always @(*) begin
        case (frame_hdr_idx)
            3'd0: frame_hdr_byte = 8'h52; // R
            3'd1: frame_hdr_byte = 8'h54; // T: tiled response
            3'd2: frame_hdr_byte = rows[7:0];
            3'd3: frame_hdr_byte = rows[15:8];
            3'd4: frame_hdr_byte = cols[7:0];
            3'd5: frame_hdr_byte = cols[15:8];
            default: frame_hdr_byte = 8'h00;
        endcase

        case (tile_hdr_idx)
            4'd0: tile_hdr_byte = 8'h54; // T
            4'd1: tile_hdr_byte = 8'h44; // D: tile data
            4'd2: tile_hdr_byte = row_idx[7:0];
            4'd3: tile_hdr_byte = row_idx[15:8];
            4'd4: tile_hdr_byte = tile_col_start[7:0];
            4'd5: tile_hdr_byte = tile_col_start[15:8];
            4'd6: tile_hdr_byte = 8'h01; // tile_rows low
            4'd7: tile_hdr_byte = 8'h00; // tile_rows high
            4'd8: tile_hdr_byte = tile_cols[7:0];
            4'd9: tile_hdr_byte = tile_cols[15:8];
            default: tile_hdr_byte = 8'h00;
        endcase

        case (end_idx)
            3'd0: end_byte = 8'h54; // T
            3'd1: end_byte = 8'h45; // E: end
            3'd2: end_byte = rows[7:0];
            3'd3: end_byte = rows[15:8];
            3'd4: end_byte = cols[7:0];
            3'd5: end_byte = cols[15:8];
            default: end_byte = 8'h00;
        endcase
    end

    always @(posedge clk) begin
        if (rst) begin
            state   <= S_IDLE;
            done    <= 0;
            fifo_rd <= 0;
            tx_en   <= 0;
        end else begin
            fifo_rd <= 0;
            case (state)
                S_IDLE: begin
                    done  <= 0;
                    tx_en <= 0;
                    if (start) begin
                        frame_hdr_idx <= 0;
                        row_idx       <= 0;
                        tile_col_start <= 0;
                        col_idx       <= 0;
                        state         <= S_FRAME_HDR_BYTE;
                    end
                end

                S_FRAME_HDR_BYTE: begin
                    if (tx_avail) begin
                        tx_data <= frame_hdr_byte;
                        tx_en   <= 1;
                        state   <= S_FRAME_HDR_ACK;
                    end
                end

                S_FRAME_HDR_ACK: begin
                    if (!tx_avail) begin
                        tx_en <= 0;
                        if (frame_hdr_idx == 3'd5) begin
                            if (rows == 0 || cols == 0) begin
                                end_idx <= 0;
                                state   <= S_END_BYTE;
                            end else begin
                                tile_hdr_idx <= 0;
                                checksum     <= 0;
                                state        <= S_TILE_HDR_BYTE;
                            end
                        end else begin
                            frame_hdr_idx <= frame_hdr_idx + 1;
                            state <= S_FRAME_HDR_BYTE;
                        end
                    end
                end

                S_TILE_HDR_BYTE: begin
                    if (tx_avail) begin
                        tx_data <= tile_hdr_byte;
                        tx_en   <= 1;
                        state   <= S_TILE_HDR_ACK;
                    end
                end

                S_TILE_HDR_ACK: begin
                    if (!tx_avail) begin
                        tx_en <= 0;
                        if (tile_hdr_idx == 4'd9) begin
                            col_idx <= 0;
                            state   <= S_READ_FIFO;
                        end else begin
                            tile_hdr_idx <= tile_hdr_idx + 1;
                            state <= S_TILE_HDR_BYTE;
                        end
                    end
                end

                S_READ_FIFO: begin
                    if (col_idx >= tile_cols) begin
                        state <= S_TILE_CKSUM;
                    end else if (fifo_avail) begin
                        fifo_rd <= 1;
                        state   <= S_READ_WAIT;
                    end
                end

                S_READ_WAIT: begin
                    state <= S_SEND_LO;
                end

                S_SEND_LO: begin
                    current_pixel <= fifo_data;
                    if (tx_avail) begin
                        tx_data  <= fifo_data[7:0];
                        tx_en    <= 1;
                        checksum <= checksum ^ fifo_data[7:0];
                        state    <= S_SEND_LO_ACK;
                    end
                end

                S_SEND_LO_ACK: begin
                    if (!tx_avail) begin
                        tx_en <= 0;
                        state <= S_SEND_HI;
                    end
                end

                S_SEND_HI: begin
                    if (tx_avail) begin
                        tx_data  <= current_pixel[15:8];
                        tx_en    <= 1;
                        checksum <= checksum ^ current_pixel[15:8];
                        col_idx  <= col_idx + 1;
                        state    <= S_SEND_HI_ACK;
                    end
                end

                S_SEND_HI_ACK: begin
                    if (!tx_avail) begin
                        tx_en <= 0;
                        state <= S_READ_FIFO;
                    end
                end

                S_TILE_CKSUM: begin
                    if (tx_avail) begin
                        tx_data <= checksum;
                        tx_en   <= 1;
                        state   <= S_TILE_CKSUM_ACK;
                    end
                end

                S_TILE_CKSUM_ACK: begin
                    if (!tx_avail) begin
                        tx_en <= 0;
                        gap_count <= 0;
                        state     <= S_TILE_GAP;
                    end
                end

                S_TILE_GAP: begin
                    if (gap_count < RESPONSE_TILE_GAP_CYCLES) begin
                        gap_count <= gap_count + 1;
                    end else if (tile_col_start + tile_cols >= cols) begin
                        if (row_idx + 1 >= rows) begin
                            end_idx <= 0;
                            state   <= S_END_BYTE;
                        end else begin
                            row_idx        <= row_idx + 1;
                            tile_col_start <= 0;
                            tile_hdr_idx   <= 0;
                            checksum       <= 0;
                            state          <= S_TILE_HDR_BYTE;
                        end
                    end else begin
                        tile_col_start <= tile_col_start + tile_cols;
                        tile_hdr_idx   <= 0;
                        checksum       <= 0;
                        state          <= S_TILE_HDR_BYTE;
                    end
                end

                S_END_BYTE: begin
                    if (tx_avail) begin
                        tx_data <= end_byte;
                        tx_en   <= 1;
                        state   <= S_END_ACK;
                    end
                end

                S_END_ACK: begin
                    if (!tx_avail) begin
                        tx_en <= 0;
                        if (end_idx == 3'd5) begin
                            done  <= 1;
                            state <= S_IDLE;
                        end else begin
                            end_idx <= end_idx + 1;
                            state   <= S_END_BYTE;
                        end
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
