`timescale 1ns / 1ps
`include "fx_defines.vh"

module mandelbrot_core_worker_fx #(
    parameter CONTEXTS = 4
) (
    input  wire                     clk,
    input  wire                     rst,
    input  wire                     ce,
    input  wire                     start,
    output reg                      busy,
    output reg                      done,
    input  wire [`FX_W-1:0]         center_re_in,
    input  wire [`FX_W-1:0]         center_im_in,
    input  wire [`FX_W-1:0]         step_in,
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
        begin v = value - 1; clog2 = 0;
            while (v > 0) begin clog2 = clog2 + 1; v = v >> 1; end
            if (clog2 == 0) clog2 = 1;
        end
    endfunction

    localparam CTX_W   = clog2(CONTEXTS);
    localparam MUL_LAT = 4;
    localparam ADD_LAT = 2;

    localparam S_IDLE       = 4'd0;
    localparam S_INIT       = 4'd1;
    localparam S_RUN        = 4'd2;
    localparam S_DONE       = 4'd3;

    localparam C_IDLE       = 4'd0;
    localparam C_NEED_ZRSQ  = 4'd1;
    localparam C_NEED_ZISQ  = 4'd2;
    localparam C_WAIT_MAG   = 4'd3;
    localparam C_NEED_SRE   = 4'd4;
    localparam C_NEED_NRE   = 4'd5;
    localparam C_NEED_2X    = 4'd6;
    localparam C_NEED_NIM   = 4'd7;
    localparam C_CHECK      = 4'd8;
    localparam C_DONE       = 4'd9;

    localparam MOP_NONE     = 3'd0;
    localparam MOP_ZRSQ     = 3'd1;
    localparam MOP_ZISQ     = 3'd2;
    localparam MOP_ZRZI     = 3'd3;

    localparam AOP_NONE     = 4'd0;
    localparam AOP_MAG      = 4'd1;
    localparam AOP_SRE      = 4'd2;
    localparam AOP_NRE      = 4'd3;
    localparam AOP_2X       = 4'd4;
    localparam AOP_NIM      = 4'd5;
    localparam AOP_CREN     = 4'd6;

    reg [3:0] state = S_IDLE;
    reg       start_latched;

    always @(posedge clk) begin
        if (rst) start_latched <= 0;
        else if (start) start_latched <= 1;
        else if (ce && state == S_IDLE && start_latched) start_latched <= 0;
    end

    reg signed [`FX_W-1:0] center_re, center_im, step_val;
    reg signed [`FX_W-1:0] c_re_start, row_c_im, c_re_next;
    reg [15:0] max_iter, rows, cols, row_start, row_stride;
    reg [15:0] half_w, half_h;
    reg [15:0] launch_col, commit_col;
    reg        c_re_add_pending, c_re_issue_pending;

    reg [3:0]  c_state   [0:CONTEXTS-1];
    reg        c_active  [0:CONTEXTS-1];
    reg [15:0] c_col     [0:CONTEXTS-1];
    reg [15:0] c_iter    [0:CONTEXTS-1];
    reg signed [`FX_W-1:0] c_c_re   [0:CONTEXTS-1];
    reg signed [`FX_W-1:0] c_c_im   [0:CONTEXTS-1];
    reg signed [`FX_W-1:0] c_z_re   [0:CONTEXTS-1];
    reg signed [`FX_W-1:0] c_z_im   [0:CONTEXTS-1];
    reg signed [`FX_W-1:0] c_zr_sq  [0:CONTEXTS-1];
    reg signed [`FX_W-1:0] c_zi_sq  [0:CONTEXTS-1];
    reg signed [`FX_W-1:0] c_zrzi   [0:CONTEXTS-1];
    reg signed [`FX_W-1:0] c_nre    [0:CONTEXTS-1];
    reg        c_mag_done [0:CONTEXTS-1];
    reg        c_zrzi_done[0:CONTEXTS-1];
    reg        c_mag_iss  [0:CONTEXTS-1];
    reg        c_zrzi_iss [0:CONTEXTS-1];
    reg        c_mul_rdy  [0:CONTEXTS-1];
    reg [2:0]  c_mul_op   [0:CONTEXTS-1];
    reg        c_add_rdy  [0:CONTEXTS-1];
    reg [3:0]  c_add_op   [0:CONTEXTS-1];
    reg signed [`FX_W-1:0] c_add_a  [0:CONTEXTS-1];
    reg signed [`FX_W-1:0] c_add_b  [0:CONTEXTS-1];
    reg        c_escape   [0:CONTEXTS-1];
    reg        c_res_v    [0:CONTEXTS-1];
    reg [15:0] c_res_iter [0:CONTEXTS-1];

    reg signed [`FX_W-1:0] mul_a, mul_b;
    reg signed [`FX_W-1:0] add_a, add_b;
    reg        mul_req_v;
    reg [2:0]  mul_req_op;
    reg [CTX_W-1:0] mul_req_cx;
    reg        add_req_v;
    reg [3:0]  add_req_op;
    reg [CTX_W-1:0] add_req_cx;

    wire signed [`FX_W-1:0] mul_result;
    wire signed [`FX_W-1:0] add_result;

    fx_mul u_mul (.clk(clk), .rst(rst), .ce(ce), .a(mul_a), .b(mul_b), .product(mul_result));
    fx_add u_add (.clk(clk), .rst(rst), .ce(ce), .a(add_a), .b(add_b), .sum(add_result));

    reg [15:0] imul_int;
    reg signed [`FX_W-1:0] imul_fx;
    wire signed [`FX_W-1:0] imul_result;
    fx_mul_int u_imul (.clk(clk), .rst(rst), .ce(ce), .a(imul_int), .b(imul_fx), .product(imul_result));

    reg signed [`FX_W-1:0] iadd_a, iadd_b;
    reg signed [`FX_W-1:0] iadd_result;
    always @(posedge clk) begin
        if (rst) iadd_result <= 0;
        else if (ce) iadd_result <= iadd_a + iadd_b;
    end

    reg [2:0] mul_op_pipe [0:MUL_LAT-1];
    reg [CTX_W-1:0] mul_ctx_pipe [0:MUL_LAT-1];
    reg [3:0] add_op_pipe [0:ADD_LAT-1];
    reg [CTX_W-1:0] add_ctx_pipe [0:ADD_LAT-1];

    wire [2:0]       mul_done_op  = mul_op_pipe[MUL_LAT-1];
    wire [CTX_W-1:0] mul_done_cx  = mul_ctx_pipe[MUL_LAT-1];
    wire [3:0]       add_done_op  = add_op_pipe[ADD_LAT-1];
    wire [CTX_W-1:0] add_done_cx  = add_ctx_pipe[ADD_LAT-1];

    wire signed [`FX_W-1:0] four_fx = $signed(64'sd4 <<< `FX_FRAC);

    reg [3:0] init_step;
    reg [3:0] init_wait;

    integer i, j, launch_idx, commit_idx, active_count;
    integer mul_iss, add_iss;
    reg [CTX_W-1:0] issue_base;

    always @(posedge clk) begin
        if (rst) begin
            state <= S_IDLE; busy <= 0; done <= 0; fifo_wr <= 0;
            launch_col <= 0; commit_col <= 0;
            c_re_add_pending <= 0; c_re_issue_pending <= 0;
            mul_req_v <= 0; mul_req_op <= MOP_NONE; mul_req_cx <= 0;
            add_req_v <= 0; add_req_op <= AOP_NONE; add_req_cx <= 0;
            imul_int <= 0; imul_fx <= 0; iadd_a <= 0; iadd_b <= 0;
            init_step <= 0; init_wait <= 0;
            for (i = 0; i < MUL_LAT; i = i + 1) begin
                mul_op_pipe[i] <= MOP_NONE; mul_ctx_pipe[i] <= 0;
            end
            for (i = 0; i < ADD_LAT; i = i + 1) begin
                add_op_pipe[i] <= AOP_NONE; add_ctx_pipe[i] <= 0;
            end
            for (i = 0; i < CONTEXTS; i = i + 1) begin
                c_state[i] <= C_IDLE; c_active[i] <= 0;
                c_res_v[i] <= 0; c_mul_rdy[i] <= 0; c_add_rdy[i] <= 0;
                c_z_re[i] <= 0; c_z_im[i] <= 0;
            end
        end else if (ce) begin
            fifo_wr <= 0;
            mul_a <= 0; mul_b <= 0; add_a <= 0; add_b <= 0;

            for (i = MUL_LAT-1; i > 0; i = i - 1) begin
                mul_op_pipe[i] <= mul_op_pipe[i-1];
                mul_ctx_pipe[i] <= mul_ctx_pipe[i-1];
            end
            for (i = ADD_LAT-1; i > 0; i = i - 1) begin
                add_op_pipe[i] <= add_op_pipe[i-1];
                add_ctx_pipe[i] <= add_ctx_pipe[i-1];
            end
            mul_op_pipe[0] <= MOP_NONE; mul_ctx_pipe[0] <= 0;
            add_op_pipe[0] <= AOP_NONE; add_ctx_pipe[0] <= 0;

            if (mul_req_v && mul_op_pipe[0] == MOP_NONE) begin
                case (mul_req_op)
                    MOP_ZRSQ: begin mul_a <= c_z_re[mul_req_cx]; mul_b <= c_z_re[mul_req_cx]; end
                    MOP_ZISQ: begin mul_a <= c_z_im[mul_req_cx]; mul_b <= c_z_im[mul_req_cx]; end
                    MOP_ZRZI: begin mul_a <= c_z_re[mul_req_cx]; mul_b <= c_z_im[mul_req_cx]; end
                    default: begin end
                endcase
                mul_op_pipe[0] <= mul_req_op;
                mul_ctx_pipe[0] <= mul_req_cx;
                mul_req_v <= 0;
            end

            if (add_req_v && add_op_pipe[0] == AOP_NONE) begin
                add_a <= c_add_a[add_req_cx];
                add_b <= c_add_b[add_req_cx];
                add_op_pipe[0] <= add_req_op;
                add_ctx_pipe[0] <= add_req_cx;
                add_req_v <= 0;
            end

            if (mul_done_op != MOP_NONE) begin
                case (mul_done_op)
                    MOP_ZRSQ: begin
                        c_zr_sq[mul_done_cx] <= mul_result;
                        c_mul_op[mul_done_cx] <= MOP_ZISQ;
                        c_mul_rdy[mul_done_cx] <= 1;
                        c_state[mul_done_cx] <= C_NEED_ZISQ;
                    end
                    MOP_ZISQ: begin
                        c_zi_sq[mul_done_cx] <= mul_result;
                        c_mag_done[mul_done_cx] <= 0;
                        c_zrzi_done[mul_done_cx] <= 0;
                        c_mag_iss[mul_done_cx] <= 0;
                        c_zrzi_iss[mul_done_cx] <= 0;
                        c_mul_op[mul_done_cx] <= MOP_ZRZI;
                        c_mul_rdy[mul_done_cx] <= 1;
                        c_add_a[mul_done_cx] <= c_zr_sq[mul_done_cx];
                        c_add_b[mul_done_cx] <= mul_result;
                        c_add_op[mul_done_cx] <= AOP_MAG;
                        c_add_rdy[mul_done_cx] <= 1;
                        c_state[mul_done_cx] <= C_WAIT_MAG;
                    end
                    MOP_ZRZI: begin
                        c_zrzi[mul_done_cx] <= mul_result;
                        c_zrzi_done[mul_done_cx] <= 1;
                    end
                    default: begin end
                endcase
            end

            if (state == S_RUN) begin
                for (i = 0; i < CONTEXTS; i = i + 1) begin
                    if (c_active[i] && c_state[i] == C_CHECK) begin
                        if (c_iter[i] >= max_iter) begin
                            c_res_iter[i] <= c_iter[i];
                            c_res_v[i] <= 1;
                            c_state[i] <= C_DONE;
                        end else begin
                            c_mul_op[i] <= MOP_ZRSQ;
                            c_mul_rdy[i] <= 1;
                            c_state[i] <= C_NEED_ZRSQ;
                        end
                    end
                    if (c_active[i] && c_state[i] == C_WAIT_MAG && c_mag_done[i] && c_zrzi_done[i]) begin
                        if (c_escape[i]) begin
                            c_res_iter[i] <= c_iter[i];
                            c_res_v[i] <= 1;
                            c_state[i] <= C_DONE;
                        end else begin
                            c_mag_iss[i] <= 0;
                            c_zrzi_iss[i] <= 0;
                            c_mul_op[i] <= MOP_ZRZI;
                            c_mul_rdy[i] <= 1;
                        c_add_a[i] <= c_zr_sq[i];
                        c_add_b[i] <= -c_zi_sq[i];
                        c_add_op[i] <= AOP_SRE;
                            c_add_rdy[i] <= 1;
                            c_state[i] <= C_NEED_SRE;
                        end
                    end
                end
            end

            if (add_done_op != AOP_NONE) begin
                case (add_done_op)
                    AOP_MAG: begin
                        c_mag_done[add_done_cx] <= 1;
                        c_escape[add_done_cx] <= (add_result > four_fx);
                    end
                    AOP_SRE: begin
                        c_add_a[add_done_cx] <= add_result;
                        c_add_b[add_done_cx] <= c_c_re[add_done_cx];
                        c_add_op[add_done_cx] <= AOP_NRE;
                        c_add_rdy[add_done_cx] <= 1;
                        c_state[add_done_cx] <= C_NEED_NRE;
                    end
                    AOP_NRE: begin
                        c_nre[add_done_cx] <= add_result;
                        c_add_a[add_done_cx] <= c_zrzi[add_done_cx];
                        c_add_b[add_done_cx] <= c_zrzi[add_done_cx];
                        c_add_op[add_done_cx] <= AOP_2X;
                        c_add_rdy[add_done_cx] <= 1;
                        c_state[add_done_cx] <= C_NEED_2X;
                    end
                    AOP_2X: begin
                        c_add_a[add_done_cx] <= add_result;
                        c_add_b[add_done_cx] <= c_c_im[add_done_cx];
                        c_add_op[add_done_cx] <= AOP_NIM;
                        c_add_rdy[add_done_cx] <= 1;
                        c_state[add_done_cx] <= C_NEED_NIM;
                    end
                    AOP_NIM: begin
                        c_z_re[add_done_cx] <= c_nre[add_done_cx];
                        c_z_im[add_done_cx] <= add_result;
                        c_iter[add_done_cx] <= c_iter[add_done_cx] + 1'b1;
                        c_state[add_done_cx] <= C_CHECK;
                    end
                    AOP_CREN: begin
                        c_re_next <= add_result;
                        c_re_add_pending <= 0;
                        c_re_issue_pending <= 0;
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
                        if (row_start_in >= rows_in || rows_in == 0 || cols_in == 0) begin
                            state <= S_DONE;
                        end else begin
                            half_w <= (cols_in - 16'd1) >> 1;
                            half_h <= (rows_in - 16'd1) >> 1;
                            init_step <= 0;
                            init_wait <= 4'd3;
                            imul_int <= (cols_in - 16'd1) >> 1;
                            imul_fx <= step_in;
                            state <= S_INIT;
                        end
                    end
                end

                S_INIT: begin
                    if (init_wait > 0) begin
                        init_wait <= init_wait - 1'b1;
                    end else begin
                        case (init_step)
                            4'd0: begin
                                iadd_a <= center_re;
                                iadd_b <= -imul_result;
                                init_step <= 4'd1;
                                init_wait <= 4'd1;
                            end
                            4'd1: begin
                                c_re_start <= iadd_result;
                                imul_int <= half_h;
                                imul_fx <= step_val;
                                init_step <= 4'd2;
                                init_wait <= 4'd3;
                            end
                            4'd2: begin
                                iadd_a <= center_im;
                                iadd_b <= imul_result;
                                init_step <= 4'd3;
                                init_wait <= 4'd1;
                            end
                            4'd3: begin
                                row_c_im <= iadd_result;
                                imul_int <= row_start;
                                imul_fx <= step_val;
                                init_step <= 4'd4;
                                init_wait <= 4'd3;
                            end
                            4'd4: begin
                                iadd_a <= row_c_im;
                                iadd_b <= -imul_result;
                                init_step <= 4'd5;
                                init_wait <= 4'd1;
                            end
                            4'd5: begin
                                row_c_im <= iadd_result;
                                c_re_next <= c_re_start;
                                launch_col <= 0;
                                commit_col <= 0;
                                c_re_add_pending <= 0;
                                c_re_issue_pending <= 0;
                                state <= S_RUN;
                            end
                            default: state <= S_RUN;
                        endcase
                    end
                end

                S_RUN: begin
                    commit_idx = -1;
                    if (!fifo_full) begin
                        for (i = 0; i < CONTEXTS; i = i + 1) begin
                            if (commit_idx < 0 && c_res_v[i] && c_col[i] == commit_col)
                                commit_idx = i;
                        end
                        if (commit_idx >= 0) begin
                            fifo_data <= c_res_iter[commit_idx];
                            fifo_wr <= 1;
                            c_active[commit_idx] <= 0;
                            c_res_v[commit_idx] <= 0;
                            c_state[commit_idx] <= C_IDLE;
                            c_z_re[commit_idx] <= 0;
                            c_z_im[commit_idx] <= 0;
                            commit_col <= commit_col + 1'b1;
                        end
                    end

                    active_count = 0;
                    for (i = 0; i < CONTEXTS; i = i + 1)
                        if (c_active[i]) active_count = active_count + 1;

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
                                c_mag_iss[launch_idx] <= 0;
                                c_zrzi_iss[launch_idx] <= 0;
                                c_mul_op[launch_idx] <= MOP_ZRSQ;
                                c_mul_rdy[launch_idx] <= (max_iter != 0);
                                c_add_rdy[launch_idx] <= 0;
                                c_escape[launch_idx] <= 0;
                                c_res_v[launch_idx] <= (max_iter == 0);
                                c_res_iter[launch_idx] <= 0;
                                c_state[launch_idx] <= (max_iter == 0) ? C_DONE : C_NEED_ZRSQ;
                                launch_col <= launch_col + 1'b1;
                                c_re_add_pending <= 1;
                                c_re_issue_pending <= 1;
                            end
                        end

                        if (mul_op_pipe[0] == MOP_NONE && !mul_req_v) begin
                            mul_iss = 0;
                            issue_base = launch_col[CTX_W-1:0];
                            for (j = 0; j < CONTEXTS; j = j + 1) begin
                                i = (j + issue_base) & (CONTEXTS - 1);
                                if (!mul_iss && c_active[i] && c_mul_rdy[i]) begin
                                    if (c_mul_op[i] == MOP_ZRSQ) begin
                                        mul_req_v <= 1; mul_req_op <= MOP_ZRSQ;
                                        mul_req_cx <= i[CTX_W-1:0];
                                        c_mul_rdy[i] <= 0; c_state[i] <= C_IDLE;
                                        mul_iss = 1;
                                    end else if (c_mul_op[i] == MOP_ZISQ) begin
                                        mul_req_v <= 1; mul_req_op <= MOP_ZISQ;
                                        mul_req_cx <= i[CTX_W-1:0];
                                        c_mul_rdy[i] <= 0; c_state[i] <= C_IDLE;
                                        mul_iss = 1;
                                    end else if (c_mul_op[i] == MOP_ZRZI && !c_zrzi_done[i] && !c_zrzi_iss[i]) begin
                                        mul_req_v <= 1; mul_req_op <= MOP_ZRZI;
                                        mul_req_cx <= i[CTX_W-1:0];
                                        c_mul_rdy[i] <= 0; c_zrzi_iss[i] <= 1;
                                        mul_iss = 1;
                                    end
                                end
                            end
                        end

                        if (add_op_pipe[0] == AOP_NONE && !add_req_v && c_re_issue_pending) begin
                            add_a <= c_re_next; add_b <= step_val;
                            add_op_pipe[0] <= AOP_CREN;
                            c_re_issue_pending <= 0;
                        end else if (add_op_pipe[0] == AOP_NONE && !add_req_v && !c_re_add_pending) begin
                            add_iss = 0;
                            issue_base = launch_col[CTX_W-1:0];
                            for (j = 0; j < CONTEXTS; j = j + 1) begin
                                i = (j + issue_base) & (CONTEXTS - 1);
                                if (!add_iss && c_active[i] && c_add_rdy[i]) begin
                                    add_req_v <= 1; add_req_op <= c_add_op[i];
                                    add_req_cx <= i[CTX_W-1:0];
                                    c_add_rdy[i] <= 0;
                                    if (c_add_op[i] == AOP_MAG) c_mag_iss[i] <= 1;
                                    else c_state[i] <= C_IDLE;
                                    add_iss = 1;
                                end
                            end
                        end
                    end
                end

                S_DONE: begin
                    busy <= 0; done <= 1; state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
