`timescale 1ns / 1ps
`include "fx_defines.vh"

module fx_mul (
    input  wire                   clk,
    input  wire                   rst,
    input  wire                   ce,
    input  wire signed [`FX_W-1:0] a,
    input  wire signed [`FX_W-1:0] b,
    output reg  signed [`FX_W-1:0] product
);

    reg signed [`FX_W-1:0] a_r, b_r;
    reg signed [2*`FX_W-1:0] prod_r;

    always @(posedge clk) begin
        if (rst) begin
            a_r <= 0;
            b_r <= 0;
            prod_r <= 0;
            product <= 0;
        end else if (ce) begin
            a_r <= a;
            b_r <= b;
            prod_r <= a_r * b_r;
            product <= prod_r[`FX_FRAC + `FX_W - 1 : `FX_FRAC];
        end
    end

endmodule
