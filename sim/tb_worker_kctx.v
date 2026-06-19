`timescale 1ns / 1ps
`include "fp_defines.vh"

module tb_worker_kctx #(
    parameter CONTEXTS = 4,
    parameter TEST_ROWS = 12,
    parameter TEST_COLS = 160,
    parameter TEST_MAX_ITER = 256,
    parameter TEST_ROW_START = 0,
    parameter DEBUG_X = -1,
    parameter STALL_AFTER = -1,
    parameter STALL_CYCLES = 0,
    parameter TIMEOUT_CYCLES = 10000000
) ();

    reg clk = 0;
    reg rst = 1;
    reg ce = 0;
    reg start = 0;
    reg [`FP_WIDTH-1:0] center_re, center_im, step;
    reg fifo_full = 0;

    wire busy;
    wire done;
    wire [15:0] fifo_data;
    wire fifo_wr;

    integer pix;
    integer errors;
    reg [15:0] expected;
    integer dbg_i;
    integer stall_left;

    mandelbrot_core_worker_kctx #(
        .CONTEXTS(CONTEXTS)
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
        .max_iter_in(TEST_MAX_ITER[15:0]),
        .rows_in(TEST_ROWS[15:0]),
        .cols_in(TEST_COLS[15:0]),
        .row_start_in(TEST_ROW_START[15:0]),
        .row_stride_in(TEST_ROWS[15:0]),
        .fifo_data(fifo_data),
        .fifo_wr(fifo_wr),
        .fifo_full(fifo_full)
    );

    always #5 clk = ~clk;

    always @(posedge clk) begin
        if (rst)
            ce <= 0;
        else
            ce <= 1'b1;
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

        center_re = f64(-0.5);
        center_im = f64(0.0);
        step = f64(0.005);
        pix = 0;
        errors = 0;
        stall_left = 0;

        @(negedge clk); start = 1;
        @(negedge clk); start = 0;

        while (pix < TEST_COLS) begin
            @(posedge clk);
            if (fifo_wr) begin
                expected = sw_iter(pix, TEST_ROW_START, TEST_COLS, TEST_ROWS, TEST_MAX_ITER);
                if (fifo_data !== expected) begin
                    $display("FAIL worker row=%0d x=%0d got=%0d expected=%0d", TEST_ROW_START, pix, fifo_data, expected);
                    errors = errors + 1;
                end
                pix = pix + 1;
                if (STALL_AFTER >= 0 && pix == STALL_AFTER)
                    stall_left = STALL_CYCLES;
            end
            if (stall_left > 0) begin
                fifo_full = 1;
                stall_left = stall_left - 1;
            end else begin
                fifo_full = 0;
            end
        end

        if (errors != 0) begin
            $display("=== WORKER KCTX TEST FAIL: %0d errors ===", errors);
            $finish;
        end

        $display("=== WORKER KCTX TEST PASS: %0d pixels ===", pix);
        $finish;
    end

    initial begin
        repeat (TIMEOUT_CYCLES) @(posedge clk);
        $display("=== WORKER KCTX TEST TIMEOUT: pix=%0d expected=%0d ===", pix, TEST_COLS);
        $finish;
    end

    always @(posedge clk) begin
        if (DEBUG_X >= 0) begin
            for (dbg_i = 0; dbg_i < CONTEXTS; dbg_i = dbg_i + 1) begin
                if (u_dut.c_active[dbg_i] && u_dut.c_col[dbg_i] == DEBUG_X[15:0]) begin
                    if (u_dut.mul_done_op != u_dut.MOP_NONE && u_dut.mul_done_ctx == dbg_i[1:0])
                        $display("DBG t=%0t ctx=%0d col=%0d iter=%0d mul_done_op=%0d state=%0d", $time, dbg_i, u_dut.c_col[dbg_i], u_dut.c_iter[dbg_i], u_dut.mul_done_op, u_dut.c_state[dbg_i]);
                    if (u_dut.mul_done_op != u_dut.MOP_NONE && u_dut.mul_done_ctx == dbg_i[1:0] && u_dut.c_iter[dbg_i] >= 120)
                        $display("DBG_MUL t=%0t iter=%0d op=%0d zre=%h zim=%h mul_result=%h", $time, u_dut.c_iter[dbg_i], u_dut.mul_done_op, u_dut.c_z_re[dbg_i], u_dut.c_z_im[dbg_i], u_dut.mul_result);
                    if (u_dut.add_done_op != u_dut.AOP_NONE && u_dut.add_done_ctx == dbg_i[1:0])
                        $display("DBG t=%0t ctx=%0d col=%0d iter=%0d add_done_op=%0d state=%0d escape=%0d mag_done=%0d zrzi_done=%0d", $time, dbg_i, u_dut.c_col[dbg_i], u_dut.c_iter[dbg_i], u_dut.add_done_op, u_dut.c_state[dbg_i], u_dut.c_escape[dbg_i], u_dut.c_mag_done[dbg_i], u_dut.c_zrzi_done[dbg_i]);
                    if (u_dut.add_done_op == u_dut.AOP_MAG && u_dut.add_done_ctx == dbg_i[1:0] && u_dut.c_iter[dbg_i] >= 120)
                        $display("DBG_MAG t=%0t iter=%0d zre_sq=%h zim_sq=%h mag=%h qre=%0d qim=%0d qmag=%0d", $time, u_dut.c_iter[dbg_i], u_dut.c_z_re_sq[dbg_i], u_dut.c_z_im_sq[dbg_i], u_dut.add_result, u_dut.quick_esc(u_dut.c_z_re_sq[dbg_i]), u_dut.quick_esc(u_dut.c_z_im_sq[dbg_i]), u_dut.quick_esc(u_dut.add_result));
                    if (u_dut.add_done_op == u_dut.AOP_NEXT_IM && u_dut.add_done_ctx == dbg_i[1:0] && u_dut.c_iter[dbg_i] >= 120)
                        $display("DBG_NEXT t=%0t iter=%0d next_re=%h next_im=%h", $time, u_dut.c_iter[dbg_i], u_dut.c_next_re[dbg_i], u_dut.add_result);
                    if (u_dut.c_result_valid[dbg_i])
                        $display("DBG t=%0t ctx=%0d col=%0d RESULT iter=%0d", $time, dbg_i, u_dut.c_col[dbg_i], u_dut.c_result_iter[dbg_i]);
                end
            end
        end
    end

endmodule
