`timescale 1ns / 1ps
`include "config.vh"
`include "fx_defines.vh"

module top_with_ram #(
    parameter CLK_HZ = `CFG_CLK_HZ,
    parameter UART_BAUD = `CFG_UART_BAUD,
    parameter CORE_COUNT = `CFG_CORE_COUNT,
    parameter FX_CONTEXTS = `CFG_FX_CONTEXTS,
    parameter WORKER_CONTEXTS = `CFG_WORKER_CONTEXTS,
    parameter WORKER_MODE = `CFG_WORKER_MODE,
    parameter SCHED_MODE = `CFG_SCHED_MODE,
    parameter DYNAMIC_OWNER_DEPTH = `CFG_DYNAMIC_OWNER_DEPTH,
    parameter AXI_DATA_WIDTH = 64,
    parameter AXI_ADDR_WIDTH = 64,
    parameter BURST_BEATS = 16
) (
    input  wire                         aclk,
    input  wire                         aresetn,
    input  wire                         uart_rx,
    output wire                         uart_tx,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI AWADDR" *)
    output wire [AXI_ADDR_WIDTH-1:0]    m_axi_awaddr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI AWLEN" *)
    output wire [7:0]                   m_axi_awlen,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI AWSIZE" *)
    output wire [2:0]                   m_axi_awsize,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI AWBURST" *)
    output wire [1:0]                   m_axi_awburst,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI AWLOCK" *)
    output wire                         m_axi_awlock,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI AWCACHE" *)
    output wire [3:0]                   m_axi_awcache,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI AWPROT" *)
    output wire [2:0]                   m_axi_awprot,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI AWQOS" *)
    output wire [3:0]                   m_axi_awqos,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI AWVALID" *)
    output wire                         m_axi_awvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI AWREADY" *)
    input  wire                         m_axi_awready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI WDATA" *)
    output wire [AXI_DATA_WIDTH-1:0]    m_axi_wdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI WSTRB" *)
    output wire [7:0]                   m_axi_wstrb,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI WLAST" *)
    output wire                         m_axi_wlast,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI WVALID" *)
    output wire                         m_axi_wvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI WREADY" *)
    input  wire                         m_axi_wready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI BRESP" *)
    input  wire [1:0]                   m_axi_bresp,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI BVALID" *)
    input  wire                         m_axi_bvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI BREADY" *)
    output wire                         m_axi_bready
);

    assign m_axi_awlen   = BURST_BEATS - 1;
    assign m_axi_awsize  = 3'd3;
    assign m_axi_awburst = 2'b01;
    assign m_axi_awlock  = 1'b0;
    assign m_axi_awcache = 4'b0011;
    assign m_axi_awprot  = 3'b000;
    assign m_axi_awqos   = 4'b0000;
    assign m_axi_wstrb   = 8'hFF;

    wire [7:0] rx_data;
    wire       rx_valid;
    wire [7:0] tx_data;
    wire       tx_en;
    wire       tx_avail;

    uart_rx #(.CLK_HZ(CLK_HZ)) u_rx (
        .rx(uart_rx), .clk(aclk), .data(rx_data), .data_avail(rx_valid)
    );
    uart_tx #(.CLK_HZ(CLK_HZ)) u_tx (
        .tx(uart_tx), .clk(aclk), .data(tx_data), .transmit_en(tx_en), .transmit_avail(tx_avail)
    );

    wire        compute_start;
    wire        compute_busy;
    wire [`FX_W-1:0] cmd_center_re, cmd_center_im, cmd_step;
    wire [15:0] cmd_max_iter, cmd_rows, cmd_cols;
    wire [63:0] cmd_ddr_base;
    wire        cmd_enter_download;
    wire        done_ack;
    wire        axi_done_sticky;
    wire [2:0]  axi_dbg_state;
    wire [31:0] axi_dbg_p_sent;
    wire [31:0] axi_dbg_p_total;
    wire [3:0]  cmd_dbg_state;

    cmd_parser_v2 #(.FX_W(`FX_W)) u_cmd (
        .clk(aclk), .rstn(aresetn),
        .rx_data(rx_data), .rx_valid(rx_valid),
        .compute_start(compute_start),
        .center_re(cmd_center_re), .center_im(cmd_center_im),
        .step(cmd_step), .max_iter(cmd_max_iter),
        .rows(cmd_rows), .cols(cmd_cols),
        .ddr_base(cmd_ddr_base),
        .enter_download(cmd_enter_download),
        .compute_busy(compute_busy),
        .ddr_write_done(axi_done_sticky),
        .ddr_write_checksum(axi_checksum),
        .done_ack(done_ack),
        .dbg_axi_state(axi_dbg_state),
        .dbg_axi_p_sent(axi_dbg_p_sent),
        .dbg_axi_p_total(axi_dbg_p_total),
        .dbg_fifo_rd_avail(fifo_rd_avail),
        .dbg_fifo_wr_avail(fifo_write_avail),
        .dbg_done_sticky(axi_done_sticky),
        .dbg_cmd_state(cmd_dbg_state),
        .tx_avail(tx_avail), .tx_data(tx_data), .tx_en(tx_en)
    );

    wire [15:0] core_fifo_data;
    wire        core_fifo_wr;
    wire        core_fifo_full;
    wire        core_tx_start;
    wire [15:0] core_tx_rows, core_tx_cols;

    mandelbrot_multicore #(
        .CORE_COUNT(CORE_COUNT),
        .CORE_FIFO_DEPTH(`CFG_CORE_FIFO_DEPTH),
        .SCHED_MODE(SCHED_MODE),
        .DYNAMIC_OWNER_DEPTH(DYNAMIC_OWNER_DEPTH),
        .WORKER_CONTEXTS(WORKER_CONTEXTS),
        .WORKER_ADD_UNITS(`CFG_WORKER_ADD_UNITS),
        .WORKER_MUL_UNITS(`CFG_WORKER_MUL_UNITS),
        .WORKER_MODE(WORKER_MODE),
        .FX_CONTEXTS(FX_CONTEXTS)
    ) u_core (
        .clk(aclk), .rst(~aresetn), .ce(1'b1),
        .start(compute_start), .busy(compute_busy), .done(),
        .center_re_in(cmd_center_re), .center_im_in(cmd_center_im),
        .step_in(cmd_step), .max_iter_in(cmd_max_iter),
        .rows_in(cmd_rows), .cols_in(cmd_cols),
        .fifo_data(core_fifo_data), .fifo_wr(core_fifo_wr),
        .fifo_full(core_fifo_full),
        .tx_start(core_tx_start), .tx_rows(core_tx_rows), .tx_cols(core_tx_cols)
    );

    wire        fifo_write_avail;
    wire        fifo_rd_avail;
    wire        fifo_rd_en;
    wire [15:0] fifo_rd_data;

    assign core_fifo_full = !fifo_write_avail;

    queue #(.DEPTH(`CFG_OUTPUT_FIFO_DEPTH), .DATA_W(16)) u_fifo (
        .clk(aclk), .rst(~aresetn),
        .write_avail(fifo_write_avail), .read_avail(fifo_rd_avail),
        .write_en(core_fifo_wr & ~core_fifo_full),
        .read_en(fifo_rd_en),
        .data_in(core_fifo_data), .data_out(fifo_rd_data)
    );

    reg         axi_start_r;
    reg [63:0]  active_ddr_base;
    reg [31:0]  active_pixel_count;

    always @(posedge aclk) begin
        if (!aresetn) begin
            axi_start_r <= 0;
            active_ddr_base <= 0;
            active_pixel_count <= 0;
        end else begin
            axi_start_r <= 0;
            if (compute_start) begin
                active_ddr_base <= cmd_ddr_base;
                active_pixel_count <= cmd_rows * cmd_cols;
                axi_start_r <= 1;
            end
        end
    end

    wire        axi_done;
    wire [15:0] axi_checksum;

    axi_ddr_writer #(
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .BURST_BEATS(BURST_BEATS)
    ) u_axi_writer (
        .aclk(aclk), .aresetn(aresetn),
        .start(axi_start_r),
        .done_ack(done_ack),
        .base_addr(active_ddr_base),
        .pixel_count(active_pixel_count),
        .done(axi_done), .checksum(axi_checksum),
        .done_sticky(axi_done_sticky),
        .dbg_state(axi_dbg_state),
        .dbg_p_sent(axi_dbg_p_sent),
        .dbg_p_total(axi_dbg_p_total),
        .fifo_rd_en(fifo_rd_en),
        .fifo_rd_data(fifo_rd_data),
        .fifo_rd_avail(fifo_rd_avail),
        .m_axi_awaddr(m_axi_awaddr), .m_axi_awlen(m_axi_awlen),
        .m_axi_awsize(m_axi_awsize), .m_axi_awburst(m_axi_awburst),
        .m_axi_awlock(m_axi_awlock), .m_axi_awcache(m_axi_awcache),
        .m_axi_awprot(m_axi_awprot), .m_axi_awqos(m_axi_awqos),
        .m_axi_awvalid(m_axi_awvalid), .m_axi_awready(m_axi_awready),
        .m_axi_wdata(m_axi_wdata), .m_axi_wstrb(m_axi_wstrb),
        .m_axi_wlast(m_axi_wlast), .m_axi_wvalid(m_axi_wvalid),
        .m_axi_wready(m_axi_wready),
        .m_axi_bresp(m_axi_bresp), .m_axi_bvalid(m_axi_bvalid),
        .m_axi_bready(m_axi_bready)
    );

endmodule
