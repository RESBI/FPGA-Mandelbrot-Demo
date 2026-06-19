`timescale 1ns / 1ps
`include "fp_defines.vh"

module fp_mul (
    input  wire                     clk,
    input  wire                     rst,
    input  wire                     ce,
    input  wire [`FP_WIDTH-1:0]     a,
    input  wire [`FP_WIDTH-1:0]     b,
    output reg  [`FP_WIDTH-1:0]     product
);

    reg [`FP_WIDTH-1:0] a_r, b_r;

    always @(posedge clk) begin
        if (ce) begin
            a_r <= a;
            b_r <= b;
        end
    end

    wire                  sign_a = a_r[`FP_SIGN_IDX];
    wire [`FP_EXP_W-1:0]  exp_a  = a_r[`FP_EXP_HI:`FP_EXP_LO];
    wire [`FP_MAN_W-1:0]  man_a  = a_r[`FP_MAN_HI:0];
    wire                  sign_b = b_r[`FP_SIGN_IDX];
    wire [`FP_EXP_W-1:0]  exp_b  = b_r[`FP_EXP_HI:`FP_EXP_LO];
    wire [`FP_MAN_W-1:0]  man_b  = b_r[`FP_MAN_HI:0];

    wire a_is_zero = (exp_a == 0) && (man_a == 0);
    wire b_is_zero = (exp_b == 0) && (man_b == 0);

    wire [`FP_MAN_W:0] full_man_a = a_is_zero ? 0 : {1'b1, man_a};
    wire [`FP_MAN_W:0] full_man_b = b_is_zero ? 0 : {1'b1, man_b};

    wire result_sign = sign_a ^ sign_b;
    wire [`FP_EXP_W:0] exp_sum = {1'b0, exp_a} + {1'b0, exp_b};

    // Stage 2: register decoded mantissas before the wide DSP multiply.
    // This removes zero mux / exponent decode logic from the DSP input path.
    reg [`FP_MAN_W:0]    full_man_a_r, full_man_b_r;
    reg                  result_sign_man_r;
    reg [`FP_EXP_W:0]    exp_sum_man_r;
    reg                  a_zero_man_r, b_zero_man_r;

    always @(posedge clk) begin
        if (ce) begin
            full_man_a_r      <= full_man_a;
            full_man_b_r      <= full_man_b;
            result_sign_man_r <= result_sign;
            exp_sum_man_r     <= exp_sum;
            a_zero_man_r      <= a_is_zero;
            b_zero_man_r      <= b_is_zero;
        end
    end

    localparam MAN_FULL_W = `FP_MAN_W + 1;
    localparam PART_LO_W = 26;
    localparam PART_HI_W = MAN_FULL_W - PART_LO_W;
    localparam PROD_W = 2 * MAN_FULL_W;

    wire [PART_LO_W-1:0] man_a_lo = full_man_a_r[PART_LO_W-1:0];
    wire [PART_HI_W-1:0] man_a_hi = full_man_a_r[MAN_FULL_W-1:PART_LO_W];
    wire [PART_LO_W-1:0] man_b_lo = full_man_b_r[PART_LO_W-1:0];
    wire [PART_HI_W-1:0] man_b_hi = full_man_b_r[MAN_FULL_W-1:PART_LO_W];

    wire [(2*PART_LO_W)-1:0]       partial_ll = man_a_lo * man_b_lo;
    wire [(PART_LO_W+PART_HI_W)-1:0] partial_lh = man_a_lo * man_b_hi;
    wire [(PART_LO_W+PART_HI_W)-1:0] partial_hl = man_a_hi * man_b_lo;
    wire [(2*PART_HI_W)-1:0]       partial_hh = man_a_hi * man_b_hi;

    // Stage 3: register narrower partial products to break the 53x53 DSP cascade.
    reg [(2*PART_LO_W)-1:0]       partial_ll_r;
    reg [(PART_LO_W+PART_HI_W)-1:0] partial_lh_r;
    reg [(PART_LO_W+PART_HI_W)-1:0] partial_hl_r;
    reg [(2*PART_HI_W)-1:0]       partial_hh_r;
    reg                   result_sign_dsp_r;
    reg [`FP_EXP_W:0]     exp_sum_dsp_r;
    reg                   a_zero_dsp_r, b_zero_dsp_r;

    always @(posedge clk) begin
        if (ce) begin
            partial_ll_r      <= partial_ll;
            partial_lh_r      <= partial_lh;
            partial_hl_r      <= partial_hl;
            partial_hh_r      <= partial_hh;
            result_sign_dsp_r <= result_sign_man_r;
            exp_sum_dsp_r     <= exp_sum_man_r;
            a_zero_dsp_r      <= a_zero_man_r;
            b_zero_dsp_r      <= b_zero_man_r;
        end
    end

    wire [PROD_W-1:0] partial_ll_ext = {{(PROD_W-(2*PART_LO_W)){1'b0}}, partial_ll_r};
    wire [PROD_W-1:0] partial_lh_ext = {{(PROD_W-(PART_LO_W+PART_HI_W)-PART_LO_W){1'b0}}, partial_lh_r, {PART_LO_W{1'b0}}};
    wire [PROD_W-1:0] partial_hl_ext = {{(PROD_W-(PART_LO_W+PART_HI_W)-PART_LO_W){1'b0}}, partial_hl_r, {PART_LO_W{1'b0}}};
    wire [PROD_W-1:0] partial_hh_ext = {{(PROD_W-(2*PART_HI_W)-(2*PART_LO_W)){1'b0}}, partial_hh_r, {(2*PART_LO_W){1'b0}}};

    wire [PROD_W-1:0] man_product_sum = partial_ll_ext + partial_lh_ext + partial_hl_ext + partial_hh_ext;

    // Stage 4: register recombined multiply result metadata with DSP output
    reg [PROD_W-1:0]      man_product_r;
    reg                   result_sign_r;
    reg [`FP_EXP_W:0]     exp_sum_r;
    reg                   a_zero_r, b_zero_r;

    always @(posedge clk) begin
        if (ce) begin
            man_product_r  <= man_product_sum;
            result_sign_r  <= result_sign_dsp_r;
            exp_sum_r      <= exp_sum_dsp_r;
            a_zero_r       <= a_zero_dsp_r;
            b_zero_r       <= b_zero_dsp_r;
        end
    end

    // Stage 5: normalize + output
    wire exp_uf_s2 = (exp_sum_r < `FP_BIAS);
    wire [`FP_EXP_W:0] exp_no_bias_full_s2;
    assign exp_no_bias_full_s2 = exp_sum_r - `FP_BIAS;
    wire [`FP_EXP_W-1:0] exp_no_bias_s2 = exp_no_bias_full_s2[`FP_EXP_W-1:0];

    wire msb_prod_s2 = man_product_r[PROD_W-1];
    wire [`FP_EXP_W-1:0] exp_final_s2;
    assign exp_final_s2 = msb_prod_s2 ? (exp_no_bias_s2 + 1) : exp_no_bias_s2;

    wire [`FP_MAN_W-1:0] man_final_s2;
    assign man_final_s2 = msb_prod_s2 ? man_product_r[PROD_W-2:PROD_W-1-`FP_MAN_W]
                                      : man_product_r[PROD_W-3:PROD_W-2-`FP_MAN_W];

    wire exp_of_s2 = (exp_final_s2 >= `FP_EXP_MAX);

    always @(posedge clk) begin
        if (rst)
            product <= 0;
        else if (ce) begin
            if (a_zero_r || b_zero_r || exp_uf_s2 || exp_of_s2)
                product <= 0;
            else
                product <= {result_sign_r, exp_final_s2, man_final_s2};
        end
    end

endmodule
