`timescale 1ns / 1ps

module work_dispatch_dynamic_rows #(
    parameter CORE_COUNT = 4
) (
    input  wire                     clk,
    input  wire                     rst,
    input  wire                     start,
    input  wire [15:0]              rows,
    input  wire [CORE_COUNT-1:0]    core_done,

    output reg  [CORE_COUNT-1:0]    core_start,
    output reg  [CORE_COUNT*16-1:0] row_start_bus,
    output reg  [CORE_COUNT*16-1:0] row_stride_bus,

    output reg                      owner_wr,
    output reg  [15:0]              owner_row,
    output reg  [7:0]               owner_core
);

    reg        active = 0;
    reg [15:0] next_row = 0;
    reg [CORE_COUNT-1:0] core_active = 0;
    reg [CORE_COUNT-1:0] core_done_block = 0;

    integer i;
    reg assigned;
    reg [CORE_COUNT-1:0] active_next;

    always @(posedge clk) begin
        if (rst) begin
            active <= 0;
            next_row <= 0;
            core_active <= 0;
            core_done_block <= 0;
            core_start <= 0;
            row_start_bus <= 0;
            row_stride_bus <= 0;
            owner_wr <= 0;
            owner_row <= 0;
            owner_core <= 0;
        end else begin
            core_start <= 0;
            owner_wr <= 0;

            if (start) begin
                active <= (rows != 0);
                next_row <= 0;
                core_active <= 0;
                core_done_block <= 0;
                row_stride_bus <= {CORE_COUNT{rows}};
            end else if (active) begin
                active_next = core_active & ~core_done;
                core_done_block <= (core_done_block | core_done) & core_done;
                assigned = 0;
                for (i = 0; i < CORE_COUNT; i = i + 1) begin
                    if (!assigned && !active_next[i] && !core_done_block[i] && !core_done[i] && next_row < rows) begin
                        core_start[i] <= 1'b1;
                        row_start_bus[i*16 +: 16] <= next_row;
                        row_stride_bus[i*16 +: 16] <= rows;
                        active_next[i] = 1'b1;
                        owner_wr <= 1'b1;
                        owner_row <= next_row;
                        owner_core <= i[7:0];
                        next_row <= next_row + 16'd1;
                        assigned = 1'b1;
                    end
                end
                core_active <= active_next;

                if (!assigned && next_row >= rows)
                    active <= 0;
            end
        end
    end

endmodule
