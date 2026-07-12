`timescale 1ns / 1ps

module cmd_parser_v2 #(
    parameter FX_W = 64
) (
    input  wire        clk,
    input  wire        rstn,
    input  wire [7:0]  rx_data,
    input  wire        rx_valid,

    output reg         compute_start,
    output reg  [FX_W-1:0] center_re,
    output reg  [FX_W-1:0] center_im,
    output reg  [FX_W-1:0] step,
    output reg  [15:0] max_iter,
    output reg  [15:0] rows,
    output reg  [15:0] cols,
    output reg  [63:0] ddr_base,
    output reg         enter_download,
    output reg  [63:0] download_base,
    output reg  [15:0] download_rows,
    output reg  [15:0] download_cols,
    input  wire        compute_busy,
    input  wire        ddr_write_busy,
    input  wire        download_busy,
    input  wire        ddr_write_done,
    input  wire [15:0] ddr_write_checksum,
    input  wire        ddr_write_error,
    output reg         done_ack,

    input  wire [2:0]  dbg_axi_state,
    input  wire [31:0] dbg_axi_p_sent,
    input  wire [31:0] dbg_axi_p_total,
    input  wire        dbg_fifo_rd_avail,
    input  wire        dbg_fifo_wr_avail,
    input  wire        dbg_done_sticky,
    input  wire [3:0]  dbg_cmd_state,

    input  wire        tx_avail,
    output reg  [7:0]  tx_data,
    output reg         tx_en,
    output wire        tx_idle
);

    localparam TYPE_COMPUTE_TILE   = 8'h10;
    localparam TYPE_ENTER_DOWNLOAD = 8'h11;
    localparam TYPE_QUERY_STATUS   = 8'h02;
    localparam TYPE_ACK            = 8'h81;
    localparam TYPE_TILE_DONE      = 8'h84;
    localparam TYPE_DEBUG_STATUS   = 8'h90;

    localparam S_RX_SYNC0 = 4'd0;
    localparam S_RX_SYNC1 = 4'd1;
    localparam S_RX_TYPE  = 4'd2;
    localparam S_RX_LEN   = 4'd3;
    localparam S_RX_PAY   = 4'd4;
    localparam S_RX_CSUM  = 4'd5;
    localparam S_TX_SYNC0 = 4'd6;
    localparam S_TX_SYNC1 = 4'd7;
    localparam S_TX_TYPE  = 4'd8;
    localparam S_TX_LEN   = 4'd9;
    localparam S_TX_PAY   = 4'd10;
    localparam S_TX_CSUM  = 4'd11;

    reg [3:0] state = S_RX_SYNC0;
    reg [7:0] frame_type;
    reg [7:0] frame_len;
    reg [7:0] pay_idx;
    reg [7:0] rx_sum;
    reg [335:0] rx_payload;

    reg [7:0] tx_ftype;
    reg [7:0] tx_flen;
    reg [7:0] tx_idx;
    reg [7:0] tx_sum;
    reg [103:0] tx_payload;

    reg        ack_pending;
    reg [7:0]  ack_status;
    reg        tile_done_pending;
    reg [15:0] done_checksum;
    reg [7:0]  done_status;
    reg        debug_status_pending;
    reg        ddr_done_seen;

    wire system_busy = compute_busy || ddr_write_busy || ddr_write_done ||
                       tile_done_pending || download_busy;
    assign tx_idle = (state == S_RX_SYNC0) && !tx_en && !ack_pending &&
                     !tile_done_pending && !debug_status_pending;

    always @(posedge clk) begin
        if (!rstn) begin
            state <= S_RX_SYNC0;
            compute_start <= 0;
            enter_download <= 0;
            download_base <= 0;
            download_rows <= 0;
            download_cols <= 0;
            tx_en <= 0;
            tx_data <= 8'hFF;
            done_ack <= 0;
            ack_pending <= 0;
            tile_done_pending <= 0;
            debug_status_pending <= 0;
            ddr_done_seen <= 0;
            done_status <= 0;
            frame_type <= 0; frame_len <= 0; pay_idx <= 0;
            rx_sum <= 0; rx_payload <= 0;
        end else begin
            compute_start <= 0;
            enter_download <= 0;
            tx_en <= 0;
            done_ack <= 0;

            if (!ddr_write_done)
                ddr_done_seen <= 0;

            if (ddr_write_done && !compute_busy && !tile_done_pending && !ddr_done_seen) begin
                tile_done_pending <= 1;
                done_checksum <= ddr_write_checksum;
                done_status <= ddr_write_error ? 8'd4 : 8'd0;
                ddr_done_seen <= 1;
            end

            case (state)
                S_RX_SYNC0: begin
                    if (rx_valid && rx_data == 8'h55) begin
                        state <= S_RX_SYNC1;
                    end else if (ack_pending) begin
                        tx_ftype <= TYPE_ACK;
                        tx_flen <= 8'd1;
                        tx_payload <= {96'd0, ack_status};
                        tx_idx <= 0;
                        ack_pending <= 0;
                        state <= S_TX_SYNC0;
                    end else if (tile_done_pending) begin
                        tx_ftype <= TYPE_TILE_DONE;
                        tx_flen <= 8'd4;
                        tx_payload <= {72'd0, 8'd0, done_status, done_checksum};
                        tx_idx <= 0;
                        tile_done_pending <= 0;
                        state <= S_TX_SYNC0;
                    end else if (debug_status_pending) begin
                        tx_ftype <= TYPE_DEBUG_STATUS;
                        tx_flen <= 8'd13;
                        tx_payload[7:0]   <= state[3:0];
                        tx_payload[15:8]  <= {compute_busy, ddr_write_busy, ddr_write_done, tile_done_pending, ack_pending, dbg_fifo_rd_avail, dbg_fifo_wr_avail, dbg_done_sticky};
                        tx_payload[23:16] <= dbg_axi_state;
                        tx_payload[31:24] <= dbg_cmd_state;
                        tx_payload[39:32] <= dbg_axi_p_sent[7:0];
                        tx_payload[47:40] <= dbg_axi_p_total[7:0];
                        tx_payload[55:48] <= done_checksum[7:0];
                        tx_payload[63:56] <= done_checksum[15:8];
                        tx_payload[71:64] <= ack_status;
                        tx_payload[79:72] <= rows[7:0];
                        tx_payload[87:80] <= cols[7:0];
                        tx_payload[95:88] <= max_iter[7:0];
                        tx_payload[103:96] <= 8'd0;
                        tx_idx <= 0;
                        debug_status_pending <= 0;
                        state <= S_TX_SYNC0;
                    end
                end

                S_RX_SYNC1: begin
                    if (rx_valid) begin
                        if (rx_data == 8'hAA) state <= S_RX_TYPE;
                        else if (rx_data != 8'h55) state <= S_RX_SYNC0;
                    end
                end

                S_RX_TYPE: begin
                    if (rx_valid) begin
                        frame_type <= rx_data;
                        rx_sum <= rx_data;
                        state <= S_RX_LEN;
                    end
                end

                S_RX_LEN: begin
                    if (rx_valid) begin
                        frame_len <= rx_data;
                        rx_sum <= rx_sum + rx_data;
                        pay_idx <= 0;
                        rx_payload <= 0;
                        state <= (rx_data == 0) ? S_RX_CSUM : S_RX_PAY;
                    end
                end

                S_RX_PAY: begin
                    if (rx_valid) begin
                        if (pay_idx < 8'd42)
                            rx_payload[8*pay_idx +: 8] <= rx_data;
                        rx_sum <= rx_sum + rx_data;
                        pay_idx <= pay_idx + 1'b1;
                        if (pay_idx == frame_len - 1) state <= S_RX_CSUM;
                    end
                end

                S_RX_CSUM: begin
                    if (rx_valid) begin
                        if ((rx_sum + rx_data) == 8'd0) begin
                            if (frame_type == TYPE_COMPUTE_TILE && frame_len == 8'd42) begin
                                ack_pending <= 1;
                                if (system_busy) begin
                                    ack_status <= 8'd1;
                                end else if (rx_payload[246:240] != 0) begin
                                    ack_status <= 8'd2;
                                end else if (rx_payload[223:208] == 0 || rx_payload[239:224] == 0) begin
                                    ack_status <= 8'd3;
                                end else begin
                                    center_re <= rx_payload[63:0];
                                    center_im <= rx_payload[127:64];
                                    step <= rx_payload[191:128];
                                    max_iter <= rx_payload[207:192];
                                    rows <= rx_payload[223:208];
                                    cols <= rx_payload[239:224];
                                    ddr_base <= rx_payload[303:240];
                                    compute_start <= 1;
                                    ack_status <= 0;
                                end
                            end else if (frame_type == TYPE_ENTER_DOWNLOAD && frame_len == 8'd12) begin
                                ack_pending <= 1;
                                if (system_busy) begin
                                    ack_status <= 8'd1;
                                end else if (rx_payload[6:0] != 0) begin
                                    ack_status <= 8'd2;
                                end else if (rx_payload[79:64] == 0 || rx_payload[95:80] == 0) begin
                                    ack_status <= 8'd3;
                                end else begin
                                    download_base <= rx_payload[63:0];
                                    download_rows <= rx_payload[79:64];
                                    download_cols <= rx_payload[95:80];
                                    enter_download <= 1;
                                    ack_status <= 0;
                                end
                            end else if (frame_type == TYPE_QUERY_STATUS && frame_len == 0) begin
                                debug_status_pending <= 1;
                            end
                        end
                        state <= S_RX_SYNC0;
                    end
                end

                S_TX_SYNC0: begin
                    if (tx_avail) begin
                        tx_data <= 8'h55; tx_en <= 1;
                        state <= S_TX_SYNC1;
                    end
                end
                S_TX_SYNC1: begin
                    if (tx_avail && ~tx_en) begin
                        tx_data <= 8'hAA; tx_en <= 1;
                        state <= S_TX_TYPE;
                    end
                end
                S_TX_TYPE: begin
                    if (tx_avail && ~tx_en) begin
                        tx_data <= tx_ftype; tx_en <= 1;
                        tx_sum <= tx_ftype;
                        state <= S_TX_LEN;
                    end
                end
                S_TX_LEN: begin
                    if (tx_avail && ~tx_en) begin
                        tx_data <= tx_flen; tx_en <= 1;
                        tx_sum <= tx_sum + tx_flen;
                        tx_idx <= 0;
                        state <= S_TX_PAY;
                    end
                end
                S_TX_PAY: begin
                    if (tx_avail && ~tx_en) begin
                        tx_data <= tx_payload[7:0]; tx_en <= 1;
                        tx_sum <= tx_sum + tx_payload[7:0];
                        tx_payload <= {8'd0, tx_payload[103:8]};
                        tx_idx <= tx_idx + 1'b1;
                        if (tx_idx == tx_flen - 1) state <= S_TX_CSUM;
                    end
                end
                S_TX_CSUM: begin
                    if (tx_avail && ~tx_en) begin
                        tx_data <= (~tx_sum) + 1'b1; tx_en <= 1;
                        if (tx_ftype == TYPE_TILE_DONE)
                            done_ack <= 1;
                        state <= S_RX_SYNC0;
                    end
                end
                default: state <= S_RX_SYNC0;
            endcase
        end
    end

endmodule
