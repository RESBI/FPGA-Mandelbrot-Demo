`timescale 1ns / 1ps

module queue #(
    parameter DEPTH = 128,
    parameter DATA_W = 8
) (
    input  wire                 clk,
    input  wire                 rst,
    output wire                 write_avail,
    output wire                 read_avail,
    input  wire                 write_en,
    input  wire                 read_en,
    input  wire [DATA_W-1:0]    data_in,
    output reg  [DATA_W-1:0]    data_out
);

    localparam ADDR_W = $clog2(DEPTH);

    reg [DATA_W-1:0] mem [0:DEPTH-1];
    reg [ADDR_W-1:0] write_ptr = 0;
    reg [ADDR_W-1:0] read_ptr  = 0;
    reg [ADDR_W:0]   count     = 0;

    wire write_fire = write_en && write_avail;
    wire read_fire  = read_en && read_avail;

    assign read_avail  = (count != 0);
    assign write_avail = (count != DEPTH);

    always @(posedge clk) begin
        if (rst) begin
            write_ptr <= 0;
            read_ptr  <= 0;
            count     <= 0;
            data_out  <= 0;
        end else begin
        if (write_fire) begin
            mem[write_ptr[ADDR_W-1:0]] <= data_in;
            write_ptr <= write_ptr + 1'b1;
        end

        if (read_fire) begin
            data_out <= mem[read_ptr[ADDR_W-1:0]];
            read_ptr <= read_ptr + 1'b1;
        end

        case ({write_fire, read_fire})
            2'b10: count <= count + 1'b1;
            2'b01: count <= count - 1'b1;
            default: count <= count;
        endcase
        end
    end

    initial begin
        write_ptr = 0;
        read_ptr = 0;
        count = 0;
        data_out = 0;
    end

endmodule
