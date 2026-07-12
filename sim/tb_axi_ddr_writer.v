`timescale 1ns / 1ps

module tb_axi_ddr_writer;
    reg clk = 0;
    reg rstn = 0;
    always #2.5 clk = ~clk;

    reg start;
    reg done_ack;
    reg [63:0] base_addr;
    reg [31:0] pixel_count;
    wire busy;
    wire done;
    wire [15:0] checksum;
    wire error;
    wire [1:0] error_resp;
    wire done_sticky;
    wire [2:0] dbg_state;
    wire [31:0] dbg_p_sent;
    wire [31:0] dbg_p_total;

    wire fifo_rd_en;
    wire [15:0] fifo_rd_data;
    wire fifo_rd_avail;
    wire fifo_write_avail;
    reg fifo_write_en;
    reg [15:0] fifo_write_data;

    wire [63:0] awaddr;
    wire [7:0] awlen;
    wire [2:0] awsize;
    wire [1:0] awburst;
    wire awlock;
    wire [3:0] awcache;
    wire [2:0] awprot;
    wire [3:0] awqos;
    wire awvalid;
    reg awready;
    wire [63:0] wdata;
    wire [7:0] wstrb;
    wire wlast;
    wire wvalid;
    reg wready;
    reg [1:0] bresp;
    reg bvalid;
    wire bready;

    reg [15:0] source [0:64];
    integer source_index;
    integer beat_index;
    integer aw_count;
    integer failures;
    reg [63:0] expected_beat;

    queue #(.DEPTH(128), .DATA_W(16)) source_fifo (
        .clk(clk), .rst(~rstn),
        .write_avail(fifo_write_avail), .read_avail(fifo_rd_avail),
        .write_en(fifo_write_en), .read_en(fifo_rd_en),
        .data_in(fifo_write_data), .data_out(fifo_rd_data)
    );

    axi_ddr_writer dut (
        .aclk(clk), .aresetn(rstn), .start(start), .done_ack(done_ack),
        .base_addr(base_addr), .pixel_count(pixel_count), .busy(busy),
        .done(done), .checksum(checksum), .error(error), .error_resp(error_resp),
        .done_sticky(done_sticky), .dbg_state(dbg_state),
        .dbg_p_sent(dbg_p_sent), .dbg_p_total(dbg_p_total),
        .fifo_rd_en(fifo_rd_en), .fifo_rd_data(fifo_rd_data),
        .fifo_rd_avail(fifo_rd_avail), .m_axi_awaddr(awaddr),
        .m_axi_awlen(awlen), .m_axi_awsize(awsize), .m_axi_awburst(awburst),
        .m_axi_awlock(awlock), .m_axi_awcache(awcache), .m_axi_awprot(awprot),
        .m_axi_awqos(awqos), .m_axi_awvalid(awvalid), .m_axi_awready(awready),
        .m_axi_wdata(wdata), .m_axi_wstrb(wstrb), .m_axi_wlast(wlast),
        .m_axi_wvalid(wvalid), .m_axi_wready(wready), .m_axi_bresp(bresp),
        .m_axi_bvalid(bvalid), .m_axi_bready(bready)
    );

    always @(posedge clk) begin
        if (!rstn) begin
            awready <= 1;
            wready <= 1;
            bvalid <= 0;
            bresp <= 0;
            beat_index <= 0;
            aw_count <= 0;
        end else begin
            if (awvalid && awready) begin
                if (awaddr !== (64'h1000_0000 + aw_count * 128)) begin
                    $display("ERROR AW %0d got=%016x expected=%016x",
                             aw_count, awaddr, 64'h1000_0000 + aw_count * 128);
                    failures = failures + 1;
                end
                aw_count <= aw_count + 1;
            end
            if (wvalid && wready) begin
                if (beat_index < 16)
                    expected_beat = {source[beat_index*4+3], source[beat_index*4+2],
                                     source[beat_index*4+1], source[beat_index*4]};
                else if (beat_index == 16)
                    expected_beat = {48'd0, source[64]};
                else
                    expected_beat = 0;
                if (wdata !== expected_beat) begin
                    $display("ERROR beat %0d got=%016x expected=%016x",
                             beat_index, wdata, expected_beat);
                    failures = failures + 1;
                end
                beat_index <= beat_index + 1;
                if (wlast)
                    bvalid <= 1;
            end
            if (bvalid && bready)
                bvalid <= 0;
        end
    end

    initial begin
        for (source_index = 0; source_index < 65; source_index = source_index + 1)
            source[source_index] = source_index + 1;
        start = 0;
        done_ack = 0;
        base_addr = 64'h1000_0000;
        pixel_count = 65;
        fifo_write_en = 0;
        fifo_write_data = 0;
        source_index = 0;
        failures = 0;

        repeat (10) @(posedge clk);
        rstn = 1;
        repeat (3) @(posedge clk);
        start = 1;
        @(posedge clk);
        start = 0;

        // Keep the FIFO empty after AWREADY to catch duplicate AW submissions.
        repeat (20) @(posedge clk);
        while (source_index < 65) begin
            @(negedge clk);
            if (fifo_write_avail) begin
                fifo_write_en = 1;
                fifo_write_data = source[source_index];
                source_index = source_index + 1;
            end
        end
        @(negedge clk);
        fifo_write_en = 0;

        wait(done_sticky);
        if (checksum !== 16'h0001) begin
            $display("ERROR checksum got=%04x", checksum);
            failures = failures + 1;
        end
        if (beat_index != 32) begin
            $display("ERROR beat count got=%0d expected=32", beat_index);
            failures = failures + 1;
        end
        if (aw_count != 2) begin
            $display("ERROR AW count got=%0d expected=2", aw_count);
            failures = failures + 1;
        end
        if (error) begin
            $display("ERROR writer response error=%0d", error_resp);
            failures = failures + 1;
        end

        if (failures == 0)
            $display("=== AXI DDR WRITER TEST PASS ===");
        else
            $display("=== AXI DDR WRITER TEST FAIL: %0d ===", failures);
        $finish;
    end
endmodule
