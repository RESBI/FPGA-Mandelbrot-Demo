`timescale 1ns / 1ps

module tb_tx_ctrl_host_tiled_4096;

    reg clk = 0;
    reg rst = 1;
    reg start = 0;
    reg [15:0] rows = 0;
    reg [15:0] cols = 16'd4096;
    reg fifo_avail = 1;
    reg [15:0] fifo_data = 0;
    reg tx_avail = 1;

    wire done;
    wire fifo_rd;
    wire [7:0] tx_data;
    wire tx_en;

    localparam FULL_ROWS = 4096;
    localparam FULL_COLS = 4096;
    localparam HOST_TILE_H = 120;
    localparam TILE_COLS = 64;
    localparam TOTAL_PIXELS = FULL_ROWS * FULL_COLS;
    localparam EXPECTED_TD = FULL_ROWS * (FULL_COLS / TILE_COLS);
    localparam EXPECTED_FRAMES = (FULL_ROWS + HOST_TILE_H - 1) / HOST_TILE_H;

    localparam P_FRAME_HDR = 0;
    localparam P_MAGIC     = 1;
    localparam P_TD_HDR    = 2;
    localparam P_PAYLOAD   = 3;
    localparam P_CHECKSUM  = 4;
    localparam P_TE_REST   = 5;
    localparam P_DONE      = 6;

    integer frame_idx;
    integer y0;
    integer th;
    integer tx_count;
    integer fifo_reads;
    integer payload_pixels;
    integer td_count;
    integer te_count;
    integer errors;
    integer parser_state;
    integer hdr_idx;
    integer payload_bytes_left;
    integer row;
    integer col;
    integer tile_rows;
    integer tile_cols;
    integer checksum;
    integer data_byte_phase;
    reg [7:0] got;
    reg [7:0] hdr [0:9];

    tx_ctrl #(.RESPONSE_TILE_GAP_CYCLES(0)) u_dut (
        .clk(clk),
        .rst(rst),
        .start(start),
        .rows(rows),
        .cols(cols),
        .done(done),
        .fifo_rd(fifo_rd),
        .fifo_data(fifo_data),
        .fifo_avail(fifo_avail),
        .tx_data(tx_data),
        .tx_en(tx_en),
        .tx_avail(tx_avail)
    );

    always #5 clk = ~clk;

    always @(posedge clk) begin
        if (rst) begin
            fifo_data <= 0;
            fifo_reads <= 0;
        end else if (fifo_rd) begin
            fifo_data <= fifo_reads[15:0];
            fifo_reads <= fifo_reads + 1;
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            tx_avail <= 1;
        end else if (tx_en && tx_avail) begin
            tx_avail <= 0;
        end else begin
            tx_avail <= 1;
        end
    end

    task fail;
        input [255:0] msg;
        begin
            $display("FAIL frame=%0d: %0s", frame_idx, msg);
            errors = errors + 1;
        end
    endtask

    task reset_parser;
        begin
            parser_state = P_FRAME_HDR;
            hdr_idx = 0;
            payload_bytes_left = 0;
            checksum = 0;
            data_byte_phase = 0;
        end
    endtask

    always @(posedge clk) begin
        if (!rst && tx_en && tx_avail) begin
            got = tx_data;
            tx_count = tx_count + 1;

            case (parser_state)
                P_FRAME_HDR: begin
                    hdr[hdr_idx] = got;
                    hdr_idx = hdr_idx + 1;
                    if (hdr_idx == 6) begin
                        if (hdr[0] != 8'h52 || hdr[1] != 8'h54) fail("bad RT magic");
                        if ({hdr[3], hdr[2]} != th) fail("bad RT rows");
                        if ({hdr[5], hdr[4]} != FULL_COLS) fail("bad RT cols");
                        hdr_idx = 0;
                        parser_state = P_MAGIC;
                    end
                end

                P_MAGIC: begin
                    hdr[hdr_idx] = got;
                    hdr_idx = hdr_idx + 1;
                    if (hdr_idx == 2) begin
                        if (hdr[0] == 8'h54 && hdr[1] == 8'h44) begin
                            hdr_idx = 2;
                            parser_state = P_TD_HDR;
                        end else if (hdr[0] == 8'h54 && hdr[1] == 8'h45) begin
                            hdr_idx = 2;
                            parser_state = P_TE_REST;
                        end else begin
                            fail("bad packet magic");
                        end
                    end
                end

                P_TD_HDR: begin
                    hdr[hdr_idx] = got;
                    hdr_idx = hdr_idx + 1;
                    if (hdr_idx == 10) begin
                        row = {hdr[3], hdr[2]};
                        col = {hdr[5], hdr[4]};
                        tile_rows = {hdr[7], hdr[6]};
                        tile_cols = {hdr[9], hdr[8]};
                        if (tile_rows != 1) fail("tile_rows not 1");
                        if (tile_cols != TILE_COLS) fail("tile_cols not 64");
                        if (row < 0 || row >= th) fail("row out of range");
                        if (col < 0 || col >= FULL_COLS) fail("col out of range");
                        td_count = td_count + 1;
                        payload_bytes_left = tile_rows * tile_cols * 2;
                        checksum = 0;
                        data_byte_phase = 0;
                        parser_state = P_PAYLOAD;
                    end
                end

                P_PAYLOAD: begin
                    checksum = checksum ^ got;
                    payload_bytes_left = payload_bytes_left - 1;
                    data_byte_phase = data_byte_phase + 1;
                    if (data_byte_phase == 2) begin
                        payload_pixels = payload_pixels + 1;
                        data_byte_phase = 0;
                    end
                    if (payload_bytes_left == 0)
                        parser_state = P_CHECKSUM;
                end

                P_CHECKSUM: begin
                    if (got != checksum[7:0]) fail("tile checksum mismatch");
                    hdr_idx = 0;
                    parser_state = P_MAGIC;
                end

                P_TE_REST: begin
                    hdr[hdr_idx] = got;
                    hdr_idx = hdr_idx + 1;
                    if (hdr_idx == 6) begin
                        if ({hdr[3], hdr[2]} != th) fail("bad TE rows");
                        if ({hdr[5], hdr[4]} != FULL_COLS) fail("bad TE cols");
                        te_count = te_count + 1;
                        parser_state = P_DONE;
                    end
                end

                default: begin end
            endcase
        end
    end

    task run_one_host_tile;
        input integer tile_rows;
        begin
            th = tile_rows;
            rows = tile_rows[15:0];
            reset_parser();
            repeat (5) @(posedge clk);
            @(negedge clk); start = 1;
            @(negedge clk); start = 0;
            while (!done) begin
                @(posedge clk);
            end
            repeat (3) @(posedge clk);
            if (parser_state != P_DONE) begin
                $display("FAIL frame=%0d parser_state=%0d", frame_idx, parser_state);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        frame_idx = 0;
        y0 = 0;
        th = 0;
        tx_count = 0;
        fifo_reads = 0;
        payload_pixels = 0;
        td_count = 0;
        te_count = 0;
        errors = 0;
        reset_parser();

        repeat (5) @(posedge clk);
        rst = 0;
        repeat (5) @(posedge clk);

        for (y0 = 0; y0 < FULL_ROWS; y0 = y0 + HOST_TILE_H) begin
            frame_idx = frame_idx + 1;
            if (FULL_ROWS - y0 > HOST_TILE_H)
                run_one_host_tile(HOST_TILE_H);
            else
                run_one_host_tile(FULL_ROWS - y0);
        end

        if (frame_idx != EXPECTED_FRAMES) begin
            $display("FAIL: frames=%0d expected=%0d", frame_idx, EXPECTED_FRAMES);
            errors = errors + 1;
        end
        if (te_count != EXPECTED_FRAMES) begin
            $display("FAIL: te_count=%0d expected=%0d", te_count, EXPECTED_FRAMES);
            errors = errors + 1;
        end
        if (td_count != EXPECTED_TD) begin
            $display("FAIL: td_count=%0d expected=%0d", td_count, EXPECTED_TD);
            errors = errors + 1;
        end
        if (payload_pixels != TOTAL_PIXELS) begin
            $display("FAIL: payload_pixels=%0d expected=%0d", payload_pixels, TOTAL_PIXELS);
            errors = errors + 1;
        end
        if (fifo_reads != TOTAL_PIXELS) begin
            $display("FAIL: fifo_reads=%0d expected=%0d", fifo_reads, TOTAL_PIXELS);
            errors = errors + 1;
        end

        if (errors == 0)
            $display("=== HOST-TILED 4096 TEST PASS: frames=%0d td=%0d pixels=%0d bytes=%0d ===", frame_idx, td_count, payload_pixels, tx_count);
        else
            $display("=== HOST-TILED 4096 TEST FAIL: errors=%0d frames=%0d td=%0d pixels=%0d ===", errors, frame_idx, td_count, payload_pixels);
        $finish;
    end

    initial begin
        repeat (220000000) @(posedge clk);
        $display("=== HOST-TILED 4096 TEST TIMEOUT: frame=%0d td=%0d pixels=%0d state=%0d ===", frame_idx, td_count, payload_pixels, parser_state);
        $finish;
    end

endmodule
