`timescale 1ns / 1ps

module axi_ddr_writer #(
    parameter AXI_DATA_WIDTH = 64,
    parameter AXI_ADDR_WIDTH = 64,
    parameter BURST_BEATS = 16
) (
    input  wire                         aclk,
    input  wire                         aresetn,
    input  wire                         start,
    input  wire                         done_ack,
    input  wire [AXI_ADDR_WIDTH-1:0]    base_addr,
    input  wire [31:0]                  pixel_count,
    output wire                         busy,
    output reg                          done,
    output reg  [15:0]                  checksum,
    output reg                          error,
    output reg  [1:0]                   error_resp,
    output wire                         done_sticky,
    output wire [2:0]                   dbg_state,
    output wire [31:0]                  dbg_p_sent,
    output wire [31:0]                  dbg_p_total,
    output wire                         fifo_rd_en,
    input  wire [15:0]                  fifo_rd_data,
    input  wire                         fifo_rd_avail,
    output reg  [AXI_ADDR_WIDTH-1:0]    m_axi_awaddr,
    output wire [7:0]                   m_axi_awlen,
    output wire [2:0]                   m_axi_awsize,
    output wire [1:0]                   m_axi_awburst,
    output wire                         m_axi_awlock,
    output wire [3:0]                   m_axi_awcache,
    output wire [2:0]                   m_axi_awprot,
    output wire [3:0]                   m_axi_awqos,
    output reg                          m_axi_awvalid,
    input  wire                         m_axi_awready,
    output reg  [AXI_DATA_WIDTH-1:0]    m_axi_wdata,
    output wire [7:0]                   m_axi_wstrb,
    output reg                          m_axi_wlast,
    output reg                          m_axi_wvalid,
    input  wire                         m_axi_wready,
    input  wire [1:0]                   m_axi_bresp,
    input  wire                         m_axi_bvalid,
    output reg                          m_axi_bready
);

    assign m_axi_awlen   = BURST_BEATS - 1;
    assign m_axi_awsize  = 3'd3;
    assign m_axi_awburst = 2'b01;
    assign m_axi_awlock  = 1'b0;
    assign m_axi_awcache = 4'b0011;
    assign m_axi_awprot  = 3'b000;
    assign m_axi_awqos   = 4'b0000;
    assign m_axi_wstrb   = 8'hFF;

    localparam ST_IDLE      = 3'd0;
    localparam ST_AW        = 3'd1;
    localparam ST_GET       = 3'd2;
    localparam ST_READ_WAIT = 3'd3;
    localparam ST_PACK      = 3'd4;
    localparam ST_W         = 3'd5;
    localparam ST_B         = 3'd6;
    localparam ST_DONE      = 3'd7;

    reg [2:0]  state;
    reg [31:0] p_total, p_sent;
    reg [AXI_ADDR_WIDTH-1:0] addr;
    reg [7:0]  beat;
    reg [1:0]  pidx;
    reg [63:0] wbuf;
    reg [15:0] cks;
    reg        rd_r;
    reg        done_latched;

    assign fifo_rd_en  = rd_r;
    assign busy        = (state != ST_IDLE);
    assign done_sticky = done_latched;
    assign dbg_state   = state;
    assign dbg_p_sent  = p_sent;
    assign dbg_p_total = p_total;

    always @(posedge aclk) begin
        if (!aresetn) begin
            state <= ST_IDLE; p_total<=0; p_sent<=0; addr<=0;
            beat<=0; pidx<=0; wbuf<=0; cks<=0; rd_r<=0;
            done<=0; done_latched<=0; checksum<=0; error<=0; error_resp<=0;
            m_axi_awvalid<=0; m_axi_wvalid<=0; m_axi_wlast<=0;
            m_axi_bready<=0; m_axi_awaddr<=0; m_axi_wdata<=0;
        end else begin
            done <= 0;
            rd_r <= 0;
            if (start)
                done_latched <= 0;
            if (done_ack)
                done_latched <= 0;

            case (state)
                ST_IDLE: begin
                    if (start) begin
                        p_total <= pixel_count;
                        p_sent <= 0;
                        addr <= base_addr;
                        beat <= 0;
                        pidx <= 0;
                        cks <= 0;
                        error <= 0;
                        error_resp <= 0;
                        m_axi_awaddr <= base_addr;
                        m_axi_awvalid <= 1;
                        m_axi_wvalid <= 0;
                        state <= ST_AW;
                    end
                end

                ST_AW: begin
                    if (m_axi_awvalid && m_axi_awready) begin
                        m_axi_awvalid <= 0;
                        state <= ST_GET;
                    end
                end

                ST_GET: begin
                    if (p_sent < p_total && fifo_rd_avail) begin
                        rd_r <= 1;
                        state <= ST_READ_WAIT;
                    end else if (p_sent >= p_total) begin
                        wbuf[16*pidx +: 16] <= 16'd0;
                        if (pidx == 2'd3) begin
                            m_axi_wdata <= {16'd0, wbuf[47:0]};
                            m_axi_wvalid <= 1;
                            m_axi_wlast <= (beat + 1 >= BURST_BEATS);
                            pidx <= 0;
                            beat <= beat + 1;
                            state <= ST_W;
                        end else begin
                            pidx <= pidx + 1;
                        end
                    end
                end

                ST_READ_WAIT: begin
                    state <= ST_PACK;
                end

                ST_PACK: begin
                    wbuf[16*pidx +: 16] <= fifo_rd_data;
                    cks <= cks ^ fifo_rd_data;
                    p_sent <= p_sent + 1;
                    if (pidx == 2'd3) begin
                        m_axi_wdata <= {fifo_rd_data, wbuf[47:0]};
                        m_axi_wvalid <= 1;
                        m_axi_wlast <= (beat + 1 >= BURST_BEATS);
                        pidx <= 0;
                        beat <= beat + 1;
                        state <= ST_W;
                    end else begin
                        pidx <= pidx + 1;
                        state <= ST_GET;
                    end
                end

                ST_W: begin
                    if (m_axi_wvalid && m_axi_wready) begin
                        m_axi_wvalid <= 0;
                        if (m_axi_wlast) begin
                            m_axi_bready <= 1;
                            state <= ST_B;
                        end else begin
                            state <= ST_GET;
                        end
                    end
                end

                ST_B: begin
                    if (m_axi_bvalid && m_axi_bready) begin
                        m_axi_bready <= 0;
                        beat <= 0;
                        if (m_axi_bresp != 2'b00) begin
                            error <= 1;
                            error_resp <= m_axi_bresp;
                        end
                        if (p_sent >= p_total) begin
                            state <= ST_DONE;
                        end else begin
                            addr <= addr + (BURST_BEATS * 8);
                            m_axi_awaddr <= addr + (BURST_BEATS * 8);
                            m_axi_awvalid <= 1;
                            state <= ST_AW;
                        end
                    end
                end

                ST_DONE: begin
                    done <= 1;
                    done_latched <= 1;
                    checksum <= cks;
                    state <= ST_IDLE;
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
