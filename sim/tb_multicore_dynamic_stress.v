`timescale 1ns / 1ps
`include "fp_defines.vh"

module tb_multicore_dynamic_stress();

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
    integer cycles;

    mandelbrot_multicore #(
        .CORE_COUNT(4),
        .CORE_FIFO_DEPTH(4096),
        .SCHED_MODE(1),
        .DYNAMIC_OWNER_DEPTH(128),
        .WORKER_CONTEXTS(2)
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

    initial begin
        repeat(5) @(posedge clk);
        rst = 0;
        repeat(5) @(posedge clk);

        rows = 48;
        cols = 64;
        max_iter = 64;
        center_re = f64(-0.5);
        center_im = f64(0.0);
        step = f64(0.01);
        pix = 0;
        cycles = 0;

        @(negedge clk); start = 1;
        @(negedge clk); start = 0;

        while (pix < rows * cols && cycles < 5000000) begin
            @(posedge clk);
            cycles = cycles + 1;
            if (fifo_wr)
                pix = pix + 1;
        end

        if (pix != rows * cols) begin
            $display("=== DYNAMIC 2CTX STRESS FAIL: pixels=%0d expected=%0d cycles=%0d busy=%0d done=%0d ===", pix, rows * cols, cycles, busy, done);
            $display("core_busy=%b core_done=%b core_avail=%b", u_dut.core_busy, u_dut.core_done, u_dut.core_fifo_avail);
            $display("w0 state=%0d pipe=%0d launch=%0d commit=%0d crepend=%0d inflight=%0d/%0d/%0d/%0d c0=%0d/%0d/%0d/%0d/%0d c1=%0d/%0d/%0d/%0d/%0d add0=%0d mul0=%0d",
                u_dut.g_core[0].g_worker_2ctx.u_worker.state,
                u_dut.g_core[0].g_worker_2ctx.u_worker.pipe_wait,
                u_dut.g_core[0].g_worker_2ctx.u_worker.launch_col,
                u_dut.g_core[0].g_worker_2ctx.u_worker.commit_col,
                u_dut.g_core[0].g_worker_2ctx.u_worker.c_re_add_pending,
                u_dut.g_core[0].g_worker_2ctx.u_worker.mag_inflight0,
                u_dut.g_core[0].g_worker_2ctx.u_worker.mag_inflight1,
                u_dut.g_core[0].g_worker_2ctx.u_worker.zrzi_inflight0,
                u_dut.g_core[0].g_worker_2ctx.u_worker.zrzi_inflight1,
                u_dut.g_core[0].g_worker_2ctx.u_worker.c_active[0],
                u_dut.g_core[0].g_worker_2ctx.u_worker.c_state[0],
                u_dut.g_core[0].g_worker_2ctx.u_worker.c_result_valid[0],
                u_dut.g_core[0].g_worker_2ctx.u_worker.c_mag_done[0],
                u_dut.g_core[0].g_worker_2ctx.u_worker.c_zrzi_done[0],
                u_dut.g_core[0].g_worker_2ctx.u_worker.c_active[1],
                u_dut.g_core[0].g_worker_2ctx.u_worker.c_state[1],
                u_dut.g_core[0].g_worker_2ctx.u_worker.c_result_valid[1],
                u_dut.g_core[0].g_worker_2ctx.u_worker.c_mag_done[1],
                u_dut.g_core[0].g_worker_2ctx.u_worker.c_zrzi_done[1],
                u_dut.g_core[0].g_worker_2ctx.u_worker.add_op_pipe[0],
                u_dut.g_core[0].g_worker_2ctx.u_worker.mul_op_pipe[0]);
            $finish;
        end

        $display("=== DYNAMIC 2CTX STRESS PASS: %0d pixels cycles=%0d ===", pix, cycles);
        $finish;
    end

endmodule
