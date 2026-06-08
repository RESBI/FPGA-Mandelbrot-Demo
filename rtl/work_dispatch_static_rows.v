`timescale 1ns / 1ps

module work_dispatch_static_rows #(
    parameter CORE_COUNT = 4
) (
    input  wire                         start,
    output wire [CORE_COUNT-1:0]        core_start,
    output wire [CORE_COUNT*16-1:0]     row_start_bus,
    output wire [CORE_COUNT*16-1:0]     row_stride_bus
);

    genvar i;
    generate
        for (i = 0; i < CORE_COUNT; i = i + 1) begin : g_assign
            assign core_start[i] = start;
            assign row_start_bus[i*16 +: 16] = i[15:0];
            assign row_stride_bus[i*16 +: 16] = CORE_COUNT[15:0];
        end
    endgenerate

endmodule
