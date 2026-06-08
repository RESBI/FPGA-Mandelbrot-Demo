`timescale 1ns / 1ps
`include "fp_defines.vh"

module tb_core_count();
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

    integer count;
    integer cycles;
    integer x;
    integer y;
    integer idx;
    integer mismatch;
    reg [15:0] expected_mem [0:19199];

    mandelbrot_core u_core (
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

    always @(posedge clk) begin
        if (fifo_wr) begin
            if (count < rows * cols && fifo_data !== expected_mem[count]) begin
                y = count / cols;
                x = count - (y * cols);
                if (mismatch < 20)
                    $display("MISMATCH [%0d,%0d] idx=%0d got=%0d expected=%0d", y, x, count, fifo_data, expected_mem[count]);
                mismatch <= mismatch + 1;
            end
            count <= count + 1;
        end
    end

    function [15:0] sw_iter;
        input real cre;
        input real cim;
        input [15:0] limit;
        real zre;
        real zim;
        real zre_sq;
        real zim_sq;
        reg [15:0] it;
        reg escaped;
        begin
            zre = 0.0;
            zim = 0.0;
            it = 0;
            escaped = 0;
            while (it < limit && !escaped) begin
                zre_sq = zre * zre;
                zim_sq = zim * zim;
                if ((zre_sq + zim_sq) > 4.0) begin
                    escaped = 1;
                end else begin
                    zim = 2.0 * zre * zim + cim;
                    zre = zre_sq - zim_sq + cre;
                    it = it + 1;
                end
            end
            sw_iter = it;
        end
    endfunction

    initial begin
        center_re = f64(-0.5);
        center_im = f64(0.0);
        step = f64(0.005);
        max_iter = 128;
        rows = 120;
        cols = 160;
        count = 0;
        mismatch = 0;

        for (idx = 0; idx < 19200; idx = idx + 1) begin
            y = idx / cols;
            x = idx - (y * cols);
            expected_mem[idx] = sw_iter(-0.5 - (((cols - 1) >> 1) * 0.005) + (x * 0.005),
                                        0.0 + (((rows - 1) >> 1) * 0.005) - (y * 0.005),
                                        max_iter);
        end

        repeat(8) @(posedge clk);
        rst = 0;
        repeat(8) @(posedge clk);

        @(negedge clk); start = 1;
        @(negedge clk); start = 0;

        for (cycles = 0; cycles < 200000000 && !done; cycles = cycles + 1) begin
            @(posedge clk);
        end

        $display("COUNT rows=%0d cols=%0d max_iter=%0d count=%0d expected=%0d mismatch=%0d done=%0d busy=%0d state=%0d row=%0d col=%0d",
            rows, cols, max_iter, count, rows * cols, mismatch, done, busy, u_core.state, u_core.row, u_core.col);
        if (count !== rows * cols || mismatch != 0) begin
            $display("FAIL: wrong output stream");
            $finish;
        end

        $display("=== CORE COUNT PASS ===");
        $finish;
    end
endmodule
