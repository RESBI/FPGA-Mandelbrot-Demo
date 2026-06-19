`timescale 1ns / 1ps
`include "fp_defines.vh"

module tb_fp_latency();
    reg clk = 0;
    reg rst = 1;
    reg ce = 1;
    reg [`FP_WIDTH-1:0] mul_a = 0;
    reg [`FP_WIDTH-1:0] mul_b = 0;
    reg [`FP_WIDTH-1:0] add_a = 0;
    reg [`FP_WIDTH-1:0] add_b = 0;
    wire [`FP_WIDTH-1:0] product;
    wire [`FP_WIDTH-1:0] sum;

    integer cycle;

    fp_mul u_mul (.clk(clk), .rst(rst), .ce(ce), .a(mul_a), .b(mul_b), .product(product));
    fp_add u_add (.clk(clk), .rst(rst), .ce(ce), .a(add_a), .b(add_b), .sum(sum));

    always #5 clk = ~clk;

    function [`FP_WIDTH-1:0] f64;
        input real val;
        reg [63:0] bits;
        begin
            bits = $realtobits(val);
            f64 = bits;
        end
    endfunction

    initial begin
        cycle = 0;
        repeat (3) @(posedge clk);
        rst = 0;
        repeat (2) @(posedge clk);

        @(negedge clk);
        mul_a = f64(-0.35);
        mul_b = f64(-0.35);
        add_a = f64(0.125);
        add_b = f64(0.25);
        @(negedge clk);
        mul_a = 0;
        mul_b = 0;
        add_a = 0;
        add_b = 0;

        repeat (20) @(posedge clk);
        $finish;
    end

    always @(posedge clk) begin
        cycle <= cycle + 1;
        $display("LAT cycle=%0d product=%h sum=%h", cycle, product, sum);
    end
endmodule
