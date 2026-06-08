`timescale 1ns / 1ps
`include "fp_defines.vh"

module tb_core();

    reg clk = 0;
    reg rst = 1;
    reg ce = 0;
    reg start = 0;
    reg [`FP_WIDTH-1:0] center_re, center_im, step;
    reg [15:0] max_iter, rows, cols;
    reg fifo_full = 0;
    integer grid_re;
    integer grid_im;

    wire busy;
    wire done;
    wire [15:0] fifo_data;
    wire fifo_wr;
    wire tx_start;
    wire [15:0] tx_rows;
    wire [15:0] tx_cols;

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

    task run_pixel;
        input real cre;
        input real cim;
        input [15:0] iter_limit;
        input [15:0] expected;
        integer cycles;
        reg seen_wr;
        begin
            center_re = f64(cre);
            center_im = f64(cim);
            step = f64(0.005);
            max_iter = iter_limit;
            rows = 1;
            cols = 1;
            seen_wr = 0;

            @(negedge clk); start = 1;
            @(negedge clk); start = 0;

            for (cycles = 0; cycles < 8000 && !seen_wr; cycles = cycles + 1) begin
                @(posedge clk);
                if (fifo_wr) begin
                    seen_wr = 1;
                    $display("PIXEL c=(%f,%f) iter=%0d expected=%0d", cre, cim, fifo_data, expected);
                    if (fifo_data !== expected) begin
                        $display("FAIL: expected %0d, got %0d", expected, fifo_data);
                        $finish;
                    end
                end
            end

            if (!seen_wr) begin
                $display("FAIL: timeout waiting for fifo_wr for c=(%f,%f)", cre, cim);
                $finish;
            end

            repeat(20) @(posedge clk);
        end
    endtask

    task run_pixel_auto;
        input real cre;
        input real cim;
        input [15:0] iter_limit;
        real zre;
        real zim;
        real zre_sq;
        real zim_sq;
        reg [15:0] expected;
        reg escaped;
        reg seen_wr;
        integer cycles;
        begin
            zre = 0.0;
            zim = 0.0;
            expected = 0;
            escaped = 0;
            while (expected < iter_limit && !escaped) begin
                zre_sq = zre * zre;
                zim_sq = zim * zim;
                if ((zre_sq + zim_sq) > 4.0) begin
                    escaped = 1;
                end else begin
                    zim = 2.0 * zre * zim + cim;
                    zre = zre_sq - zim_sq + cre;
                    expected = expected + 1;
                end
            end
            run_pixel(cre, cim, iter_limit, expected);
        end
    endtask

    task run_first_pixel_auto;
        input real center_re;
        input real center_im;
        input real step;
        input [15:0] iter_limit;
        input [15:0] img_rows;
        input [15:0] img_cols;
        real cre;
        real cim;
        real zre;
        real zim;
        real zre_sq;
        real zim_sq;
        reg [15:0] expected;
        reg escaped;
        reg seen_wr;
        integer cycles;
        begin
            cre = center_re - (((img_cols - 1) >> 1) * step);
            cim = center_im + (((img_rows - 1) >> 1) * step);
            zre = 0.0;
            zim = 0.0;
            expected = 0;
            escaped = 0;
            while (expected < iter_limit && !escaped) begin
                zre_sq = zre * zre;
                zim_sq = zim * zim;
                if ((zre_sq + zim_sq) > 4.0) begin
                    escaped = 1;
                end else begin
                    zim = 2.0 * zre * zim + cim;
                    zre = zre_sq - zim_sq + cre;
                    expected = expected + 1;
                end
            end

            tb_core.center_re = f64(center_re);
            tb_core.center_im = f64(center_im);
            tb_core.step = f64(step);
            max_iter = iter_limit;
            rows = img_rows;
            cols = img_cols;
            seen_wr = 0;

            @(negedge clk); start = 1;
            @(negedge clk); start = 0;

            for (cycles = 0; cycles < 500000 && !seen_wr; cycles = cycles + 1) begin
                @(posedge clk);
                if (fifo_wr) seen_wr = 1;
            end
            if (!seen_wr) begin
                $display("FAIL first pixel: timeout");
                $finish;
            end
            $display("FIRST rows=%0d cols=%0d c=(%f,%f) iter=%0d expected=%0d", img_rows, img_cols, cre, cim, fifo_data, expected);
            if (fifo_data !== expected) begin
                $display("FAIL first pixel: expected %0d, got %0d", expected, fifo_data);
                $finish;
            end

            repeat(20) @(posedge clk);
        end
    endtask

    initial begin
        center_re = 0;
        center_im = 0;
        step = 0;
        max_iter = 0;
        rows = 0;
        cols = 0;

        repeat(8) @(posedge clk);
        rst = 0;
        repeat(8) @(posedge clk);

        run_pixel(2.5, 0.0, 5, 1);
        run_pixel(0.0, 0.0, 5, 5);
        run_pixel(2.6, 0.0, 5, 1);

        run_pixel_auto(-2.0, 0.0, 16);
        run_pixel_auto(-1.0, 0.0, 16);
        run_pixel_auto(-0.75, 0.1, 32);
        run_pixel_auto(-0.5, 0.0, 32);
        run_pixel_auto(0.25, 0.0, 32);
        run_pixel_auto(0.5, 0.5, 32);
        run_pixel_auto(-1.25, 0.25, 32);
        run_pixel_auto(-0.125, 0.75, 32);
        run_pixel_auto(1.0, 1.0, 16);
        run_pixel_auto(-1.75, -0.05, 32);

        for (grid_re = 0; grid_re <= 6; grid_re = grid_re + 1) begin
            for (grid_im = 0; grid_im <= 4; grid_im = grid_im + 1) begin
                run_pixel_auto(-2.0 + (0.5 * grid_re), -1.0 + (0.5 * grid_im), 32);
            end
        end

        run_first_pixel_auto(-0.5, 0.0, 0.005, 256, 120, 160);

        $display("=== CORE TEST PASS ===");
        $finish;
    end

endmodule
