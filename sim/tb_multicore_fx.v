`timescale 1ns / 1ps
`include "fx_defines.vh"

module tb_multicore_fx #(
    parameter CORE_COUNT = 4,
    parameter FX_CONTEXTS = 4,
    parameter TEST_ROWS = 12,
    parameter TEST_COLS = 16,
    parameter TEST_MAX_ITER = 64,
    parameter CORE_FIFO_DEPTH = 128,
    parameter TIMEOUT_CYCLES = 2000000
);

    reg clk = 0;
    reg rst = 1;
    reg ce = 1;
    reg start = 0;
    wire busy;
    wire done;
    reg [`FX_W-1:0] center_re, center_im, step;
    reg [15:0] max_iter, rows, cols;
    wire [15:0] fifo_data;
    wire fifo_wr;
    wire fifo_full = 1'b0;
    wire tx_start;
    wire [15:0] tx_rows, tx_cols;

    always #2.5 clk = ~clk;

    localparam real FX_SCALE = 2.0 ** `FX_FRAC;

    mandelbrot_multicore #(
        .CORE_COUNT(CORE_COUNT),
        .CORE_FIFO_DEPTH(CORE_FIFO_DEPTH),
        .SCHED_MODE(1),
        .DYNAMIC_OWNER_DEPTH(256),
        .WORKER_CONTEXTS(4),
        .WORKER_MODE(1),
        .FX_CONTEXTS(FX_CONTEXTS)
    ) u_core (
        .clk(clk), .rst(rst), .ce(ce),
        .start(start), .busy(busy), .done(done),
        .center_re_in(center_re), .center_im_in(center_im),
        .step_in(step), .max_iter_in(max_iter),
        .rows_in(rows), .cols_in(cols),
        .fifo_data(fifo_data), .fifo_wr(fifo_wr), .fifo_full(fifo_full),
        .tx_start(tx_start), .tx_rows(tx_rows), .tx_cols(tx_cols)
    );

    reg [15:0] out_fifo_data;
    reg out_fifo_wr;
    wire out_fifo_full = 1'b0;
    reg [31:0] pixel_count = 0;
    reg [15:0] received [0:4095];
    integer errors = 0;
    integer total_pixels;

    localparam signed [`FX_W-1:0] four_fx_ref = 64'sh4 << `FX_FRAC;

    function [15:0] fx_iter_ref;
        input [`FX_W-1:0] cre_fx, cim_fx;
        input [15:0] maxi;
        reg signed [`FX_W-1:0] zr, zi, zr2, zi2, zrzi, mag;
        integer i;
        begin
            zr = 0; zi = 0;
            fx_iter_ref = maxi;
            for (i = 0; i < maxi; i = i + 1) begin
                zr2 = (zr * zr) >>> `FX_FRAC;
                zi2 = (zi * zi) >>> `FX_FRAC;
                mag = zr2 + zi2;
                if (mag > four_fx_ref) begin
                    fx_iter_ref = i;
                    i = maxi + 1;
                end else begin
                    zrzi = (zr * zi) >>> `FX_FRAC;
                    zi = (zrzi <<< 1) + cim_fx;
                    zr = zr2 - zi2 + cre_fx;
                end
            end
        end
    endfunction

    always @(posedge clk) begin
        out_fifo_wr <= 0;
        if (fifo_wr && !out_fifo_full) begin
            out_fifo_wr <= 1;
            out_fifo_data <= fifo_data;
            received[pixel_count] <= fifo_data;
            pixel_count <= pixel_count + 1;
        end
    end

    integer r, c, idx;
    reg signed [`FX_W-1:0] cre_start, cim_start, step_fx;
    reg [15:0] expected;

    initial begin
        center_re = 64'hFFC0000000000000;
        center_im = 64'h0000000000000000;
        step = 64'h00028F5C28F5C28F;
        max_iter = TEST_MAX_ITER;
        rows = TEST_ROWS;
        cols = TEST_COLS;

        #20 rst = 0;
        #10 start = 1;
        #5 start = 0;

        total_pixels = TEST_ROWS * TEST_COLS;

        wait (pixel_count >= total_pixels || done);
        #50;

        cre_start = center_re - $signed({16'b0, (cols - 1) >> 1}) * step;
        cim_start = center_im + $signed({16'b0, (rows - 1) >> 1}) * step;
        step_fx = step;

        errors = 0;
        for (r = 0; r < TEST_ROWS; r = r + 1) begin
            for (c = 0; c < TEST_COLS; c = c + 1) begin
                idx = r * TEST_COLS + c;
                expected = fx_iter_ref(cre_start + c * step_fx, cim_start - r * step_fx, TEST_MAX_ITER);
                if (received[idx] !== expected) begin
                    if (errors < 20)
                        $display("MISMATCH row=%0d col=%0d got=%0d exp=%0d", r, c, received[idx], expected);
                    errors = errors + 1;
                end
            end
        end

        if (errors == 0)
            $display("=== FX MULTICORE TEST PASS: %0d pixels ===", total_pixels);
        else
            $display("=== FX MULTICORE TEST FAIL: %0d errors out of %0d ===", errors, total_pixels);

        $finish;
    end

    initial begin
        #(TIMEOUT_CYCLES * 5);
        $display("=== FX MULTICORE TEST TIMEOUT ===");
        $finish;
    end

endmodule
