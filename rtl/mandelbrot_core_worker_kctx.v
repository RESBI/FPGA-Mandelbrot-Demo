`timescale 1ns / 1ps
`include "fp_defines.vh"

module mandelbrot_core_worker_kctx #(
    parameter CONTEXTS = 4
) (
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

    function integer clog2;
        input integer value;
        integer v;
        begin
            v = value - 1;
            clog2 = 0;
            while (v > 0) begin
                clog2 = clog2 + 1;
                v = v >> 1;
            end
            if (clog2 == 0)
                clog2 = 1;
        end
    endfunction

    localparam CTX_W = clog2(CONTEXTS);

    localparam MUL_LAT = 6;
    localparam ADD_LAT = 9;

    localparam S_IDLE                 = 5'd0;
    localparam S_INIT_LATCH           = 5'd1;
    localparam S_INIT_START           = 5'd2;
    localparam S_INIT_W_CAPTURE       = 5'd3;
    localparam S_INIT_W2_CAPTURE      = 5'd4;
    localparam S_INIT_H_CAPTURE       = 5'd5;
    localparam S_INIT_H2_CAPTURE      = 5'd6;
    localparam S_INIT_ROWSTEP_MUL     = 5'd7;
    localparam S_INIT_ROWSTART_MUL    = 5'd8;
    localparam S_DONE                 = 5'd10;
    localparam S_RUN                  = 5'd9;

    localparam C_IDLE                 = 4'd0;
    localparam C_NEED_ZRSQ            = 4'd1;
    localparam C_NEED_ZISQ            = 4'd2;
    localparam C_WAIT_MAG_ZRZI        = 4'd4;
    localparam C_NEED_SUB_RE          = 4'd5;
    localparam C_NEED_NEXT_RE         = 4'd6;
    localparam C_NEED_2X              = 4'd7;
    localparam C_NEED_NEXT_IM         = 4'd8;
    localparam C_DONE                 = 4'd9;
    localparam C_CHECK_ITER           = 4'd10;

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
    reg [`FP_WIDTH-1:0] half_w_fp, half_h_fp, row_start_fp, row_stride_fp;
    reg [15:0] max_iter, rows, cols;
    reg [15:0] row_start, row_stride;
    reg [15:0] half_w;
    reg [15:0] launch_col;
    reg [15:0] commit_col;
    reg        c_re_add_pending;
    reg        c_re_issue_pending;
    reg        launch_add_used;

    reg [3:0]  c_state [0:CONTEXTS-1];
    reg        c_active [0:CONTEXTS-1];
    reg [15:0] c_col [0:CONTEXTS-1];
    reg [15:0] c_iter [0:CONTEXTS-1];
    reg [`FP_WIDTH-1:0] c_c_re [0:CONTEXTS-1];
    reg [`FP_WIDTH-1:0] c_c_im [0:CONTEXTS-1];
    reg [`FP_WIDTH-1:0] c_z_re [0:CONTEXTS-1];
    reg [`FP_WIDTH-1:0] c_z_im [0:CONTEXTS-1];
    reg [`FP_WIDTH-1:0] c_z_re_sq [0:CONTEXTS-1];
    reg [`FP_WIDTH-1:0] c_z_im_sq [0:CONTEXTS-1];
    reg [`FP_WIDTH-1:0] c_z_re_z_im [0:CONTEXTS-1];
    reg [`FP_WIDTH-1:0] c_tmp_re [0:CONTEXTS-1];
    reg [`FP_WIDTH-1:0] c_next_re [0:CONTEXTS-1];
    reg [`FP_WIDTH-1:0] c_tmp_2x [0:CONTEXTS-1];
    reg        c_mag_done [0:CONTEXTS-1];
    reg        c_zrzi_done [0:CONTEXTS-1];
    reg        c_mag_issued [0:CONTEXTS-1];
    reg        c_zrzi_issued [0:CONTEXTS-1];
    reg        c_mul_ready [0:CONTEXTS-1];
    reg [2:0]  c_mul_op_ready [0:CONTEXTS-1];
    reg        c_add_ready [0:CONTEXTS-1];
    reg [3:0]  c_add_op_ready [0:CONTEXTS-1];
    reg [`FP_WIDTH-1:0] c_add_a_ready [0:CONTEXTS-1];
    reg [`FP_WIDTH-1:0] c_add_b_ready [0:CONTEXTS-1];
    reg        c_add_neg_ready [0:CONTEXTS-1];
    reg        c_escape [0:CONTEXTS-1];
    reg        c_result_valid [0:CONTEXTS-1];
    reg [15:0] c_result_iter [0:CONTEXTS-1];

    reg [`FP_WIDTH-1:0] mul_a, mul_b;
    reg [`FP_WIDTH-1:0] add_a, add_b;
    reg                 add_neg;
    reg                 mul_req_valid;
    reg [2:0]           mul_req_op;
    reg [CTX_W-1:0]     mul_req_ctx;
    reg                 add_req_valid;
    reg [3:0]           add_req_op;
    reg [CTX_W-1:0]     add_req_ctx;

    wire [`FP_WIDTH-1:0] mul_result;
    wire [`FP_WIDTH-1:0] add_result;
    wire [`FP_WIDTH-1:0] add_b_eff = add_neg ? {~add_b[`FP_SIGN_IDX], add_b[`FP_EXP_HI:0]} : add_b;

    fp_mul u_mul (.clk(clk), .rst(rst), .ce(ce), .a(mul_a), .b(mul_b), .product(mul_result));
    fp_add u_add (.clk(clk), .rst(rst), .ce(ce), .a(add_a), .b(add_b_eff), .sum(add_result));

    reg [2:0]         mul_op_pipe [0:MUL_LAT-1];
    reg [CTX_W-1:0]   mul_ctx_pipe [0:MUL_LAT-1];
    reg [3:0]         add_op_pipe [0:ADD_LAT-1];
    reg [CTX_W-1:0]   add_ctx_pipe [0:ADD_LAT-1];

    wire [2:0]       mul_done_op = mul_op_pipe[MUL_LAT-1];
    wire [CTX_W-1:0] mul_done_ctx = mul_ctx_pipe[MUL_LAT-1];
    wire [3:0]       add_done_op = add_op_pipe[ADD_LAT-1];
    wire [CTX_W-1:0] add_done_ctx = add_ctx_pipe[ADD_LAT-1];

    integer i;
    integer j;
    integer launch_idx;
    integer commit_idx;
    integer active_count;
    integer mul_issued;
    integer add_issued;
    reg [CTX_W-1:0] issue_base;

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
            launch_col <= 0;
            commit_col <= 0;
            c_re_add_pending <= 0;
            c_re_issue_pending <= 0;
            mul_req_valid <= 0;
            mul_req_op <= MOP_NONE;
            mul_req_ctx <= 0;
            add_req_valid <= 0;
            add_req_op <= AOP_NONE;
            add_req_ctx <= 0;
            for (i = 0; i < MUL_LAT; i = i + 1) begin
                mul_op_pipe[i] <= MOP_NONE;
                mul_ctx_pipe[i] <= 0;
            end
            for (i = 0; i < ADD_LAT; i = i + 1) begin
                add_op_pipe[i] <= AOP_NONE;
                add_ctx_pipe[i] <= 0;
            end
            for (i = 0; i < CONTEXTS; i = i + 1) begin
                c_state[i] <= C_IDLE;
                c_active[i] <= 0;
                c_result_valid[i] <= 0;
                c_mul_ready[i] <= 0;
                c_add_ready[i] <= 0;
                c_z_re[i] <= 0;
                c_z_im[i] <= 0;
            end
        end else if (ce) begin
            fifo_wr <= 0;
            launch_add_used = 1'b0;
            mul_a <= {`FP_WIDTH{1'b0}};
            mul_b <= {`FP_WIDTH{1'b0}};
            add_a <= {`FP_WIDTH{1'b0}};
            add_b <= {`FP_WIDTH{1'b0}};
            add_neg <= 1'b0;

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

            if (mul_req_valid && mul_op_pipe[0] == MOP_NONE) begin
                case (mul_req_op)
                    MOP_ZRSQ: begin
                        mul_a <= c_z_re[mul_req_ctx];
                        mul_b <= c_z_re[mul_req_ctx];
                    end
                    MOP_ZISQ: begin
                        mul_a <= c_z_im[mul_req_ctx];
                        mul_b <= c_z_im[mul_req_ctx];
                    end
                    MOP_ZRZI: begin
                        mul_a <= c_z_re[mul_req_ctx];
                        mul_b <= c_z_im[mul_req_ctx];
                    end
                    default: begin end
                endcase
                mul_op_pipe[0] <= mul_req_op;
                mul_ctx_pipe[0] <= mul_req_ctx;
                mul_req_valid <= 0;
            end

            if (add_req_valid && add_op_pipe[0] == AOP_NONE) begin
                add_a <= c_add_a_ready[add_req_ctx];
                add_b <= c_add_b_ready[add_req_ctx];
                add_neg <= c_add_neg_ready[add_req_ctx];
                add_op_pipe[0] <= add_req_op;
                add_ctx_pipe[0] <= add_req_ctx;
                add_req_valid <= 0;
            end

            if (mul_done_op != MOP_NONE) begin
                case (mul_done_op)
                    MOP_ZRSQ: begin
                        c_z_re_sq[mul_done_ctx] <= mul_result;
                        c_mul_op_ready[mul_done_ctx] <= MOP_ZISQ;
                        c_mul_ready[mul_done_ctx] <= 1;
                        c_state[mul_done_ctx] <= C_NEED_ZISQ;
                    end
                    MOP_ZISQ: begin
                        c_z_im_sq[mul_done_ctx] <= mul_result;
                        c_mag_done[mul_done_ctx] <= 0;
                        c_zrzi_done[mul_done_ctx] <= 0;
                        c_mag_issued[mul_done_ctx] <= 0;
                        c_zrzi_issued[mul_done_ctx] <= 0;
                        c_mul_op_ready[mul_done_ctx] <= MOP_ZRZI;
                        c_mul_ready[mul_done_ctx] <= 1;
                        c_add_a_ready[mul_done_ctx] <= c_z_re_sq[mul_done_ctx];
                        c_add_b_ready[mul_done_ctx] <= mul_result;
                        c_add_neg_ready[mul_done_ctx] <= 0;
                        c_add_op_ready[mul_done_ctx] <= AOP_MAG;
                        c_add_ready[mul_done_ctx] <= 1;
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
                        mul_a <= row_start_fp;
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

            if (state == S_RUN) begin
                for (i = 0; i < CONTEXTS; i = i + 1) begin
                    if (c_active[i] && c_state[i] == C_CHECK_ITER) begin
                        if (c_iter[i] >= max_iter) begin
                            c_result_iter[i] <= c_iter[i];
                            c_result_valid[i] <= 1;
                            c_state[i] <= C_DONE;
                        end else begin
                            c_mul_op_ready[i] <= MOP_ZRSQ;
                            c_mul_ready[i] <= 1;
                            c_state[i] <= C_NEED_ZRSQ;
                        end
                    end
                    if (c_active[i] && c_state[i] == C_WAIT_MAG_ZRZI && c_mag_done[i] && c_zrzi_done[i]) begin
                        if (c_escape[i]) begin
                            c_result_iter[i] <= c_iter[i];
                            c_result_valid[i] <= 1;
                            c_state[i] <= C_DONE;
                        end else begin
                            c_mag_issued[i] <= 0;
                            c_zrzi_issued[i] <= 0;
                            c_mul_op_ready[i] <= MOP_ZRZI;
                            c_mul_ready[i] <= 1;
                            c_add_a_ready[i] <= c_z_re_sq[i];
                            c_add_b_ready[i] <= c_z_im_sq[i];
                            c_add_neg_ready[i] <= 1;
                            c_add_op_ready[i] <= AOP_SUB_RE;
                            c_add_ready[i] <= 1;
                            c_state[i] <= C_NEED_SUB_RE;
                        end
                    end
                end
            end

            if (add_done_op != AOP_NONE) begin
                case (add_done_op)
                    AOP_MAG: begin
                        c_mag_done[add_done_ctx] <= 1;
                        c_escape[add_done_ctx] <= quick_esc(c_z_re_sq[add_done_ctx]) || quick_esc(c_z_im_sq[add_done_ctx]) || quick_esc(add_result);
                    end
                    AOP_SUB_RE: begin
                        c_tmp_re[add_done_ctx] <= add_result;
                        c_add_a_ready[add_done_ctx] <= add_result;
                        c_add_b_ready[add_done_ctx] <= c_c_re[add_done_ctx];
                        c_add_neg_ready[add_done_ctx] <= 0;
                        c_add_op_ready[add_done_ctx] <= AOP_NEXT_RE;
                        c_add_ready[add_done_ctx] <= 1;
                        c_state[add_done_ctx] <= C_NEED_NEXT_RE;
                    end
                    AOP_NEXT_RE: begin
                        c_next_re[add_done_ctx] <= add_result;
                        c_add_a_ready[add_done_ctx] <= c_z_re_z_im[add_done_ctx];
                        c_add_b_ready[add_done_ctx] <= c_z_re_z_im[add_done_ctx];
                        c_add_neg_ready[add_done_ctx] <= 0;
                        c_add_op_ready[add_done_ctx] <= AOP_2X;
                        c_add_ready[add_done_ctx] <= 1;
                        c_state[add_done_ctx] <= C_NEED_2X;
                    end
                    AOP_2X: begin
                        c_tmp_2x[add_done_ctx] <= add_result;
                        c_add_a_ready[add_done_ctx] <= add_result;
                        c_add_b_ready[add_done_ctx] <= c_c_im[add_done_ctx];
                        c_add_neg_ready[add_done_ctx] <= 0;
                        c_add_op_ready[add_done_ctx] <= AOP_NEXT_IM;
                        c_add_ready[add_done_ctx] <= 1;
                        c_state[add_done_ctx] <= C_NEED_NEXT_IM;
                    end
                    AOP_NEXT_IM: begin
                        c_z_re[add_done_ctx] <= c_next_re[add_done_ctx];
                        c_z_im[add_done_ctx] <= add_result;
                        c_iter[add_done_ctx] <= c_iter[add_done_ctx] + 1'b1;
                        c_state[add_done_ctx] <= C_CHECK_ITER;
                    end
                    AOP_C_RE_NEXT: begin
                        c_re_next <= add_result;
                        c_re_add_pending <= 0;
                        c_re_issue_pending <= 0;
                    end
                    AOP_INIT_W_SUB: begin
                        c_re_start <= add_result;
                        half_w <= (rows - 16'd1) >> 1;
                        mul_a <= half_h_fp;
                        mul_b <= step_val;
                        mul_op_pipe[0] <= MOP_INIT_H;
                    end
                    AOP_INIT_H_ADD: begin
                        c_im_top <= add_result;
                        mul_a <= row_stride_fp;
                        mul_b <= step_val;
                        mul_op_pipe[0] <= MOP_INIT_ROWSTEP;
                    end
                    AOP_INIT_ROWSTART_SUB: begin
                        row_c_im <= add_result;
                        c_re_next <= c_re_start;
                        launch_col <= 0;
                        commit_col <= 0;
                        c_re_add_pending <= 0;
                        c_re_issue_pending <= 0;
                        state <= S_RUN;
                    end
                    default: begin end
                endcase
            end

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
                        busy <= 1;
                        if (row_start_in >= rows_in || rows_in == 0 || cols_in == 0)
                            state <= S_DONE;
                        else
                            state <= S_INIT_LATCH;
                    end
                end

                S_INIT_LATCH: begin
                    half_w <= (cols - 16'd1) >> 1;
                    half_w_fp <= int2fp((cols - 16'd1) >> 1);
                    half_h_fp <= int2fp((rows - 16'd1) >> 1);
                    row_start_fp <= int2fp(row_start);
                    row_stride_fp <= int2fp(row_stride);
                    state <= S_INIT_START;
                end

                S_INIT_START: begin
                    mul_a <= half_w_fp;
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
                    commit_idx = -1;
                    if (!fifo_full) begin
                        for (i = 0; i < CONTEXTS; i = i + 1) begin
                            if (commit_idx < 0 && c_result_valid[i] && c_col[i] == commit_col)
                                commit_idx = i;
                        end
                        if (commit_idx >= 0) begin
                            fifo_data <= c_result_iter[commit_idx];
                            fifo_wr <= 1;
                            c_active[commit_idx] <= 0;
                            c_result_valid[commit_idx] <= 0;
                            c_state[commit_idx] <= C_IDLE;
                            c_z_re[commit_idx] <= 0;
                            c_z_im[commit_idx] <= 0;
                            commit_col <= commit_col + 1'b1;
                        end
                    end

                    active_count = 0;
                    for (i = 0; i < CONTEXTS; i = i + 1) begin
                        if (c_active[i])
                            active_count = active_count + 1;
                    end

                    if (commit_col >= cols && active_count == 0) begin
                        state <= S_DONE;
                    end else begin
                        launch_idx = -1;
                        if (launch_col < cols && !c_re_add_pending) begin
                            for (i = 0; i < CONTEXTS; i = i + 1) begin
                                if (launch_idx < 0 && !c_active[i])
                                    launch_idx = i;
                            end
                            if (launch_idx >= 0) begin
                                c_active[launch_idx] <= 1;
                                c_col[launch_idx] <= launch_col;
                                c_iter[launch_idx] <= 0;
                                c_c_re[launch_idx] <= c_re_next;
                                c_c_im[launch_idx] <= row_c_im;
                                c_mag_done[launch_idx] <= 0;
                                c_zrzi_done[launch_idx] <= 0;
                                c_mag_issued[launch_idx] <= 0;
                                c_zrzi_issued[launch_idx] <= 0;
                                c_mul_op_ready[launch_idx] <= MOP_ZRSQ;
                                c_mul_ready[launch_idx] <= (max_iter != 0);
                                c_add_ready[launch_idx] <= 0;
                                c_escape[launch_idx] <= 0;
                                c_result_valid[launch_idx] <= (max_iter == 0);
                                c_result_iter[launch_idx] <= 0;
                                c_state[launch_idx] <= (max_iter == 0) ? C_DONE : C_NEED_ZRSQ;
                                launch_col <= launch_col + 1'b1;
                                c_re_add_pending <= 1;
                                c_re_issue_pending <= 1;
                            end
                        end

                        if (mul_op_pipe[0] == MOP_NONE && !mul_req_valid) begin
                            mul_issued = 0;
                            issue_base = launch_col[CTX_W-1:0];
                            for (j = 0; j < CONTEXTS; j = j + 1) begin
                                i = (j + issue_base) & (CONTEXTS - 1);
                                if (!mul_issued && c_active[i] && c_mul_ready[i]) begin
                                    if (c_mul_op_ready[i] == MOP_ZRSQ) begin
                                        mul_req_valid <= 1;
                                        mul_req_op <= MOP_ZRSQ;
                                        mul_req_ctx <= i[CTX_W-1:0];
                                        c_mul_ready[i] <= 0;
                                        c_state[i] <= C_IDLE;
                                        mul_issued = 1;
                                    end else if (c_mul_op_ready[i] == MOP_ZISQ) begin
                                        mul_req_valid <= 1;
                                        mul_req_op <= MOP_ZISQ;
                                        mul_req_ctx <= i[CTX_W-1:0];
                                        c_mul_ready[i] <= 0;
                                        c_state[i] <= C_IDLE;
                                        mul_issued = 1;
                                    end else if (c_mul_op_ready[i] == MOP_ZRZI && !c_zrzi_done[i] && !c_zrzi_issued[i]) begin
                                        mul_req_valid <= 1;
                                        mul_req_op <= MOP_ZRZI;
                                        mul_req_ctx <= i[CTX_W-1:0];
                                        c_mul_ready[i] <= 0;
                                        c_zrzi_issued[i] <= 1;
                                        mul_issued = 1;
                                    end
                                end
                            end
                        end

                        if (add_op_pipe[0] == AOP_NONE && !add_req_valid && c_re_issue_pending) begin
                            add_a <= c_re_next;
                            add_b <= step_val;
                            add_neg <= 0;
                            add_op_pipe[0] <= AOP_C_RE_NEXT;
                            c_re_issue_pending <= 0;
                        end else if (add_op_pipe[0] == AOP_NONE && !add_req_valid && !c_re_add_pending && !launch_add_used) begin
                            add_issued = 0;
                            issue_base = launch_col[CTX_W-1:0];
                            for (j = 0; j < CONTEXTS; j = j + 1) begin
                                i = (j + issue_base) & (CONTEXTS - 1);
                                if (!add_issued && c_active[i] && c_add_ready[i]) begin
                                    add_req_valid <= 1;
                                    add_req_op <= c_add_op_ready[i];
                                    add_req_ctx <= i[CTX_W-1:0];
                                    c_add_ready[i] <= 0;
                                    if (c_add_op_ready[i] == AOP_MAG)
                                        c_mag_issued[i] <= 1;
                                    else
                                        c_state[i] <= C_IDLE;
                                    add_issued = 1;
                                end
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

endmodule
