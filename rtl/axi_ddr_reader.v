`timescale 1ns / 1ps

module axi_ddr_reader #(
    parameter AXI_DATA_WIDTH = 64,
    parameter AXI_ADDR_WIDTH = 64,
    parameter MAX_BURST_BEATS = 16,
    parameter BEAT_FIFO_DEPTH = 16
) (
    input  wire                         aclk,
    input  wire                         aresetn,
    input  wire                         start,
    input  wire [AXI_ADDR_WIDTH-1:0]    base_addr,
    input  wire [31:0]                  pixel_count,
    output wire                         busy,
    output reg                          done,
    output reg                          error,
    output reg  [1:0]                   error_resp,

    input  wire                         pixel_rd_en,
    output reg  [15:0]                  pixel_rd_data,
    output wire                         pixel_rd_avail,

    output reg  [AXI_ADDR_WIDTH-1:0]    m_axi_araddr,
    output reg  [7:0]                   m_axi_arlen,
    output wire [2:0]                   m_axi_arsize,
    output wire [1:0]                   m_axi_arburst,
    output wire                         m_axi_arlock,
    output wire [3:0]                   m_axi_arcache,
    output wire [2:0]                   m_axi_arprot,
    output wire [3:0]                   m_axi_arqos,
    output reg                          m_axi_arvalid,
    input  wire                         m_axi_arready,
    input  wire [AXI_DATA_WIDTH-1:0]    m_axi_rdata,
    input  wire [1:0]                   m_axi_rresp,
    input  wire                         m_axi_rlast,
    input  wire                         m_axi_rvalid,
    output wire                         m_axi_rready
);

    localparam RD_IDLE       = 3'd0;
    localparam RD_PLAN       = 3'd1;
    localparam RD_AR         = 3'd2;
    localparam RD_R          = 3'd3;
    localparam RD_WAIT_DRAIN = 3'd4;
    localparam RD_DONE       = 3'd5;
    localparam RD_ERR_DRAIN  = 3'd6;
    localparam RD_ERROR      = 3'd7;

    localparam PX_IDLE    = 2'd0;
    localparam PX_READ    = 2'd1;
    localparam PX_CAPTURE = 2'd2;
    localparam PX_HAVE    = 2'd3;

    reg [2:0] rd_state;
    reg [1:0] px_state;
    reg [AXI_ADDR_WIDTH-1:0] current_addr;
    reg [31:0] beats_remaining;
    reg [7:0] burst_beats;
    reg [7:0] burst_received;
    reg [31:0] pixels_total;
    reg [31:0] pixels_served;
    reg [AXI_DATA_WIDTH-1:0] pixel_beat;
    reg [1:0] pixel_lane;
    reg error_pending;
    reg [1:0] error_resp_pending;

    wire beat_fifo_write_avail;
    wire beat_fifo_read_avail;
    wire [AXI_DATA_WIDTH-1:0] beat_fifo_data;
    wire beat_fifo_write = (rd_state == RD_R) && m_axi_rvalid && m_axi_rready;
    wire beat_fifo_read = (px_state == PX_READ);
    wire beat_fifo_reset = ~aresetn || (start && rd_state == RD_IDLE);

    assign m_axi_arsize  = 3'd3;
    assign m_axi_arburst = 2'b01;
    assign m_axi_arlock  = 1'b0;
    assign m_axi_arcache = 4'b0011;
    assign m_axi_arprot  = 3'b000;
    assign m_axi_arqos   = 4'b0000;
    assign m_axi_rready  = ((rd_state == RD_R) && beat_fifo_write_avail) ||
                           (rd_state == RD_ERR_DRAIN);
    assign pixel_rd_avail = (px_state == PX_HAVE) && (pixels_served < pixels_total);
    assign busy = (rd_state != RD_IDLE) || (px_state != PX_IDLE) || beat_fifo_read_avail;

    function [7:0] calc_burst_beats;
        input [31:0] remaining;
        input [11:0] addr_low;
        reg [12:0] bytes_to_4k;
        reg [9:0] beats_to_4k;
        reg [31:0] count;
        begin
            bytes_to_4k = 13'd4096 - {1'b0, addr_low};
            beats_to_4k = bytes_to_4k >> 3;
            count = MAX_BURST_BEATS;
            if (remaining < count)
                count = remaining;
            if (beats_to_4k < count)
                count = beats_to_4k;
            if (count == 0)
                count = 1;
            calc_burst_beats = count[7:0];
        end
    endfunction

    queue #(
        .DEPTH(BEAT_FIFO_DEPTH),
        .DATA_W(AXI_DATA_WIDTH)
    ) u_beat_fifo (
        .clk(aclk),
        .rst(beat_fifo_reset),
        .write_avail(beat_fifo_write_avail),
        .read_avail(beat_fifo_read_avail),
        .write_en(beat_fifo_write),
        .read_en(beat_fifo_read),
        .data_in(m_axi_rdata),
        .data_out(beat_fifo_data)
    );

    always @(posedge aclk) begin
        if (!aresetn) begin
            rd_state <= RD_IDLE;
            current_addr <= 0;
            beats_remaining <= 0;
            burst_beats <= 0;
            burst_received <= 0;
            pixels_total <= 0;
            m_axi_araddr <= 0;
            m_axi_arlen <= 0;
            m_axi_arvalid <= 0;
            done <= 0;
            error <= 0;
            error_resp <= 0;
            error_pending <= 0;
            error_resp_pending <= 0;
        end else begin
            done <= 0;

            case (rd_state)
                RD_IDLE: begin
                    m_axi_arvalid <= 0;
                    if (start) begin
                        current_addr <= base_addr;
                        beats_remaining <= (pixel_count + 32'd3) >> 2;
                        pixels_total <= pixel_count;
                        error <= 0;
                        error_resp <= 0;
                        error_pending <= 0;
                        error_resp_pending <= 0;
                        rd_state <= (pixel_count == 0) ? RD_DONE : RD_PLAN;
                    end
                end

                RD_PLAN: begin
                    if (!beat_fifo_read_avail && px_state == PX_IDLE) begin
                        burst_beats <= calc_burst_beats(beats_remaining, current_addr[11:0]);
                        m_axi_araddr <= current_addr;
                        m_axi_arlen <= calc_burst_beats(beats_remaining, current_addr[11:0]) - 1'b1;
                        m_axi_arvalid <= 1;
                        rd_state <= RD_AR;
                    end
                end

                RD_AR: begin
                    if (m_axi_arvalid && m_axi_arready) begin
                        m_axi_arvalid <= 0;
                        burst_received <= 0;
                        rd_state <= RD_R;
                    end
                end

                RD_R: begin
                    if (m_axi_rvalid && m_axi_rready) begin
                        if (m_axi_rresp != 2'b00) begin
                            error_pending <= 1;
                            error_resp_pending <= m_axi_rresp;
                        end

                        burst_received <= burst_received + 1'b1;
                        if (m_axi_rlast && (burst_received + 1'b1) < burst_beats) begin
                            error_pending <= 1;
                            error_resp_pending <= 2'b10;
                            rd_state <= RD_ERROR;
                        end else if ((burst_received + 1'b1) >= burst_beats) begin
                            if (!m_axi_rlast) begin
                                error_pending <= 1;
                                error_resp_pending <= 2'b10;
                                rd_state <= RD_ERR_DRAIN;
                            end else if (error_pending || m_axi_rresp != 2'b00) begin
                                rd_state <= RD_ERROR;
                            end else begin
                                current_addr <= current_addr + ({56'd0, burst_beats} << 3);
                                beats_remaining <= beats_remaining - burst_beats;
                                rd_state <= RD_WAIT_DRAIN;
                            end
                        end
                    end
                end

                RD_WAIT_DRAIN: begin
                    if (!beat_fifo_read_avail && px_state == PX_IDLE) begin
                        if (beats_remaining == 0 && pixels_served >= pixels_total)
                            rd_state <= RD_DONE;
                        else if (beats_remaining != 0)
                            rd_state <= RD_PLAN;
                    end
                end

                RD_DONE: begin
                    done <= 1;
                    rd_state <= RD_IDLE;
                end

                RD_ERR_DRAIN: begin
                    if (m_axi_rvalid && m_axi_rready && m_axi_rlast)
                        rd_state <= RD_ERROR;
                end

                RD_ERROR: begin
                    error <= 1;
                    error_resp <= error_resp_pending;
                end

                default: rd_state <= RD_IDLE;
            endcase
        end
    end

    always @(posedge aclk) begin
        if (!aresetn) begin
            px_state <= PX_IDLE;
            pixels_served <= 0;
            pixel_beat <= 0;
            pixel_lane <= 0;
            pixel_rd_data <= 0;
        end else if (start && rd_state == RD_IDLE) begin
            px_state <= PX_IDLE;
            pixels_served <= 0;
            pixel_beat <= 0;
            pixel_lane <= 0;
            pixel_rd_data <= 0;
        end else begin
            case (px_state)
                PX_IDLE: begin
                    if (beat_fifo_read_avail && pixels_served < pixels_total)
                        px_state <= PX_READ;
                end

                PX_READ: begin
                    px_state <= PX_CAPTURE;
                end

                PX_CAPTURE: begin
                    pixel_beat <= beat_fifo_data;
                    pixel_lane <= 0;
                    px_state <= PX_HAVE;
                end

                PX_HAVE: begin
                    if (pixel_rd_en && pixels_served < pixels_total) begin
                        case (pixel_lane)
                            2'd0: pixel_rd_data <= pixel_beat[15:0];
                            2'd1: pixel_rd_data <= pixel_beat[31:16];
                            2'd2: pixel_rd_data <= pixel_beat[47:32];
                            default: pixel_rd_data <= pixel_beat[63:48];
                        endcase
                        pixels_served <= pixels_served + 1'b1;
                        if ((pixels_served + 1'b1) >= pixels_total || pixel_lane == 2'd3) begin
                            pixel_lane <= 0;
                            px_state <= PX_IDLE;
                        end else begin
                            pixel_lane <= pixel_lane + 1'b1;
                        end
                    end
                end

                default: px_state <= PX_IDLE;
            endcase
        end
    end

endmodule
