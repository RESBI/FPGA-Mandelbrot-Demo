`timescale 1ns / 1ps

module uart_tx_pattern_top (
    input  wire uart_rx,
    output wire uart_tx,
    input  wire sys_clk
);

    wire [7:0] tx_data;
    wire       tx_en;
    wire       tx_avail;

    uart_tx u_tx (
        .tx             (uart_tx),
        .clk            (sys_clk),
        .data           (tx_data),
        .transmit_en    (tx_en),
        .transmit_avail (tx_avail)
    );

    localparam PATTERN_LEN = 8;
    localparam STATE_GAP   = 2'd0;
    localparam STATE_LOAD  = 2'd1;
    localparam STATE_PULSE = 2'd2;
    localparam STATE_WAIT  = 2'd3;

    reg [1:0] state = STATE_GAP;
    reg [2:0] pattern_idx = 0;
    reg [23:0] gap_counter = 24'd100000;
    reg tx_en_r = 0;
    reg [7:0] tx_data_r = 8'h55;

    assign tx_en = tx_en_r;
    assign tx_data = tx_data_r;

    always @(posedge sys_clk) begin
        tx_en_r <= 1'b0;

        case (state)
            STATE_GAP: begin
                if (gap_counter != 0) begin
                    gap_counter <= gap_counter - 1'b1;
                end else begin
                    state <= STATE_LOAD;
                end
            end

            STATE_LOAD: begin
                case (pattern_idx)
                    3'd0: tx_data_r <= 8'h55;
                    3'd1: tx_data_r <= 8'hAA;
                    3'd2: tx_data_r <= 8'h00;
                    3'd3: tx_data_r <= 8'hFF;
                    3'd4: tx_data_r <= 8'h52;
                    3'd5: tx_data_r <= 8'h4B;
                    3'd6: tx_data_r <= 8'h01;
                    default: tx_data_r <= 8'h7E;
                endcase
                state <= STATE_PULSE;
            end

            STATE_PULSE: begin
                if (tx_avail) begin
                    tx_en_r <= 1'b1;
                    state <= STATE_WAIT;
                end
            end

            STATE_WAIT: begin
                if (!tx_avail) begin
                    if (pattern_idx == PATTERN_LEN - 1) begin
                        pattern_idx <= 0;
                        gap_counter <= 24'd100000;
                        state <= STATE_GAP;
                    end else begin
                        pattern_idx <= pattern_idx + 1'b1;
                        state <= STATE_LOAD;
                    end
                end
            end

            default: state <= STATE_GAP;
        endcase
    end

    wire unused_uart_rx = uart_rx;

endmodule
