`timescale 1ns / 1ps
`include "fx_defines.vh"

module fx_add (
    input  wire                   clk,
    input  wire                   rst,
    input  wire                   ce,
    input  wire signed [`FX_W-1:0] a,
    input  wire signed [`FX_W-1:0] b,
    output reg  signed [`FX_W-1:0] sum
);

    always @(posedge clk) begin
        if (rst)
            sum <= 0;
        else if (ce)
            sum <= a + b;
    end

endmodule
