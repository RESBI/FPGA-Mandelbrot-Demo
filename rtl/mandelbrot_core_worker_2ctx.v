`timescale 1ns / 1ps
`include "fp_defines.vh"

module mandelbrot_core_worker_2ctx (
    input  wire                     clk,
    input  wire                     rst,
    input  wire                     ce,
    input  wire                     start,
    output reg                      busy,
    output reg                      done,
    input  wire [`FP_WIDTH-1:0]     center_re_in,
    input  wire [`FP_WIDTH-1:0]     center_im_in,
    input  wire [`FP_WIDTH-1:0]     step_in,
    input  wire [15:0]              max_iter_in,
    input  wire [15:0]              rows_in,
    input  wire [15:0]              cols_in,
    input  wire [15:0]              row_start_in,
    input  wire [15:0]              row_stride_in,

    output reg  [15:0]              fifo_data,
    output reg                      fifo_wr,
    input  wire                     fifo_full
);

    // Tag delay must match the real back-to-back FPU latency, not the old
    // single-context PIPE_WAIT guard time.
    localparam MUL_LAT = 6;
    localparam ADD_LAT = 7;

    localparam S_IDLE                 = 5'd0;
    localparam S_INIT_START           = 5'd1;
    localparam S_INIT_W_CAPTURE       = 5'd2;
    localparam S_INIT_W2_CAPTURE      = 5'd3;
    localparam S_INIT_H_CAPTURE       = 5'd4;
    localparam S_INIT_H2_CAPTURE      = 5'd5;
    localparam S_INIT_ROWSTEP_MUL     = 5'd6;
    localparam S_INIT_ROWSTART_MUL    = 5'd7;
    localparam S_INIT_ROWSTART_SUB    = 5'd8;
    localparam S_RUN                  = 5'd9;
    localparam S_DONE                 = 5'd10;

    localparam C_IDLE                 = 4'd0;
    localparam C_NEED_ZRSQ            = 4'd1;
    localparam C_NEED_ZISQ            = 4'd2;
    localparam C_NEED_MAG_ZRZI        = 4'd3;
    localparam C_WAIT_MAG_ZRZI        = 4'd4;
    localparam C_NEED_SUB_RE          = 4'd5;
    localparam C_NEED_NEXT_RE         = 4'd6;
    localparam C_NEED_2X              = 4'd7;
    localparam C_NEED_NEXT_IM         = 4'd8;
    localparam C_DONE                 = 4'd9;

    localparam MOP_NONE               = 3'd0;
    localparam MOP_ZRSQ               = 3'd1;
    localparam MOP_ZISQ               = 3'd2;
    localparam MOP_ZRZI               = 3'd3;
    localparam MOP_INIT_W             = 3'd4;
    localparam MOP_INIT_H             = 3'd5;
    localparam MOP_INIT_ROWSTEP       = 3'd6;
    localparam MOP_INIT_ROWSTART      = 3'd7;

    localparam AOP_NONE               = 4'd0;
    localparam AOP_MAG                = 4'd1;
    localparam AOP_SUB_RE             = 4'd2;
    localparam AOP_NEXT_RE            = 4'd3;
    localparam AOP_2X                 = 4'd4;
    localparam AOP_NEXT_IM            = 4'd5;
    localparam AOP_C_RE_NEXT          = 4'd6;
    localparam AOP_INIT_W_SUB         = 4'd7;
    localparam AOP_INIT_H_ADD         = 4'd8;
    localparam AOP_INIT_ROWSTART_SUB  = 4'd9;

    reg [4:0] state = S_IDLE;
    reg [3:0] pipe_wait;
    reg       start_latched;

    always @(posedge clk) begin
        if (rst)
            start_latched <= 0;
        else if (start)
            start_latched <= 1;
        else if (ce && state == S_IDLE && start_latched)
            start_latched <= 0;
    end

    reg [`FP_WIDTH-1:0] center_re, center_im, step_val;
    reg [`FP_WIDTH-1:0] c_re_start, c_im_top, row_step, row_c_im;
    reg [`FP_WIDTH-1:0] c_re_next;
    reg [15:0] max_iter, rows, cols;
    reg [15:0] row_start, row_stride;
    reg [15:0] half_w;
    reg [15:0] launch_col;
    reg [15:0] commit_col;
    reg        c_re_add_pending;
    reg        launch_add_used;

    reg [3:0]  c_state [0:1];
    reg        c_active [0:1];
    reg [15:0] c_col [0:1];
    reg [15:0] c_iter [0:1];
    reg [`FP_WIDTH-1:0] c_c_re [0:1];
    reg [`FP_WIDTH-1:0] c_c_im [0:1];
    reg [`FP_WIDTH-1:0] c_z_re [0:1];
    reg [`FP_WIDTH-1:0] c_z_im [0:1];
    reg [`FP_WIDTH-1:0] c_z_re_sq [0:1];
    reg [`FP_WIDTH-1:0] c_z_im_sq [0:1];
    reg [`FP_WIDTH-1:0] c_z_re_z_im [0:1];
    reg [`FP_WIDTH-1:0] c_tmp_re [0:1];
    reg [`FP_WIDTH-1:0] c_next_re [0:1];
    reg [`FP_WIDTH-1:0] c_tmp_2x [0:1];
    reg        c_mag_done [0:1];
    reg        c_zrzi_done [0:1];
    reg        c_mag_issued [0:1];
    reg        c_zrzi_issued [0:1];
    reg        c_escape [0:1];
    reg        c_result_valid [0:1];
    reg [15:0] c_result_iter [0:1];

    reg [`FP_WIDTH-1:0] mul_a, mul_b;
    reg [`FP_WIDTH-1:0] add_a, add_b;
    reg                 add_neg;

    wire [`FP_WIDTH-1:0] mul_result;
    wire [`FP_WIDTH-1:0] add_result;
    wire [`FP_WIDTH-1:0] add_b_eff = add_neg ? {~add_b[`FP_SIGN_IDX], add_b[`FP_EXP_HI:0]} : add_b;

    fp_mul u_mul (.clk(clk), .rst(rst), .ce(ce), .a(mul_a), .b(mul_b), .product(mul_result));
    fp_add u_add (.clk(clk), .rst(rst), .ce(ce), .a(add_a), .b(add_b_eff), .sum(add_result));

    reg [2:0] mul_op_pipe [0:MUL_LAT-1];
    reg       mul_ctx_pipe [0:MUL_LAT-1];
    reg [3:0] add_op_pipe [0:ADD_LAT-1];
    reg       add_ctx_pipe [0:ADD_LAT-1];

    wire [2:0] mul_done_op = mul_op_pipe[MUL_LAT-1];
    wire       mul_done_ctx = mul_ctx_pipe[MUL_LAT-1];
    wire [3:0] add_done_op = add_op_pipe[ADD_LAT-1];
    wire       add_done_ctx = add_ctx_pipe[ADD_LAT-1];

    integer i;
    reg mag_inflight0, mag_inflight1;
    reg zrzi_inflight0, zrzi_inflight1;

    always @(*) begin
        mag_inflight0 = 0;
        mag_inflight1 = 0;
        zrzi_inflight0 = 0;
        zrzi_inflight1 = 0;
        for (i = 0; i < ADD_LAT; i = i + 1) begin
            if (add_op_pipe[i] == AOP_MAG && add_ctx_pipe[i] == 0)
                mag_inflight0 = 1;
            if (add_op_pipe[i] == AOP_MAG && add_ctx_pipe[i] == 1)
                mag_inflight1 = 1;
        end
        for (i = 0; i < MUL_LAT; i = i + 1) begin
            if (mul_op_pipe[i] == MOP_ZRZI && mul_ctx_pipe[i] == 0)
                zrzi_inflight0 = 1;
            if (mul_op_pipe[i] == MOP_ZRZI && mul_ctx_pipe[i] == 1)
                zrzi_inflight1 = 1;
        end
    end

    function quick_esc;
        input [`FP_WIDTH-1:0] val;
        begin
            quick_esc = (val[`FP_EXP_HI:`FP_EXP_LO] > (`FP_BIAS + 2)) ||
                        ((val[`FP_EXP_HI:`FP_EXP_LO] == (`FP_BIAS + 2)) && (val[`FP_MAN_HI:0] != 0));
        end
    endfunction

    function [`FP_WIDTH-1:0] int2fp;
        input [15:0] val;
        reg [3:0] msb;
        reg [15:0] frac_bits;
        reg [`FP_MAN_W-1:0] man_tmp;
        reg [`FP_WIDTH-1:0] fp_tmp;
        begin
            if (val == 0) begin
                int2fp = 0;
            end else begin
                if      (val[15]) msb = 4'd15;
                else if (val[14]) msb = 4'd14;
                else if (val[13]) msb = 4'd13;
                else if (val[12]) msb = 4'd12;
                else if (val[11]) msb = 4'd11;
                else if (val[10]) msb = 4'd10;
                else if (val[9])  msb = 4'd9;
                else if (val[8])  msb = 4'd8;
                else if (val[7])  msb = 4'd7;
                else if (val[6])  msb = 4'd6;
                else if (val[5])  msb = 4'd5;
                else if (val[4])  msb = 4'd4;
                else if (val[3])  msb = 4'd3;
                else if (val[2])  msb = 4'd2;
                else if (val[1])  msb = 4'd1;
                else              msb = 4'd0;
                frac_bits = val ^ (16'd1 << msb);
                man_tmp = frac_bits;
                man_tmp = man_tmp << (`FP_MAN_W - msb);
                fp_tmp = 0;
                fp_tmp[`FP_SIGN_IDX] = 1'b0;
                fp_tmp[`FP_EXP_HI:`FP_EXP_LO] = `FP_BIAS + msb;
                fp_tmp[`FP_MAN_HI:0] = man_tmp;
                int2fp = fp_tmp;
            end
        end
    endfunction

    always @(posedge clk) begin
        if (rst) begin
            state <= S_IDLE;
            busy <= 0;
            done <= 0;
            fifo_wr <= 0;
            launch_add_used = 1'b0;
            pipe_wait <= 0;
            launch_col <= 0;
            commit_col <= 0;
            c_re_add_pending <= 0;
            for (i = 0; i < MUL_LAT; i = i + 1) begin
                mul_op_pipe[i] <= MOP_NONE;
                mul_ctx_pipe[i] <= 0;
            end
            for (i = 0; i < ADD_LAT; i = i + 1) begin
                add_op_pipe[i] <= AOP_NONE;
                add_ctx_pipe[i] <= 0;
            end
            for (i = 0; i < 2; i = i + 1) begin
                c_state[i] <= C_IDLE;
                c_active[i] <= 0;
                c_result_valid[i] <= 0;
            end
        end else if (ce) begin
            fifo_wr <= 0;
            launch_add_used = 1'b0;

            for (i = MUL_LAT-1; i > 0; i = i - 1) begin
                mul_op_pipe[i] <= mul_op_pipe[i-1];
                mul_ctx_pipe[i] <= mul_ctx_pipe[i-1];
            end
            for (i = ADD_LAT-1; i > 0; i = i - 1) begin
                add_op_pipe[i] <= add_op_pipe[i-1];
                add_ctx_pipe[i] <= add_ctx_pipe[i-1];
            end
            mul_op_pipe[0] <= MOP_NONE;
            mul_ctx_pipe[0] <= 0;
            add_op_pipe[0] <= AOP_NONE;
            add_ctx_pipe[0] <= 0;

            if (mul_done_op != MOP_NONE) begin
                case (mul_done_op)
                    MOP_ZRSQ: begin
                        c_z_re_sq[mul_done_ctx] <= mul_result;
                        c_state[mul_done_ctx] <= C_NEED_ZISQ;
                    end
                    MOP_ZISQ: begin
                        c_z_im_sq[mul_done_ctx] <= mul_result;
                        c_mag_done[mul_done_ctx] <= 0;
                        c_zrzi_done[mul_done_ctx] <= 0;
                        c_mag_issued[mul_done_ctx] <= 0;
                        c_zrzi_issued[mul_done_ctx] <= 0;
                        c_state[mul_done_ctx] <= C_WAIT_MAG_ZRZI;
                    end
                    MOP_ZRZI: begin
                        c_z_re_z_im[mul_done_ctx] <= mul_result;
                        c_zrzi_done[mul_done_ctx] <= 1;
                    end
                    MOP_INIT_W: begin
                        add_a <= center_re;
                        add_b <= mul_result;
                        add_neg <= 1;
                        add_op_pipe[0] <= AOP_INIT_W_SUB;
                    end
                    MOP_INIT_H: begin
                        add_a <= center_im;
                        add_b <= mul_result;
                        add_neg <= 0;
                        add_op_pipe[0] <= AOP_INIT_H_ADD;
                    end
                    MOP_INIT_ROWSTEP: begin
                        row_step <= mul_result;
                        mul_a <= int2fp(row_start);
                        mul_b <= step_val;
                        mul_op_pipe[0] <= MOP_INIT_ROWSTART;
                    end
                    MOP_INIT_ROWSTART: begin
                        add_a <= c_im_top;
                        add_b <= mul_result;
                        add_neg <= 1;
                        add_op_pipe[0] <= AOP_INIT_ROWSTART_SUB;
                    end
                    default: begin end
                endcase
            end

            if (add_done_op != AOP_NONE) begin
                case (add_done_op)
                    AOP_MAG: begin
                        c_mag_done[add_done_ctx] <= 1;
                        c_escape[add_done_ctx] <= quick_esc(c_z_re_sq[add_done_ctx]) || quick_esc(c_z_im_sq[add_done_ctx]) || quick_esc(add_result);
                    end
                    AOP_SUB_RE: begin
                        c_tmp_re[add_done_ctx] <= add_result;
                        c_state[add_done_ctx] <= C_NEED_NEXT_RE;
                    end
                    AOP_NEXT_RE: begin
                        c_next_re[add_done_ctx] <= add_result;
                        c_state[add_done_ctx] <= C_NEED_2X;
                    end
                    AOP_2X: begin
                        c_tmp_2x[add_done_ctx] <= add_result;
                        c_state[add_done_ctx] <= C_NEED_NEXT_IM;
                    end
                    AOP_NEXT_IM: begin
                        if (add_done_ctx == 1'b0) begin
                            c_z_re[0] <= c_next_re[0];
                            c_z_im[0] <= add_result;
                            c_iter[0] <= c_iter[0] + 1'b1;
                            if ((c_iter[0] + 1'b1) >= max_iter) begin
                                c_result_iter[0] <= c_iter[0] + 1'b1;
                                c_result_valid[0] <= 1;
                                c_state[0] <= C_DONE;
                            end else begin
                                c_state[0] <= C_NEED_ZRSQ;
                            end
                        end else begin
                            c_z_re[1] <= c_next_re[1];
                            c_z_im[1] <= add_result;
                            c_iter[1] <= c_iter[1] + 1'b1;
                            if ((c_iter[1] + 1'b1) >= max_iter) begin
                                c_result_iter[1] <= c_iter[1] + 1'b1;
                                c_result_valid[1] <= 1;
                                c_state[1] <= C_DONE;
                            end else begin
                                c_state[1] <= C_NEED_ZRSQ;
                            end
                        end
                    end
                    AOP_C_RE_NEXT: begin
                        c_re_next <= add_result;
                        c_re_add_pending <= 0;
                    end
                    AOP_INIT_W_SUB: begin
                        c_re_start <= add_result;
                        half_w <= (rows - 16'd1) >> 1;
                        mul_a <= int2fp((rows - 16'd1) >> 1);
                        mul_b <= step_val;
                        mul_op_pipe[0] <= MOP_INIT_H;
                    end
                    AOP_INIT_H_ADD: begin
                        c_im_top <= add_result;
                        mul_a <= int2fp(row_stride);
                        mul_b <= step_val;
                        mul_op_pipe[0] <= MOP_INIT_ROWSTEP;
                    end
                    AOP_INIT_ROWSTART_SUB: begin
                        row_c_im <= add_result;
                        c_re_next <= c_re_start;
                        launch_col <= 0;
                        commit_col <= 0;
                        c_re_add_pending <= 0;
                        state <= S_RUN;
                    end
                    default: begin end
                endcase
            end

            if (pipe_wait) begin
                pipe_wait <= pipe_wait - 1'b1;
            end else begin
                case (state)
                    S_IDLE: begin
                        done <= 0;
                        if (start_latched) begin
                            center_re <= center_re_in;
                            center_im <= center_im_in;
                            step_val <= step_in;
                            max_iter <= max_iter_in;
                            rows <= rows_in;
                            cols <= cols_in;
                            row_start <= row_start_in;
                            row_stride <= row_stride_in;
                            half_w <= (cols_in - 16'd1) >> 1;
                            busy <= 1;
                            if (row_start_in >= rows_in || rows_in == 0 || cols_in == 0)
                                state <= S_DONE;
                            else
                                state <= S_INIT_START;
                        end
                    end

                    S_INIT_START: begin
                        mul_a <= int2fp(half_w);
                        mul_b <= step_val;
                        mul_op_pipe[0] <= MOP_INIT_W;
                        state <= S_INIT_W_CAPTURE;
                    end

                    S_INIT_W_CAPTURE: begin
                        if (add_done_op == AOP_INIT_W_SUB)
                            state <= S_INIT_W2_CAPTURE;
                    end

                    S_INIT_W2_CAPTURE: begin
                        if (mul_done_op == MOP_INIT_H)
                            state <= S_INIT_H_CAPTURE;
                    end

                    S_INIT_H_CAPTURE: begin
                        if (add_done_op == AOP_INIT_H_ADD)
                            state <= S_INIT_H2_CAPTURE;
                    end

                    S_INIT_H2_CAPTURE: begin
                        if (mul_done_op == MOP_INIT_ROWSTEP)
                            state <= S_INIT_ROWSTEP_MUL;
                    end

                    S_INIT_ROWSTEP_MUL: begin
                        if (mul_done_op == MOP_INIT_ROWSTART)
                            state <= S_INIT_ROWSTART_MUL;
                    end

                    S_INIT_ROWSTART_MUL: begin
                        if (add_done_op == AOP_INIT_ROWSTART_SUB)
                            state <= S_RUN;
                    end

                    S_RUN: begin
                        if (!fifo_full) begin
                            if (c_result_valid[0] && c_col[0] == commit_col) begin
                                fifo_data <= c_result_iter[0];
                                fifo_wr <= 1;
                                c_active[0] <= 0;
                                c_result_valid[0] <= 0;
                                c_state[0] <= C_IDLE;
                                commit_col <= commit_col + 1'b1;
                            end else if (c_result_valid[1] && c_col[1] == commit_col) begin
                                fifo_data <= c_result_iter[1];
                                fifo_wr <= 1;
                                c_active[1] <= 0;
                                c_result_valid[1] <= 0;
                                c_state[1] <= C_IDLE;
                                commit_col <= commit_col + 1'b1;
                            end
                        end

                        if (commit_col >= cols && !c_active[0] && !c_active[1]) begin
                            state <= S_DONE;
                        end else begin
                            if (launch_col < cols && !c_re_add_pending) begin
                                if (!c_active[0]) begin
                                    c_active[0] <= 1;
                                    c_col[0] <= launch_col;
                                    c_iter[0] <= 0;
                                    c_c_re[0] <= c_re_next;
                                    c_c_im[0] <= row_c_im;
                                    c_z_re[0] <= 0;
                                    c_z_im[0] <= 0;
                                    c_mag_done[0] <= 0;
                                    c_zrzi_done[0] <= 0;
                                    c_mag_issued[0] <= 0;
                                    c_zrzi_issued[0] <= 0;
                                    c_escape[0] <= 0;
                                    c_result_valid[0] <= (max_iter == 0);
                                    c_result_iter[0] <= 0;
                                    c_state[0] <= (max_iter == 0) ? C_DONE : C_NEED_ZRSQ;
                                    launch_col <= launch_col + 1'b1;
                                    add_a <= c_re_next;
                                    add_b <= step_val;
                                    add_neg <= 0;
                                    add_op_pipe[0] <= AOP_C_RE_NEXT;
                                    c_re_add_pending <= 1;
                                    launch_add_used = 1'b1;
                                end else if (!c_active[1]) begin
                                    c_active[1] <= 1;
                                    c_col[1] <= launch_col;
                                    c_iter[1] <= 0;
                                    c_c_re[1] <= c_re_next;
                                    c_c_im[1] <= row_c_im;
                                    c_z_re[1] <= 0;
                                    c_z_im[1] <= 0;
                                    c_mag_done[1] <= 0;
                                    c_zrzi_done[1] <= 0;
                                    c_mag_issued[1] <= 0;
                                    c_zrzi_issued[1] <= 0;
                                    c_escape[1] <= 0;
                                    c_result_valid[1] <= (max_iter == 0);
                                    c_result_iter[1] <= 0;
                                    c_state[1] <= (max_iter == 0) ? C_DONE : C_NEED_ZRSQ;
                                    launch_col <= launch_col + 1'b1;
                                    add_a <= c_re_next;
                                    add_b <= step_val;
                                    add_neg <= 0;
                                    add_op_pipe[0] <= AOP_C_RE_NEXT;
                                    c_re_add_pending <= 1;
                                    launch_add_used = 1'b1;
                                end
                            end

                            if (mul_op_pipe[0] == MOP_NONE) begin
                                if (c_active[0] && c_state[0] == C_NEED_ZRSQ) begin
                                    mul_a <= c_z_re[0];
                                    mul_b <= c_z_re[0];
                                    mul_op_pipe[0] <= MOP_ZRSQ;
                                    mul_ctx_pipe[0] <= 0;
                                    c_state[0] <= C_IDLE;
                                end else if (c_active[1] && c_state[1] == C_NEED_ZRSQ) begin
                                    mul_a <= c_z_re[1];
                                    mul_b <= c_z_re[1];
                                    mul_op_pipe[0] <= MOP_ZRSQ;
                                    mul_ctx_pipe[0] <= 1;
                                    c_state[1] <= C_IDLE;
                                end else if (c_active[0] && c_state[0] == C_NEED_ZISQ) begin
                                    mul_a <= c_z_im[0];
                                    mul_b <= c_z_im[0];
                                    mul_op_pipe[0] <= MOP_ZISQ;
                                    mul_ctx_pipe[0] <= 0;
                                    c_state[0] <= C_IDLE;
                                end else if (c_active[1] && c_state[1] == C_NEED_ZISQ) begin
                                    mul_a <= c_z_im[1];
                                    mul_b <= c_z_im[1];
                                    mul_op_pipe[0] <= MOP_ZISQ;
                                    mul_ctx_pipe[0] <= 1;
                                    c_state[1] <= C_IDLE;
                                end else if (c_active[0] && c_state[0] == C_WAIT_MAG_ZRZI && !c_zrzi_done[0] && !zrzi_inflight0) begin
                                    mul_a <= c_z_re[0];
                                    mul_b <= c_z_im[0];
                                    mul_op_pipe[0] <= MOP_ZRZI;
                                    mul_ctx_pipe[0] <= 0;
                                end else if (c_active[1] && c_state[1] == C_WAIT_MAG_ZRZI && !c_zrzi_done[1] && !zrzi_inflight1) begin
                                    mul_a <= c_z_re[1];
                                    mul_b <= c_z_im[1];
                                    mul_op_pipe[0] <= MOP_ZRZI;
                                    mul_ctx_pipe[0] <= 1;
                                end
                            end

                            if (add_op_pipe[0] == AOP_NONE && !c_re_add_pending && !launch_add_used) begin
                                if (c_active[0] && c_state[0] == C_WAIT_MAG_ZRZI && !c_mag_done[0] && !mag_inflight0) begin
                                    add_a <= c_z_re_sq[0];
                                    add_b <= c_z_im_sq[0];
                                    add_neg <= 0;
                                    add_op_pipe[0] <= AOP_MAG;
                                    add_ctx_pipe[0] <= 0;
                                end else if (c_active[1] && c_state[1] == C_WAIT_MAG_ZRZI && !c_mag_done[1] && !mag_inflight1) begin
                                    add_a <= c_z_re_sq[1];
                                    add_b <= c_z_im_sq[1];
                                    add_neg <= 0;
                                    add_op_pipe[0] <= AOP_MAG;
                                    add_ctx_pipe[0] <= 1;
                                end else if (c_active[0] && c_state[0] == C_NEED_SUB_RE) begin
                                    add_a <= c_z_re_sq[0];
                                    add_b <= c_z_im_sq[0];
                                    add_neg <= 1;
                                    add_op_pipe[0] <= AOP_SUB_RE;
                                    add_ctx_pipe[0] <= 0;
                                    c_state[0] <= C_IDLE;
                                end else if (c_active[1] && c_state[1] == C_NEED_SUB_RE) begin
                                    add_a <= c_z_re_sq[1];
                                    add_b <= c_z_im_sq[1];
                                    add_neg <= 1;
                                    add_op_pipe[0] <= AOP_SUB_RE;
                                    add_ctx_pipe[0] <= 1;
                                    c_state[1] <= C_IDLE;
                                end else if (c_active[0] && c_state[0] == C_NEED_NEXT_RE) begin
                                    add_a <= c_tmp_re[0];
                                    add_b <= c_c_re[0];
                                    add_neg <= 0;
                                    add_op_pipe[0] <= AOP_NEXT_RE;
                                    add_ctx_pipe[0] <= 0;
                                    c_state[0] <= C_IDLE;
                                end else if (c_active[1] && c_state[1] == C_NEED_NEXT_RE) begin
                                    add_a <= c_tmp_re[1];
                                    add_b <= c_c_re[1];
                                    add_neg <= 0;
                                    add_op_pipe[0] <= AOP_NEXT_RE;
                                    add_ctx_pipe[0] <= 1;
                                    c_state[1] <= C_IDLE;
                                end else if (c_active[0] && c_state[0] == C_NEED_2X) begin
                                    add_a <= c_z_re_z_im[0];
                                    add_b <= c_z_re_z_im[0];
                                    add_neg <= 0;
                                    add_op_pipe[0] <= AOP_2X;
                                    add_ctx_pipe[0] <= 0;
                                    c_state[0] <= C_IDLE;
                                end else if (c_active[1] && c_state[1] == C_NEED_2X) begin
                                    add_a <= c_z_re_z_im[1];
                                    add_b <= c_z_re_z_im[1];
                                    add_neg <= 0;
                                    add_op_pipe[0] <= AOP_2X;
                                    add_ctx_pipe[0] <= 1;
                                    c_state[1] <= C_IDLE;
                                end else if (c_active[0] && c_state[0] == C_NEED_NEXT_IM) begin
                                    add_a <= c_tmp_2x[0];
                                    add_b <= c_c_im[0];
                                    add_neg <= 0;
                                    add_op_pipe[0] <= AOP_NEXT_IM;
                                    add_ctx_pipe[0] <= 0;
                                    c_state[0] <= C_IDLE;
                                end else if (c_active[1] && c_state[1] == C_NEED_NEXT_IM) begin
                                    add_a <= c_tmp_2x[1];
                                    add_b <= c_c_im[1];
                                    add_neg <= 0;
                                    add_op_pipe[0] <= AOP_NEXT_IM;
                                    add_ctx_pipe[0] <= 1;
                                    c_state[1] <= C_IDLE;
                                end
                            end

                            if (c_active[0] && c_state[0] == C_WAIT_MAG_ZRZI && c_mag_done[0] && c_zrzi_done[0]) begin
                                if (c_escape[0]) begin
                                    c_result_iter[0] <= c_iter[0];
                                    c_result_valid[0] <= 1;
                                    c_state[0] <= C_DONE;
                                end else begin
                                    c_mag_issued[0] <= 0;
                                    c_zrzi_issued[0] <= 0;
                                    c_state[0] <= C_NEED_SUB_RE;
                                end
                            end
                            if (c_active[1] && c_state[1] == C_WAIT_MAG_ZRZI && c_mag_done[1] && c_zrzi_done[1]) begin
                                if (c_escape[1]) begin
                                    c_result_iter[1] <= c_iter[1];
                                    c_result_valid[1] <= 1;
                                    c_state[1] <= C_DONE;
                                end else begin
                                    c_mag_issued[1] <= 0;
                                    c_zrzi_issued[1] <= 0;
                                    c_state[1] <= C_NEED_SUB_RE;
                                end
                            end
                        end
                    end

                    S_DONE: begin
                        busy <= 0;
                        done <= 1;
                        state <= S_IDLE;
                    end

                    default: state <= S_IDLE;
                endcase
            end
        end
    end

endmodule
