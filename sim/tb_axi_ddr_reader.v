`timescale 1ns / 1ps

module tb_axi_ddr_reader;
    reg clk = 0;
    reg rstn = 0;
    always #2.5 clk = ~clk;

    reg start;
    reg [63:0] base_addr;
    reg [31:0] pixel_count;
    wire busy;
    wire done;
    wire error;
    wire [1:0] error_resp;

    reg pixel_rd_en;
    wire [15:0] pixel_rd_data;
    wire pixel_rd_avail;

    wire [63:0] araddr;
    wire [7:0] arlen;
    wire [2:0] arsize;
    wire [1:0] arburst;
    wire arlock;
    wire [3:0] arcache;
    wire [2:0] arprot;
    wire [3:0] arqos;
    wire arvalid;
    reg arready;
    reg [63:0] rdata;
    reg [1:0] rresp;
    reg rlast;
    reg rvalid;
    wire rready;

    reg sending;
    reg [63:0] send_addr;
    reg [7:0] send_beats;
    reg [7:0] send_index;
    reg [1:0] consume_delay;
    integer expected_pixel;
    integer failures;
    integer inject_error_beat;
    reg [1:0] inject_error_resp;

    axi_ddr_reader #(
        .AXI_DATA_WIDTH(64),
        .AXI_ADDR_WIDTH(64),
        .MAX_BURST_BEATS(16),
        .BEAT_FIFO_DEPTH(16)
    ) dut (
        .aclk(clk), .aresetn(rstn),
        .start(start), .base_addr(base_addr), .pixel_count(pixel_count),
        .busy(busy), .done(done), .error(error), .error_resp(error_resp),
        .pixel_rd_en(pixel_rd_en), .pixel_rd_data(pixel_rd_data),
        .pixel_rd_avail(pixel_rd_avail),
        .m_axi_araddr(araddr), .m_axi_arlen(arlen), .m_axi_arsize(arsize),
        .m_axi_arburst(arburst), .m_axi_arlock(arlock), .m_axi_arcache(arcache),
        .m_axi_arprot(arprot), .m_axi_arqos(arqos), .m_axi_arvalid(arvalid),
        .m_axi_arready(arready), .m_axi_rdata(rdata), .m_axi_rresp(rresp),
        .m_axi_rlast(rlast), .m_axi_rvalid(rvalid), .m_axi_rready(rready)
    );

    function [15:0] pixel_value;
        input [63:0] byte_addr;
        reg [63:0] index;
        begin
            index = (byte_addr - base_addr) >> 1;
            pixel_value = index[15:0] ^ 16'h5A5A;
        end
    endfunction

    function [63:0] beat_value;
        input [63:0] byte_addr;
        begin
            beat_value = {
                pixel_value(byte_addr + 6),
                pixel_value(byte_addr + 4),
                pixel_value(byte_addr + 2),
                pixel_value(byte_addr)
            };
        end
    endfunction

    always @(posedge clk) begin
        if (!rstn) begin
            arready <= 1;
            rvalid <= 0;
            rlast <= 0;
            rresp <= 0;
            rdata <= 0;
            sending <= 0;
            send_addr <= 0;
            send_beats <= 0;
            send_index <= 0;
        end else begin
            if (!sending && arvalid && arready) begin
                sending <= 1;
                send_addr <= araddr;
                send_beats <= arlen + 1'b1;
                send_index <= 0;
                rvalid <= 1;
                rdata <= beat_value(araddr);
                rlast <= (arlen == 0);
                rresp <= (inject_error_beat == 0) ? inject_error_resp : 0;
            end else if (sending && rvalid && rready) begin
                if ((send_index + 1'b1) >= send_beats) begin
                    sending <= 0;
                    rvalid <= 0;
                    rlast <= 0;
                    rresp <= 0;
                end else begin
                    send_index <= send_index + 1'b1;
                    rdata <= beat_value(send_addr + ({56'd0, send_index + 1'b1} << 3));
                    rlast <= ((send_index + 2) >= send_beats);
                    rresp <= ((send_index + 1'b1) == inject_error_beat) ? inject_error_resp : 0;
                end
            end
        end
    end

    always @(posedge clk) begin
        if (!rstn) begin
            pixel_rd_en <= 0;
            consume_delay <= 0;
            expected_pixel <= 0;
        end else begin
            pixel_rd_en <= 0;
            if (consume_delay == 2) begin
                consume_delay <= 1;
            end else if (consume_delay == 1) begin
                if (pixel_rd_data !== (expected_pixel[15:0] ^ 16'h5A5A)) begin
                    $display("ERROR pixel %0d got=%04x expected=%04x",
                             expected_pixel, pixel_rd_data,
                             expected_pixel[15:0] ^ 16'h5A5A);
                    failures = failures + 1;
                end
                expected_pixel <= expected_pixel + 1;
                consume_delay <= 0;
            end else if (pixel_rd_avail) begin
                pixel_rd_en <= 1;
                consume_delay <= 2;
            end
        end
    end

    task run_case;
        input integer count;
        integer timeout;
        begin
            expected_pixel = 0;
            consume_delay = 0;
            pixel_count = count;
            base_addr = 64'h0000_0000_1000_0FF8;
            start = 1;
            @(posedge clk);
            start = 0;
            timeout = 0;
            while ((!done || expected_pixel < count) && timeout < 200000) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            if (timeout >= 200000) begin
                $display("ERROR timeout count=%0d expected_pixel=%0d", count, expected_pixel);
                failures = failures + 1;
            end
            if (error) begin
                $display("ERROR reader error count=%0d resp=%0d", count, error_resp);
                failures = failures + 1;
            end
            if (expected_pixel != count) begin
                $display("ERROR count=%0d consumed=%0d", count, expected_pixel);
                failures = failures + 1;
            end
            repeat (5) @(posedge clk);
            $display("case %0d pixels complete", count);
        end
    endtask

    task run_error_case;
        integer timeout;
        begin
            expected_pixel = 0;
            consume_delay = 0;
            pixel_count = 8;
            base_addr = 64'h0000_0000_1000_2000;
            inject_error_beat = 1;
            inject_error_resp = 2'b10;
            start = 1;
            @(posedge clk);
            start = 0;
            timeout = 0;
            while (!error && timeout < 2000) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            if (timeout >= 2000 || error_resp != 2'b10) begin
                $display("ERROR RRESP propagation timeout=%0d resp=%0d", timeout, error_resp);
                failures = failures + 1;
            end
            if (sending || rvalid) begin
                $display("ERROR reader reported before AXI burst drained");
                failures = failures + 1;
            end
            $display("RRESP error case complete");
        end
    endtask

    initial begin
        start = 0;
        base_addr = 0;
        pixel_count = 0;
        pixel_rd_en = 0;
        failures = 0;
        inject_error_beat = -1;
        inject_error_resp = 0;
        repeat (10) @(posedge clk);
        rstn = 1;
        repeat (5) @(posedge clk);

        run_case(1);
        run_case(3);
        run_case(4);
        run_case(5);
        run_case(63);
        run_case(64);
        run_case(65);
        run_case(129);
        run_error_case();

        if (failures == 0)
            $display("=== AXI DDR READER TEST PASS ===");
        else
            $display("=== AXI DDR READER TEST FAIL: %0d ===", failures);
        $finish;
    end
endmodule
