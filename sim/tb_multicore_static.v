`timescale 1ns / 1ps
`include "fp_defines.vh"

module tb_multicore_static();

    reg clk = 0;
    reg rst = 1;
    reg ce = 0;
    reg start = 0;
    reg [`FP_WIDTH-1:0] center_re, center_im, step;
    reg [15:0] max_iter, rows, cols;
    reg fifo_full = 0;

    wire busy;
    wire done;
    wire [15:0] fifo_data;
    wire fifo_wr;
    wire tx_start;
    wire [15:0] tx_rows;
    wire [15:0] tx_cols;

    integer pix;
    integer y;
    integer x;
    integer errors;
    reg [15:0] expected;

    mandelbrot_multicore #(
        .CORE_COUNT(4),
        .CORE_FIFO_DEPTH(128),
        .SCHED_MODE(0),
        .WORKER_CONTEXTS(1)
    ) u_dut (
        .clk(clk),
        .rst(rst),
        .ce(ce),
        .start(start),
        .busy(busy),
        .done(done),
        .center_re_in(center_re),
        .center_im_in(center_im),
        .step_in(step),
        .max_iter_in(max_iter),
        .rows_in(rows),
        .cols_in(cols),
        .fifo_data(fifo_data),
        .fifo_wr(fifo_wr),
        .fifo_full(fifo_full),
        .tx_start(tx_start),
        .tx_rows(tx_rows),
        .tx_cols(tx_cols)
    );

    always #5 clk = ~clk;

    always @(posedge clk) begin
        if (rst)
            ce <= 0;
        else
            ce <= ~ce;
    end

    function [`FP_WIDTH-1:0] f64;
        input real val;
        reg [63:0] bits;
        begin
            bits = $realtobits(val);
            f64 = bits;
        end
    endfunction

    function [15:0] sw_iter;
        input integer px;
        input integer py;
        input integer w;
        input integer h;
        input integer limit;
        real cre;
        real cim;
        real zre;
        real zim;
        real zre_sq;
        real zim_sq;
        integer count;
        begin
            cre = -0.5 + (px - ((w - 1) / 2)) * 0.005;
            cim =  0.0 - (py - ((h - 1) / 2)) * 0.005;
            zre = 0.0;
            zim = 0.0;
            count = 0;
            while (count < limit) begin
                zre_sq = zre * zre;
                zim_sq = zim * zim;
                if ((zre_sq + zim_sq) > 4.0) begin
                    count = limit + count;
                end else begin
                    zim = 2.0 * zre * zim + cim;
                    zre = zre_sq - zim_sq + cre;
                    count = count + 1;
                end
            end
            if (count > limit)
                sw_iter = count - limit;
            else
                sw_iter = count[15:0];
        end
    endfunction

    initial begin
        repeat(5) @(posedge clk);
        rst = 0;
        repeat(5) @(posedge clk);

        rows = 12;
        cols = 16;
        max_iter = 64;
        center_re = f64(-0.5);
        center_im = f64(0.0);
        step = f64(0.005);
        pix = 0;
        errors = 0;

        @(negedge clk); start = 1;
        @(negedge clk); start = 0;

        while (pix < rows * cols) begin
            @(posedge clk);
            if (fifo_wr) begin
                y = pix / cols;
                x = pix % cols;
                expected = sw_iter(x, y, cols, rows, max_iter);
                if (fifo_data !== expected) begin
                    $display("FAIL static pix=%0d y=%0d x=%0d got=%0d expected=%0d", pix, y, x, fifo_data, expected);
                    errors = errors + 1;
                end
                pix = pix + 1;
            end
        end

        if (errors != 0) begin
            $display("=== MULTICORE STATIC TEST FAIL: %0d errors ===", errors);
            $finish;
        end

        $display("=== MULTICORE STATIC TEST PASS: %0d pixels ===", pix);
        $finish;
    end

endmodule
