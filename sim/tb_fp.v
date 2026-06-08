`timescale 1ns / 1ps
`include "fp_defines.vh"

module tb_fp();

    reg clk = 0;
    reg rst = 1;
    reg ce = 0;
    reg [`FP_WIDTH-1:0] a, b;
    wire [`FP_WIDTH-1:0] mul_out, add_out;
    wire [`FP_WIDTH-1:0] add_b_eff = b;  // no negation for direct test

    fp_mul u_mul (.clk(clk), .rst(rst), .ce(ce), .a(a), .b(b), .product(mul_out));
    fp_add u_add (.clk(clk), .rst(rst), .ce(ce), .a(a), .b(add_b_eff), .sum(add_out));

    always #5 clk = ~clk;

    // Encode float64 manually
    function [`FP_WIDTH-1:0] f64;
        input real val;
        reg [63:0] bits;
        begin
            bits = $realtobits(val);
            f64 = bits;
        end
    endfunction

    // Decode float64 for debug display
    function [63:0] f64_exp;
        input [`FP_WIDTH-1:0] val;
        begin
            f64_exp = val[62:52];
        end
    endfunction

    task run_pipeline;
        begin
            @(negedge clk); ce = 1;
            @(negedge clk); ce = 0;
            repeat(4) begin
                @(negedge clk); ce = 1;
                @(negedge clk); ce = 0;
            end
        end
    endtask

    task test_mul;
        input real ra, rb;
        begin
            a = f64(ra);
            b = f64(rb);
            run_pipeline();
            $display("MUL: %f * %f => exp=%d man=%h sign=%d",
                ra, rb, mul_out[62:52], mul_out[51:0], mul_out[63]);
        end
    endtask

    task test_add;
        input real ra, rb;
        begin
            a = f64(ra);
            b = f64(rb);
            run_pipeline();
            $display("ADD: %f + %f => exp=%d man=%h sign=%d",
                ra, rb, add_out[62:52], add_out[51:0], add_out[63]);
        end
    endtask

    initial begin
        $display("=== FP64 Test ===");

        repeat(5) @(posedge clk);
        rst = 0;
        repeat(3) @(posedge clk);

        $display("--- Multiply ---");
        test_mul(0.0, 0.0);
        test_mul(1.0, 1.0);
        test_mul(2.0, 3.0);
        test_mul(2.5, 2.5);
        test_mul(2.6, 2.6);
        test_mul(3.0, 3.0);
        test_mul(79.0, 0.005);
        test_mul(59.0, 0.005);

        $display("--- Addition ---");
        test_add(0.0, 0.0);
        test_add(6.25, 0.0);
        test_add(0.0, 6.25);
        test_add(1.5, 3.5);
        test_add(-0.75, 0.1);
        test_add(0.5625, -0.01);
        test_add(-0.75, -0.15);
        test_add(-0.075, -0.075);
        test_add(-0.15, 0.1);
        test_add(0.0, -0.75);

        $display("=== Done ===");
        $finish;
    end

endmodule
