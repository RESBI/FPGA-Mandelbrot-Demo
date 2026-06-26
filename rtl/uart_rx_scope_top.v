`timescale 1ns / 1ps

module uart_rx_scope_top (
    input  wire uart_rx,
    output wire uart_tx,
    input  wire sys_clk,
    input  wire rst_n,
    output wire [3:2] led
);

    localparam CLK_HZ = 24576000;
    localparam WINDOW_CYCLES = CLK_HZ / 10;

    wire clk;
    BUFG u_sys_clk_bufg (.I(sys_clk), .O(clk));

    reg [7:0] rst_cnt = 8'd0;
    wire rst = (rst_cnt != 8'hff);
    always @(posedge clk) begin
        if (rst_cnt != 8'hff)
            rst_cnt <= rst_cnt + 1'b1;
    end

    reg rx_meta = 1'b1;
    reg rx_sync = 1'b1;
    reg rx_prev = 1'b1;
    reg [21:0] window_ctr = 22'd0;
    reg [15:0] fall_ctr = 16'd0;
    reg [15:0] rise_ctr = 16'd0;
    reg [23:0] low_ctr = 24'd0;
    reg [15:0] fall_latched = 16'd0;
    reg [15:0] rise_latched = 16'd0;
    reg [23:0] low_latched = 24'd0;
    reg rx_latched = 1'b1;
    reg frame_pending = 1'b0;
    reg [7:0] seq = 8'd0;

    always @(posedge clk) begin
        rx_meta <= uart_rx;
        rx_sync <= rx_meta;
        rx_prev <= rx_sync;

        if (rst) begin
            window_ctr <= 22'd0;
            fall_ctr <= 16'd0;
            rise_ctr <= 16'd0;
            low_ctr <= 24'd0;
            frame_pending <= 1'b0;
            seq <= 8'd0;
        end else begin
            if (rx_prev && !rx_sync)
                fall_ctr <= fall_ctr + 1'b1;
            if (!rx_prev && rx_sync)
                rise_ctr <= rise_ctr + 1'b1;
            if (!rx_sync)
                low_ctr <= low_ctr + 1'b1;

            if (window_ctr == WINDOW_CYCLES - 1) begin
                window_ctr <= 22'd0;
                fall_latched <= fall_ctr;
                rise_latched <= rise_ctr;
                low_latched <= low_ctr;
                rx_latched <= rx_sync;
                fall_ctr <= 16'd0;
                rise_ctr <= 16'd0;
                low_ctr <= 24'd0;
                frame_pending <= 1'b1;
                seq <= seq + 1'b1;
            end else begin
                window_ctr <= window_ctr + 1'b1;
            end

            if (frame_done)
                frame_pending <= 1'b0;
        end
    end

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

    localparam FRAME_LEN = 11;
    localparam TX_IDLE = 2'd0;
    localparam TX_LOAD = 2'd1;
    localparam TX_SEND = 2'd2;
    localparam TX_WAIT = 2'd3;
    reg [3:0] frame_idx = 4'd0;
    reg [1:0] tx_state = TX_IDLE;
    reg frame_done = 1'b0;

    always @(posedge clk) begin
        tx_en <= 1'b0;
        frame_done <= 1'b0;

        if (rst) begin
            frame_idx <= 4'd0;
            tx_state <= TX_IDLE;
            tx_data <= 8'h00;
        end else begin
            case (tx_state)
                TX_IDLE: begin
                    if (frame_pending) begin
                        frame_idx <= 4'd0;
                        tx_state <= TX_LOAD;
                    end
                end

                TX_LOAD: begin
                    case (frame_idx)
                        4'd0: tx_data <= 8'hA5;
                        4'd1: tx_data <= 8'h5A;
                        4'd2: tx_data <= seq;
                        4'd3: tx_data <= {7'd0, rx_latched};
                        4'd4: tx_data <= fall_latched[7:0];
                        4'd5: tx_data <= fall_latched[15:8];
                        4'd6: tx_data <= rise_latched[7:0];
                        4'd7: tx_data <= rise_latched[15:8];
                        4'd8: tx_data <= low_latched[7:0];
                        4'd9: tx_data <= low_latched[15:8];
                        default: tx_data <= low_latched[23:16];
                    endcase
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
                            tx_state <= TX_IDLE;
                            frame_done <= 1'b1;
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

    wire unused_rst_n = rst_n;
    assign led = {rx_sync, |fall_latched};

endmodule
