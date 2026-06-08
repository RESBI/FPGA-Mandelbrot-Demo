`timescale 1ns / 1ps
`include "fp_defines.vh"

module mandelbrot_core (
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

    output reg  [15:0]              fifo_data,
    output reg                      fifo_wr,
    input  wire                     fifo_full,

    output reg                      tx_start,
    output reg  [15:0]              tx_rows,
    output reg  [15:0]              tx_cols
);

    // Core issues FP inputs on one ce and reads registered FP outputs on a later ce.
    localparam PIPE_WAIT = 6;

    // States
    localparam S_IDLE            = 6'd0;
    localparam S_INIT_START      = 6'd1;
    localparam S_INIT_W_CAPTURE  = 6'd2;
    localparam S_INIT_W2_CAPTURE = 6'd3;
    localparam S_INIT_H_CAPTURE  = 6'd4;
    localparam S_INIT_H2_CAPTURE = 6'd5;
    localparam S_ROW_START       = 6'd6;
    localparam S_ITER_START      = 6'd7;
    localparam S_MUL_ZRSQ_CAPT   = 6'd8;
    localparam S_MUL_ZISQ_CAPT   = 6'd9;
    localparam S_MUL_ZRZI_CAPT   = 6'd10;
    localparam S_SUB_RE_CAPT     = 6'd11;
    localparam S_ADD_NEXTRE_CAPT = 6'd12;
    localparam S_ADD_2X_CAPT     = 6'd13;
    localparam S_ADD_NEXTIM_CAPT = 6'd14;
    localparam S_ITER_INC        = 6'd15;
    localparam S_OUTPUT_WAIT     = 6'd16;
    localparam S_OUTPUT          = 6'd17;
    localparam S_NEXT_COL        = 6'd18;
    localparam S_NEXT_ROW        = 6'd19;
    localparam S_NEXT_ROW_WAIT   = 6'd20;
    localparam S_DONE            = 6'd21;

    reg [5:0] state = S_IDLE;
    reg [2:0]  pipe_wait;  // pipeline wait counter
    reg        start_latched;  // latch start outside ce block

    // Capture start pulse on every clock (not just ce cycles)
    always @(posedge clk) begin
        if (rst)
            start_latched <= 0;
        else if (start)
            start_latched <= 1;
        else if (ce && state == S_IDLE && start_latched)
            start_latched <= 0;
    end

    reg [`FP_WIDTH-1:0] center_re, center_im, step_val;
    reg [15:0] max_iter, rows, cols;
    reg [`FP_WIDTH-1:0] c_re, c_im, c_re_start;
    reg [`FP_WIDTH-1:0] z_re, z_im;
    reg [`FP_WIDTH-1:0] z_re_sq, z_im_sq, z_re_z_im;
    reg [15:0] row, col;
    reg [15:0] iter;
    reg [15:0] half_w, half_h;

    reg [`FP_WIDTH-1:0] mul_a, mul_b;
    reg [`FP_WIDTH-1:0] add_a, add_b;
    reg                 add_neg;

    wire [`FP_WIDTH-1:0] mul_result;
    wire [`FP_WIDTH-1:0] add_result;
    wire [`FP_WIDTH-1:0] add_b_eff = add_neg ? {~add_b[`FP_SIGN_IDX], add_b[`FP_EXP_HI:0]} : add_b;

    fp_mul u_mul (.clk(clk), .rst(rst), .ce(ce), .a(mul_a), .b(mul_b), .product(mul_result));
    fp_add u_add (.clk(clk), .rst(rst), .ce(ce), .a(add_a), .b(add_b_eff), .sum(add_result));

    // Check if value > 4.0
    function quick_esc;
        input [`FP_WIDTH-1:0] val;
        begin
            quick_esc = (val[`FP_EXP_HI:`FP_EXP_LO] > (`FP_BIAS + 2)) ||
                        ((val[`FP_EXP_HI:`FP_EXP_LO] == (`FP_BIAS + 2)) && (val[`FP_MAN_HI:0] != 0));
        end
    endfunction

    // Integer to FP
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
            state     <= S_IDLE;
            busy      <= 0;
            done      <= 0;
            fifo_wr   <= 0;
            tx_start  <= 0;
            pipe_wait <= 0;
        end else if (ce) begin
            if (pipe_wait) begin
                pipe_wait <= pipe_wait - 1'b1;
            end else begin
                case (state)
                    S_IDLE: begin
                        done <= 0;
                        fifo_wr <= 0;
                        tx_start <= 0;
                        if (start_latched) begin
                            center_re <= center_re_in;
                            center_im <= center_im_in;
                            step_val  <= step_in;
                            max_iter  <= max_iter_in;
                            rows      <= rows_in;
                            cols      <= cols_in;
                            busy      <= 1;
                            tx_rows   <= rows_in;
                            tx_cols   <= cols_in;
                            tx_start  <= 1;
                            half_w <= (cols_in - 16'd1) >> 1;
                            state <= S_INIT_START;
                        end
                    end

                    // --- Initialization with pipelined FP ---
                    S_INIT_START: begin
                        tx_start <= 0;
                        mul_a <= int2fp(half_w);
                        mul_b <= step_val;
                        pipe_wait <= PIPE_WAIT;
                        state <= S_INIT_W_CAPTURE;
                    end

                    S_INIT_W_CAPTURE: begin
                        // mul_result = re_offset = half_w * step
                        add_a <= center_re;
                        add_b <= mul_result;
                        add_neg <= 1;  // c_re_start = center_re - re_offset
                        pipe_wait <= PIPE_WAIT;
                        state <= S_INIT_W2_CAPTURE;
                    end

                    S_INIT_W2_CAPTURE: begin
                        // add_result = c_re_start
                        c_re_start <= add_result;
                        half_h <= (rows - 16'd1) >> 1;
                        mul_a <= int2fp((rows - 16'd1) >> 1);
                        mul_b <= step_val;
                        pipe_wait <= PIPE_WAIT;
                        state <= S_INIT_H_CAPTURE;
                    end

                    S_INIT_H_CAPTURE: begin
                        // mul_result = im_offset = half_h * step
                        add_a <= center_im;
                        add_b <= mul_result;
                        add_neg <= 0;  // c_im = center_im + im_offset
                        pipe_wait <= PIPE_WAIT;
                        state <= S_INIT_H2_CAPTURE;
                    end

                    S_INIT_H2_CAPTURE: begin
                        c_im <= add_result;
                        row <= 0;
                        state <= S_ROW_START;
                    end

                    // --- Row / Column iteration ---
                    S_ROW_START: begin
                        c_re <= c_re_start;
                        col <= 0;
                        state <= S_ITER_START;
                    end

                    S_ITER_START: begin
                        z_re <= 0;
                        z_im <= 0;
                        iter <= 0;
                        if (max_iter == 0) begin
                            state <= S_OUTPUT_WAIT;
                        end else begin
                            mul_a <= 0;
                            mul_b <= 0;  // z_re * z_re (initial)
                            pipe_wait <= PIPE_WAIT;
                            state <= S_MUL_ZRSQ_CAPT;
                        end
                    end

                    // --- Pipelined iteration loop ---
                    // Each capture state: gets result of previous op, starts next op
                    S_MUL_ZRSQ_CAPT: begin
                        z_re_sq <= mul_result;    // z_re^2
                        mul_a <= z_im;
                        mul_b <= z_im;             // start z_im^2
                        pipe_wait <= PIPE_WAIT;
                        state <= S_MUL_ZISQ_CAPT;
                    end

                    S_MUL_ZISQ_CAPT: begin
                        z_im_sq <= mul_result;    // z_im^2
                        // Start z_re*z_im AND escape add (both have same pipeline depth)
                        mul_a <= z_re;
                        mul_b <= z_im;             // z_re * z_im
                        add_a <= z_re_sq;
                        add_b <= mul_result;
                        add_neg <= 0;              // z_re^2 + z_im^2 (escape check)
                        pipe_wait <= PIPE_WAIT;
                        state <= S_MUL_ZRZI_CAPT;
                    end

                S_MUL_ZRZI_CAPT: begin
                    z_re_z_im <= mul_result;
                    if (quick_esc(z_re_sq) || quick_esc(z_im_sq) || quick_esc(add_result)) begin
                        state <= S_OUTPUT_WAIT;
                    end else begin
                        add_a <= z_re_sq;
                        add_b <= z_im_sq;
                        add_neg <= 1;
                        pipe_wait <= PIPE_WAIT;
                        state <= S_SUB_RE_CAPT;
                    end
                end

                    S_SUB_RE_CAPT: begin
                        // add_result = z_re^2 - z_im^2
                        add_a <= add_result;
                        add_b <= c_re;
                        add_neg <= 0;              // (z_re^2 - z_im^2) + c_re
                        pipe_wait <= PIPE_WAIT;
                        state <= S_ADD_NEXTRE_CAPT;
                    end

                    S_ADD_NEXTRE_CAPT: begin
                        z_re <= add_result;        // new z_re
                        // 2 * z_re_z_im = z_re_z_im + z_re_z_im
                        add_a <= z_re_z_im;
                        add_b <= z_re_z_im;
                        add_neg <= 0;
                        pipe_wait <= PIPE_WAIT;
                        state <= S_ADD_2X_CAPT;
                    end

                    S_ADD_2X_CAPT: begin
                        // add_result = 2 * z_re_z_im
                        add_a <= add_result;
                        add_b <= c_im;
                        add_neg <= 0;              // 2*z_re*z_im + c_im
                        pipe_wait <= PIPE_WAIT;
                        state <= S_ADD_NEXTIM_CAPT;
                    end

                    S_ADD_NEXTIM_CAPT: begin
                        z_im <= add_result;        // new z_im
                        iter <= iter + 1;
                        state <= S_ITER_INC;
                    end

                    S_ITER_INC: begin
                        if (iter >= max_iter) begin
                            state <= S_OUTPUT_WAIT;
                        end else begin
                            mul_a <= z_re;
                            mul_b <= z_re;          // next z_re^2
                            pipe_wait <= PIPE_WAIT;
                            state <= S_MUL_ZRSQ_CAPT;
                        end
                    end

                    S_OUTPUT_WAIT: begin
                        if (!fifo_full) begin
                            fifo_data <= iter;
                            fifo_wr <= 1;
                            state <= S_OUTPUT;
                        end
                    end

                    S_OUTPUT: begin
                        fifo_wr <= 0;
                        add_a <= c_re;
                        add_b <= step_val;
                        add_neg <= 0;              // c_re + step
                        pipe_wait <= PIPE_WAIT;
                        state <= S_NEXT_COL;
                    end

                    S_NEXT_COL: begin
                        c_re <= add_result;
                        if ((col + 1) >= cols) begin
                            state <= S_NEXT_ROW;
                        end else begin
                            col <= col + 1;
                            state <= S_ITER_START;
                        end
                    end

                    S_NEXT_ROW: begin
                        add_a <= c_im;
                        add_b <= step_val;
                        add_neg <= 1;              // c_im - step
                        pipe_wait <= PIPE_WAIT;
                        state <= S_NEXT_ROW_WAIT;
                    end

                    S_NEXT_ROW_WAIT: begin
                        // add_result ready: c_im - step
                        if ((row + 1) >= rows) begin
                            state <= S_DONE;
                        end else begin
                            row <= row + 1;
                            c_im <= add_result;
                            state <= S_ROW_START;
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
