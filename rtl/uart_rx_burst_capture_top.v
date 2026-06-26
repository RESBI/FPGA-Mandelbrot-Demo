`timescale 1ns / 1ps

module uart_rx_burst_capture_top (
    input  wire uart_rx,
    output wire uart_tx,
    input  wire sys_clk,
    input  wire rst_n,
    output wire [3:2] led
);

    localparam CLK_HZ = 24576000;
    localparam IDLE_CYCLES = 16'd20000;
    localparam MAX_CAPTURE = 64;

    wire clk;
    BUFG u_sys_clk_bufg (.I(sys_clk), .O(clk));

    reg [7:0] rst_cnt = 8'd0;
    wire rst = !rst_n || (rst_cnt != 8'hff);

    always @(posedge clk) begin
        if (!rst_n)
            rst_cnt <= 8'd0;
        else if (rst_cnt != 8'hff)
            rst_cnt <= rst_cnt + 1'b1;
    end

    wire [7:0] rx_data;
    wire rx_avail;
    uart_rx #(.CLK_HZ(CLK_HZ)) u_rx (
        .rx         (uart_rx),
        .clk        (clk),
        .data       (rx_data),
        .data_avail (rx_avail)
    );

    wire tx_avail;
    reg tx_en = 1'b0;
    reg [7:0] tx_data = 8'h00;
    uart_tx #(.CLK_HZ(CLK_HZ)) u_tx (
        .tx             (uart_tx),
        .clk            (clk),
        .data           (tx_data),
        .transmit_en    (tx_en),
        .transmit_avail (tx_avail)
    );

    reg [7:0] capture [0:MAX_CAPTURE-1];
    reg [6:0] count = 7'd0;
    reg [7:0] xor_all = 8'd0;
    reg active = 1'b0;
    reg [15:0] idle_ctr = 16'd0;
    reg frame_pending = 1'b0;
    reg overflow = 1'b0;

    integer i;
    always @(posedge clk) begin
        if (rst) begin
            count <= 7'd0;
            xor_all <= 8'd0;
            active <= 1'b0;
            idle_ctr <= 16'd0;
            frame_pending <= 1'b0;
            overflow <= 1'b0;
            for (i = 0; i < MAX_CAPTURE; i = i + 1)
                capture[i] <= 8'd0;
        end else begin
            if (rx_avail) begin
                if (!active && !frame_pending) begin
                    count <= 7'd1;
                    xor_all <= rx_data;
                    capture[0] <= rx_data;
                    overflow <= 1'b0;
                end else if (!frame_pending) begin
                    if (count < MAX_CAPTURE) begin
                        capture[count] <= rx_data;
                        count <= count + 1'b1;
                    end else begin
                        overflow <= 1'b1;
                    end
                    xor_all <= xor_all ^ rx_data;
                end
                active <= 1'b1;
                idle_ctr <= 16'd0;
            end else if (active && !frame_pending) begin
                if (idle_ctr == IDLE_CYCLES) begin
                    active <= 1'b0;
                    frame_pending <= 1'b1;
                end else begin
                    idle_ctr <= idle_ctr + 1'b1;
                end
            end

            if (frame_done) begin
                frame_pending <= 1'b0;
                count <= 7'd0;
                xor_all <= 8'd0;
                overflow <= 1'b0;
            end
        end
    end

    localparam HEADER_LEN = 5;
    localparam FRAME_LEN = HEADER_LEN + MAX_CAPTURE;
    localparam TX_IDLE = 2'd0;
    localparam TX_LOAD = 2'd1;
    localparam TX_SEND = 2'd2;
    localparam TX_WAIT = 2'd3;

    reg [6:0] frame_idx = 7'd0;
    reg [1:0] tx_state = TX_IDLE;
    reg frame_done = 1'b0;

    always @(posedge clk) begin
        tx_en <= 1'b0;
        frame_done <= 1'b0;

        if (rst) begin
            frame_idx <= 7'd0;
            tx_state <= TX_IDLE;
            tx_data <= 8'h00;
        end else begin
            case (tx_state)
                TX_IDLE: begin
                    if (frame_pending) begin
                        frame_idx <= 7'd0;
                        tx_state <= TX_LOAD;
                    end
                end

                TX_LOAD: begin
                    if (frame_idx == 7'd0)
                        tx_data <= 8'h42; // B
                    else if (frame_idx == 7'd1)
                        tx_data <= 8'h43; // C
                    else if (frame_idx == 7'd2)
                        tx_data <= {overflow, count};
                    else if (frame_idx == 7'd3)
                        tx_data <= xor_all;
                    else if (frame_idx == 7'd4)
                        tx_data <= IDLE_CYCLES[7:0];
                    else
                        tx_data <= capture[frame_idx - HEADER_LEN];
                    tx_state <= TX_SEND;
                end

                TX_SEND: begin
                    if (tx_avail) begin
                        tx_en <= 1'b1;
                        tx_state <= TX_WAIT;
                    end
                end

                TX_WAIT: begin
                    if (!tx_avail) begin
                        if (frame_idx == FRAME_LEN - 1) begin
                            frame_done <= 1'b1;
                            tx_state <= TX_IDLE;
                        end else begin
                            frame_idx <= frame_idx + 1'b1;
                            tx_state <= TX_LOAD;
                        end
                    end
                end

                default: tx_state <= TX_IDLE;
            endcase
        end
    end

    reg [31:0] heartbeat = 32'd0;
    always @(posedge clk)
        heartbeat <= heartbeat + 1'b1;

    assign led = {frame_pending | active, heartbeat[25]};

endmodule
