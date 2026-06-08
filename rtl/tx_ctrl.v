`timescale 1ns / 1ps

module tx_ctrl (
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

    localparam S_IDLE        = 4'd0;
    localparam S_HDR_BYTE    = 4'd1;
    localparam S_HDR_ACK     = 4'd2;
    localparam S_READ_FIFO   = 4'd3;
    localparam S_READ_WAIT   = 4'd4;
    localparam S_SEND_LO     = 4'd5;
    localparam S_SEND_LO_ACK = 4'd6;
    localparam S_SEND_HI     = 4'd7;
    localparam S_SEND_HI_ACK = 4'd8;
    localparam S_CKSUM_BYTE  = 4'd9;
    localparam S_CKSUM_ACK   = 4'd10;

    reg [3:0]  state = S_IDLE;
    reg [31:0] pixel_count;
    reg [31:0] byte_count;   // 2 * pixel_count
    reg [31:0] byte_sent;
    reg [7:0]  checksum;
    reg [2:0]  hdr_idx;
    reg [7:0]  hdr_byte;
    reg [15:0] current_pixel;

    wire [31:0] total_pixels = {16'd0, rows} * {16'd0, cols};
    wire [31:0] total_bytes  = total_pixels * 2;

    always @(*) begin
        case (hdr_idx)
            3'd0: hdr_byte = 8'h52;
            3'd1: hdr_byte = 8'h4B;
            3'd2: hdr_byte = rows[7:0];
            3'd3: hdr_byte = rows[15:8];
            3'd4: hdr_byte = cols[7:0];
            3'd5: hdr_byte = cols[15:8];
            default: hdr_byte = 8'h00;
        endcase
    end

    always @(posedge clk) begin
        if (rst) begin
            state    <= S_IDLE;
            done     <= 0;
            fifo_rd  <= 0;
            tx_en    <= 0;
        end else begin
            case (state)
                S_IDLE: begin
                    done <= 0;
                    fifo_rd <= 0;
                    tx_en <= 0;
                    if (start) begin
                        pixel_count <= total_pixels;
                        byte_count  <= total_bytes;
                        byte_sent   <= 0;
                        checksum    <= 0;
                        hdr_idx     <= 0;
                        state <= S_HDR_BYTE;
                    end
                end

                S_HDR_BYTE: begin
                    if (tx_avail) begin
                        tx_data <= hdr_byte;
                        tx_en   <= 1;
                        state   <= S_HDR_ACK;
                    end
                end

                S_HDR_ACK: begin
                    if (!tx_avail) begin
                        tx_en <= 0;
                        if (hdr_idx == 3'd5) begin
                            state <= S_READ_FIFO;
                        end else begin
                            hdr_idx <= hdr_idx + 1;
                            state <= S_HDR_BYTE;
                        end
                    end
                end

                S_READ_FIFO: begin
                    if (byte_sent >= byte_count) begin
                        state <= S_CKSUM_BYTE;
                    end else if (fifo_avail) begin
                        fifo_rd <= 1;
                        state <= S_READ_WAIT;
                    end
                end

                S_READ_WAIT: begin
                    fifo_rd <= 0;
                    state <= S_SEND_LO;
                end

                // Send lower byte of 16-bit pixel
                S_SEND_LO: begin
                    current_pixel <= fifo_data;
                    if (tx_avail) begin
                        tx_data   <= fifo_data[7:0];
                        tx_en     <= 1;
                        byte_sent <= byte_sent + 1;
                        checksum  <= checksum ^ fifo_data[7:0];
                        state     <= S_SEND_LO_ACK;
                    end
                end

                S_SEND_LO_ACK: begin
                    if (!tx_avail) begin
                        tx_en <= 0;
                        state <= S_SEND_HI;
                    end
                end

                // Send upper byte of 16-bit pixel
                S_SEND_HI: begin
                    if (tx_avail) begin
                        tx_data   <= current_pixel[15:8];
                        tx_en     <= 1;
                        byte_sent <= byte_sent + 1;
                        checksum  <= checksum ^ current_pixel[15:8];
                        state     <= S_SEND_HI_ACK;
                    end
                end

                S_SEND_HI_ACK: begin
                    if (!tx_avail) begin
                        tx_en <= 0;
                        state <= S_READ_FIFO;
                    end
                end

                S_CKSUM_BYTE: begin
                    if (tx_avail) begin
                        tx_data <= checksum;
                        tx_en   <= 1;
                        state   <= S_CKSUM_ACK;
                    end
                end

                S_CKSUM_ACK: begin
                    if (!tx_avail) begin
                        tx_en <= 0;
                        done  <= 1;
                        state <= S_IDLE;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
