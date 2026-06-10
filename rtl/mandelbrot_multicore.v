`timescale 1ns / 1ps
`include "fp_defines.vh"

module mandelbrot_multicore #(
    parameter CORE_COUNT = 4,
    parameter CORE_FIFO_DEPTH = 4096,
    parameter SCHED_MODE = 0,
    parameter DYNAMIC_OWNER_DEPTH = 4096
) (
    input  wire                     clk,
    input  wire                     rst,
    input  wire                     ce,
    input  wire                     start,
    output wire                     busy,
    output wire                     done,
    input  wire [`FP_WIDTH-1:0]     center_re_in,
    input  wire [`FP_WIDTH-1:0]     center_im_in,
    input  wire [`FP_WIDTH-1:0]     step_in,
    input  wire [15:0]              max_iter_in,
    input  wire [15:0]              rows_in,
    input  wire [15:0]              cols_in,

    output wire [15:0]              fifo_data,
    output wire                     fifo_wr,
    input  wire                     fifo_full,

    output reg                      tx_start,
    output reg  [15:0]              tx_rows,
    output reg  [15:0]              tx_cols
);

    wire [CORE_COUNT-1:0] core_start;
    wire [CORE_COUNT*16-1:0] row_start_bus;
    wire [CORE_COUNT*16-1:0] row_stride_bus;

    wire [CORE_COUNT-1:0] core_busy;
    wire [CORE_COUNT-1:0] core_done;
    wire [CORE_COUNT-1:0] core_fifo_wr;
    wire [CORE_COUNT*16-1:0] core_fifo_wdata;
    wire [CORE_COUNT-1:0] core_fifo_full;
    wire [CORE_COUNT-1:0] core_fifo_write_avail;
    wire [CORE_COUNT-1:0] core_fifo_rd;
    wire [CORE_COUNT-1:0] core_fifo_avail;
    wire [CORE_COUNT*16-1:0] core_fifo_rdata;

    wire owner_wr;
    wire [15:0] owner_row;
    wire [7:0]  owner_core;

    reg active;
    wire merge_done;

    assign busy = active;
    assign done = merge_done;

    generate
        if (SCHED_MODE == 0) begin : g_static_sched
            work_dispatch_static_rows #(.CORE_COUNT(CORE_COUNT)) u_dispatch (
                .start          (start),
                .core_start     (core_start),
                .row_start_bus  (row_start_bus),
                .row_stride_bus (row_stride_bus)
            );

            assign owner_wr = 1'b0;
            assign owner_row = 16'd0;
            assign owner_core = 8'd0;
        end else begin : g_dynamic_sched
            work_dispatch_dynamic_rows #(.CORE_COUNT(CORE_COUNT)) u_dispatch (
                .clk            (clk),
                .rst            (rst),
                .start          (start),
                .rows           (rows_in),
                .core_done      (core_done),
                .core_start     (core_start),
                .row_start_bus  (row_start_bus),
                .row_stride_bus (row_stride_bus),
                .owner_wr       (owner_wr),
                .owner_row      (owner_row),
                .owner_core     (owner_core)
            );
        end
    endgenerate

    genvar i;
    generate
        for (i = 0; i < CORE_COUNT; i = i + 1) begin : g_core
            assign core_fifo_full[i] = !core_fifo_write_avail[i];

            mandelbrot_core_worker u_worker (
                .clk          (clk),
                .rst          (rst),
                .ce           (ce),
                .start        (core_start[i]),
                .busy         (core_busy[i]),
                .done         (core_done[i]),
                .center_re_in (center_re_in),
                .center_im_in (center_im_in),
                .step_in      (step_in),
                .max_iter_in  (max_iter_in),
                .rows_in      (rows_in),
                .cols_in      (cols_in),
                .row_start_in (row_start_bus[i*16 +: 16]),
                .row_stride_in(row_stride_bus[i*16 +: 16]),
                .fifo_data    (core_fifo_wdata[i*16 +: 16]),
                .fifo_wr      (core_fifo_wr[i]),
                .fifo_full    (core_fifo_full[i])
            );

            queue #(.DEPTH(CORE_FIFO_DEPTH), .DATA_W(16)) u_fifo (
                .clk         (clk),
                .write_avail (core_fifo_write_avail[i]),
                .read_avail  (core_fifo_avail[i]),
                .write_en    (core_fifo_wr[i]),
                .read_en     (core_fifo_rd[i]),
                .data_in     (core_fifo_wdata[i*16 +: 16]),
                .data_out    (core_fifo_rdata[i*16 +: 16])
            );
        end
    endgenerate

    generate
        if (SCHED_MODE == 0) begin : g_static_merge
            raster_merge_static_rows #(.CORE_COUNT(CORE_COUNT)) u_merge (
                .clk             (clk),
                .rst             (rst),
                .start           (start),
                .rows            (rows_in),
                .cols            (cols_in),
                .done            (merge_done),
                .core_fifo_rd    (core_fifo_rd),
                .core_fifo_avail (core_fifo_avail),
                .core_fifo_data  (core_fifo_rdata),
                .fifo_data       (fifo_data),
                .fifo_wr         (fifo_wr),
                .fifo_full       (fifo_full)
            );
        end else begin : g_dynamic_collect
            raster_collect_dynamic_rows #(
                .CORE_COUNT(CORE_COUNT),
                .OWNER_TABLE_DEPTH(DYNAMIC_OWNER_DEPTH)
            ) u_merge (
                .clk             (clk),
                .rst             (rst),
                .start           (start),
                .rows            (rows_in),
                .cols            (cols_in),
                .done            (merge_done),
                .owner_wr        (owner_wr),
                .owner_row       (owner_row),
                .owner_core      (owner_core),
                .core_fifo_rd    (core_fifo_rd),
                .core_fifo_avail (core_fifo_avail),
                .core_fifo_data  (core_fifo_rdata),
                .fifo_data       (fifo_data),
                .fifo_wr         (fifo_wr),
                .fifo_full       (fifo_full)
            );
        end
    endgenerate

    always @(posedge clk) begin
        if (rst) begin
            active <= 0;
            tx_start <= 0;
            tx_rows <= 0;
            tx_cols <= 0;
        end else begin
            tx_start <= 0;
            if (start && !active) begin
                active <= 1;
                tx_rows <= rows_in;
                tx_cols <= cols_in;
                tx_start <= 1;
            end else if (merge_done) begin
                active <= 0;
            end
        end
    end

endmodule
