`timescale 1ns / 1ps
`ifndef CONFIG_VH
`include "config.vh"
`endif

// PL power-on reset generator.
//
// On ZU+ designs where the PL tester and interconnect reset would otherwise be
// driven by zynq_ultra_ps_e_0/pl_resetn0, that reset line is held low by the PS
// until FSBL/PMUFW releases it. If the PS never runs firmware (blank boot), the
// PL logic stays in reset forever and the UART debug path is dead.
//
// This module produces a clean, self-contained reset derived only from the PL
// clock. After bitstream configuration the internal counter starts at zero
// (FPGA INIT), holds rstn low for RST_MS, then deasserts through a 3-FF
// synchronizer. This lets the tester respond over UART immediately after the
// bitstream is loaded, before any PS firmware runs.
//
// An optional ext_rstn input (active low) is AND-gated into the output so a PS
// or button reset can still be applied when wired. Tie ext_rstn to 1'b1 to keep
// the reset purely PL-local.

module pl_por #(
    parameter integer CLK_HZ = `CFG_CLK_HZ,
    parameter integer RST_MS = 5,
    parameter integer USE_EXT_RST = 0
) (
    input  wire clk,
    input  wire ext_rstn,
    output wire rstn
);

    localparam integer RST_CYCLES = ((CLK_HZ / 1000) * RST_MS) > 0 ? ((CLK_HZ / 1000) * RST_MS) : 1;

    reg [31:0] cnt = 32'd0;
    reg        por = 1'b1;
    reg [2:0]  pipe = 3'b000;

    always @(posedge clk) begin
        if (cnt < RST_CYCLES) begin
            cnt <= cnt + 32'd1;
            por <= 1'b1;
        end else begin
            por <= 1'b0;
        end
        pipe <= {pipe[1:0], (~por) & (USE_EXT_RST ? ext_rstn : 1'b1)};
    end

    assign rstn = pipe[2];

endmodule
