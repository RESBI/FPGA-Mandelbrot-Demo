`timescale 1ns / 1ps
`include "fp_defines.vh"

module tb_cmd_parser_soft_reset;
    reg clk = 0;
    reg rst = 1;
    reg [7:0] rx_data = 0;
    reg rx_avail = 0;
    reg compute_busy = 0;
    wire compute_start;
    wire [`FP_WIDTH-1:0] center_re;
    wire [`FP_WIDTH-1:0] center_im;
    wire [`FP_WIDTH-1:0] step;
    wire [15:0] max_iter;
    wire [15:0] rows;
    wire [15:0] cols;
    wire precision_mode;
    wire soft_reset;

    cmd_parser u_dut (
        .clk(clk),
        .rst(rst),
        .rx_data(rx_data),
        .rx_avail(rx_avail),
        .compute_start(compute_start),
        .compute_busy(compute_busy),
        .center_re(center_re),
        .center_im(center_im),
        .step(step),
        .max_iter(max_iter),
        .rows(rows),
        .cols(cols),
        .precision_mode(precision_mode),
        .soft_reset(soft_reset)
    );

    always #5 clk = ~clk;

    task send_byte;
        input [7:0] b;
        begin
            @(posedge clk);
            rx_data <= b;
            rx_avail <= 1;
            @(posedge clk);
            rx_avail <= 0;
            rx_data <= 0;
        end
    endtask

    initial begin
        repeat (5) @(posedge clk);
        rst <= 0;
        repeat (2) @(posedge clk);

        send_byte("R");
        send_byte("S");
        send_byte("T");
        send_byte("!");
        send_byte("R");
        send_byte("S");
        send_byte("T");
        send_byte("!");

        @(posedge clk);
        if (!soft_reset) begin
            $display("ERROR: soft_reset was not asserted after RST!RST!");
            $finish;
        end

        @(posedge clk);
        if (soft_reset) begin
            $display("ERROR: soft_reset stayed asserted for more than one cycle");
            $finish;
        end

        $display("=== CMD PARSER SOFT RESET TEST PASS ===");
        $finish;
    end
endmodule
