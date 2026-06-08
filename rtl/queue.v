`timescale 1ns / 1ps

module queue #(
    parameter DEPTH = 128,
    parameter DATA_W = 8
) (
    input  wire                 clk,
    output wire                 write_avail,
    output wire                 read_avail,
    input  wire                 write_en,
    input  wire                 read_en,
    input  wire [DATA_W-1:0]    data_in,
    output reg  [DATA_W-1:0]    data_out
);

    localparam ADDR_W = $clog2(DEPTH);

    reg [DATA_W-1:0] mem [0:DEPTH-1];
    reg [ADDR_W:0]   write_ptr = 0;
    reg [ADDR_W:0]   read_ptr  = 0;
    reg              read_ctrl  = 1;
    reg              write_ctrl = 1;

    wire read_valid  = write_ptr != read_ptr;
    wire write_valid = ((write_ptr + 1) % DEPTH) != read_ptr;

    assign read_avail  = read_valid && read_ctrl;
    assign write_avail = write_valid && write_ctrl;

    always @(posedge clk) begin
        if (write_en && write_avail) begin
            mem[write_ptr[ADDR_W-1:0]] <= data_in;
            write_ptr <= (write_ptr + 1) % DEPTH;
            write_ctrl <= 0;
        end else if (!write_en) begin
            write_ctrl <= 1;
        end
    end

    always @(posedge clk) begin
        if (read_en && read_avail) begin
            data_out <= mem[read_ptr[ADDR_W-1:0]];
            read_ptr <= (read_ptr + 1) % DEPTH;
            read_ctrl <= 0;
        end else if (!read_en) begin
            read_ctrl <= 1;
        end
    end

endmodule
