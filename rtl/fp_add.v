`timescale 1ns / 1ps
`include "fp_defines.vh"

module fp_add (
    input  wire                     clk,
    input  wire                     rst,
    input  wire                     ce,
    input  wire [`FP_WIDTH-1:0]     a,
    input  wire [`FP_WIDTH-1:0]     b,
    output reg  [`FP_WIDTH-1:0]     sum
);

    localparam INT_W = `FP_MAN_W + 2;

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

    wire [INT_W-1:0] man_ext_a = a_is_zero ? 0 : {1'b1, man_a, 1'b0};
    wire [INT_W-1:0] man_ext_b = b_is_zero ? 0 : {1'b1, man_b, 1'b0};

    wire a_gt_b = (exp_a > exp_b) || ((exp_a == exp_b) && (man_ext_a >= man_ext_b));

    wire                  sign_large = a_gt_b ? sign_a : sign_b;
    wire [`FP_EXP_W-1:0]  exp_large  = a_gt_b ? exp_a  : exp_b;
    wire [INT_W-1:0]      man_large  = a_gt_b ? man_ext_a : man_ext_b;
    wire [`FP_EXP_W-1:0]  exp_small  = a_gt_b ? exp_b  : exp_a;
    wire [INT_W-1:0]      man_small  = a_gt_b ? man_ext_b : man_ext_a;
    wire                  same_sign  = ~(sign_a ^ sign_b);
    wire [`FP_EXP_W-1:0]  diff       = exp_large - exp_small;

    // Stage 1: decode, compare, and select operands. Splitting this from
    // alignment/add-sub keeps the 100 MHz critical path out of one long cone.
    reg [INT_W-1:0]        man_large_s1, man_small_s1;
    reg [`FP_EXP_W-1:0]    exp_large_s1;
    reg [`FP_EXP_W-1:0]    diff_s1;
    reg                    sign_large_s1;
    reg                    same_sign_s1;
    reg                    a_zero_s1, b_zero_s1;
    reg [`FP_WIDTH-1:0]    a_store_s1, b_store_s1;

    always @(posedge clk) begin
        if (ce) begin
            man_large_s1 <= man_large;
            man_small_s1 <= man_small;
            exp_large_s1 <= exp_large;
            diff_s1      <= diff;
            sign_large_s1 <= sign_large;
            same_sign_s1 <= same_sign;
            a_zero_s1    <= a_is_zero;
            b_zero_s1    <= b_is_zero;
            a_store_s1   <= a_r;
            b_store_s1   <= b_r;
        end
    end

    wire [INT_W-1:0] man_small_align;
    assign man_small_align = (diff_s1 >= INT_W) ? 0 : (man_small_s1 >> diff_s1);

    wire [INT_W:0] man_result_raw;
    assign man_result_raw = same_sign_s1 ?
        ({1'b0, man_large_s1} + {1'b0, man_small_align}) :
        ({1'b0, man_large_s1} - {1'b0, man_small_align});

    // Stage 2: align + add/sub pipeline
    reg [INT_W:0]          man_result_r;
    reg [`FP_EXP_W-1:0]    exp_large_r;
    reg                    sign_large_r;
    reg                    a_zero_r, b_zero_r;
    reg [`FP_WIDTH-1:0]    a_store, b_store;

    always @(posedge clk) begin
        if (ce) begin
            man_result_r  <= man_result_raw;
            exp_large_r   <= exp_large_s1;
            sign_large_r  <= sign_large_s1;
            a_zero_r      <= a_zero_s1;
            b_zero_r      <= b_zero_s1;
            a_store       <= a_store_s1;
            b_store       <= b_store_s1;
        end
    end

    // Stage 3: normalize + bypass with stored inputs
    wire result_is_zero_s2 = (man_result_r == 0);
    wire msb_s2 = man_result_r[INT_W];
    wire [INT_W-1:0] man_after_add_s2 = man_result_r[INT_W-1:0];

    reg [7:0] lead_zeros;
    reg       found;
    integer   k;
    always @(*) begin
        lead_zeros = 0;
        found = 0;
        for (k = INT_W-1; k >= 0; k = k - 1) begin
            if (!found && man_after_add_s2[k]) begin
                lead_zeros = (INT_W - 1) - k;
                found = 1;
            end
        end
    end

    reg [`FP_MAN_W-1:0] man_final;
    reg [`FP_EXP_W-1:0] exp_final;
    reg                 sign_final;
    reg [INT_W-1:0]     man_norm;

    always @(*) begin
        if (result_is_zero_s2) begin
            sign_final = 1'b0;
            exp_final  = 0;
            man_final  = 0;
            man_norm   = 0;
        end else if (msb_s2) begin
            sign_final = sign_large_r;
            exp_final  = exp_large_r + 1;
            man_norm   = man_result_r[INT_W:1];
            man_final  = man_result_r[INT_W-1:2];
        end else begin
            sign_final = sign_large_r;
            if (exp_large_r > lead_zeros) begin
                exp_final = exp_large_r - lead_zeros;
            end else begin
                exp_final = 0;
            end
            man_norm = man_after_add_s2 << lead_zeros;
            man_final = man_norm[INT_W-2:1];
        end
    end

    wire exp_of_s2 = (exp_final >= `FP_EXP_MAX);

    reg [`FP_MAN_W-1:0] man_final_r;
    reg [`FP_EXP_W-1:0] exp_final_r;
    reg                 sign_final_r;
    reg                 exp_of_r;
    reg                 result_is_zero_r;
    reg                 a_zero_s3, b_zero_s3;
    reg [`FP_WIDTH-1:0] a_store_s3, b_store_s3;

    always @(posedge clk) begin
        if (ce) begin
            man_final_r      <= man_final;
            exp_final_r      <= exp_final;
            sign_final_r     <= sign_final;
            exp_of_r         <= exp_of_s2;
            result_is_zero_r <= result_is_zero_s2;
            a_zero_s3        <= a_zero_r;
            b_zero_s3        <= b_zero_r;
            a_store_s3       <= a_store;
            b_store_s3       <= b_store;
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            sum <= 0;
        end else if (ce) begin
            if (a_zero_s3) begin
                sum <= b_store_s3;
            end else if (b_zero_s3) begin
                sum <= a_store_s3;
            end else if (exp_of_r || result_is_zero_r) begin
                sum <= 0;
            end else begin
                sum <= {sign_final_r, exp_final_r, man_final_r};
            end
        end
    end

endmodule
