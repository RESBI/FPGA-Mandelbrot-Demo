`timescale 1ns / 1ps
`include "config.vh"
`include "fp_defines.vh"

module top #(
    parameter CLK_HZ = `CFG_CLK_HZ,
    parameter DIRECT_200MHZ = `CFG_DIRECT_200MHZ,
    parameter SCHED_MODE = `CFG_SCHED_MODE,
    parameter DYNAMIC_OWNER_DEPTH = `CFG_DYNAMIC_OWNER_DEPTH,
    parameter CORE_COUNT = `CFG_CORE_COUNT,
    parameter WORKER_CONTEXTS = `CFG_WORKER_CONTEXTS
) (
    input  wire uart_rx,
    output wire uart_tx,
    input  wire sys_clk,
    input  wire rst_n,
    output wire [3:2] led
);

    wire clk;
    wire clk_locked;

    BUFG u_sys_clk_bufg (
        .I(sys_clk),
        .O(clk)
    );

    assign clk_locked = 1'b1;

    // Clock enable for FP operations
    reg [`FP_CE_DIV-1:0] ce_counter;
    wire fp_ce;
    assign fp_ce = (`FP_CE_DIV == 1) ? 1'b1 : (ce_counter == `FP_CE_DIV - 1);

    always @(posedge clk) begin
        if (`FP_CE_DIV == 1)
            ce_counter <= 0;
        else if (ce_counter == `FP_CE_DIV - 1)
            ce_counter <= 0;
        else
            ce_counter <= ce_counter + 1;
    end

    // Reset generation
    reg [3:0] rst_cnt = 0;
    wire power_on_rst;
    wire rst;
    wire soft_reset;
    reg [7:0] soft_rst_cnt = 0;
    assign power_on_rst = !rst_n || !clk_locked || (rst_cnt < 15);
    assign rst = power_on_rst || (soft_rst_cnt != 0);

    always @(posedge clk) begin
        if (!rst_n || !clk_locked)
            rst_cnt <= 0;
        else if (rst_cnt < 15)
            rst_cnt <= rst_cnt + 1;
    end

    always @(posedge clk) begin
        if (power_on_rst)
            soft_rst_cnt <= 0;
        else if (soft_reset)
            soft_rst_cnt <= 8'd32;
        else if (soft_rst_cnt != 0)
            soft_rst_cnt <= soft_rst_cnt - 1'b1;
    end

    // UART signals
    wire [7:0] rx_data;
    wire       rx_avail;

    wire [7:0] tx_data;
    wire       tx_en;
    wire       tx_avail;

    // Command parser signals
    wire       compute_start;
    wire       compute_busy;
    wire [`FP_WIDTH-1:0] cmd_center_re;
    wire [`FP_WIDTH-1:0] cmd_center_im;
    wire [`FP_WIDTH-1:0] cmd_step;
    wire [15:0] cmd_max_iter;
    wire [15:0] cmd_rows;
    wire [15:0] cmd_cols;
    wire       cmd_precision;

    // Result FIFO signals
    wire       fifo_wr_en;
    wire [15:0] fifo_wr_data;
    wire       fifo_full;
    wire       fifo_rd_en;
    wire [15:0] fifo_rd_data;
    wire       fifo_rd_avail;

    // TX control signals
    wire       tx_ctrl_start;
    wire [15:0] tx_ctrl_rows;
    wire [15:0] tx_ctrl_cols;
    wire       tx_ctrl_done;

    uart_rx #(
        .CLK_HZ(CLK_HZ)
    ) u_rx (
        .rx         (uart_rx),
        .clk        (clk),
        .data       (rx_data),
        .data_avail (rx_avail)
    );

    uart_tx #(
        .CLK_HZ(CLK_HZ)
    ) u_tx (
        .tx             (uart_tx),
        .clk            (clk),
        .data           (tx_data),
        .transmit_en    (tx_en),
        .transmit_avail (tx_avail)
    );

    cmd_parser u_cmd (
        .clk            (clk),
        .rst            (rst),
        .rx_data        (rx_data),
        .rx_avail       (rx_avail),
        .compute_start  (compute_start),
        .compute_busy   (compute_busy),
        .center_re      (cmd_center_re),
        .center_im      (cmd_center_im),
        .step           (cmd_step),
        .max_iter       (cmd_max_iter),
        .rows           (cmd_rows),
        .cols           (cmd_cols),
        .precision_mode (cmd_precision),
        .soft_reset     (soft_reset)
    );

    mandelbrot_multicore #(
        .CORE_COUNT(CORE_COUNT),
        .CORE_FIFO_DEPTH(`CFG_CORE_FIFO_DEPTH),
        .SCHED_MODE(SCHED_MODE),
        .DYNAMIC_OWNER_DEPTH(DYNAMIC_OWNER_DEPTH),
        .WORKER_CONTEXTS(WORKER_CONTEXTS)
    ) u_core (
        .clk            (clk),
        .rst            (rst),
        .ce             (fp_ce),
        .start          (compute_start),
        .busy           (compute_busy),
        .done           (),
        .center_re_in   (cmd_center_re),
        .center_im_in   (cmd_center_im),
        .step_in        (cmd_step),
        .max_iter_in    (cmd_max_iter),
        .rows_in        (cmd_rows),
        .cols_in        (cmd_cols),
        .fifo_data      (fifo_wr_data),
        .fifo_wr        (fifo_wr_en),
        .fifo_full      (fifo_full),
        .tx_start       (tx_ctrl_start),
        .tx_rows        (tx_ctrl_rows),
        .tx_cols        (tx_ctrl_cols)
    );

    // Result FIFO: configured depth x 16 bits
    wire fifo_write_avail;
    assign fifo_full = !fifo_write_avail;

    queue #(.DEPTH(`CFG_OUTPUT_FIFO_DEPTH), .DATA_W(16)) u_fifo (
        .clk         (clk),
        .rst         (rst),
        .write_avail (fifo_write_avail),
        .read_avail  (fifo_rd_avail),
        .write_en    (fifo_wr_en),
        .read_en     (fifo_rd_en),
        .data_in     (fifo_wr_data),
        .data_out    (fifo_rd_data)
    );

    tx_ctrl u_txctrl (
        .clk        (clk),
        .rst        (rst),
        .start      (tx_ctrl_start),
        .rows       (tx_ctrl_rows),
        .cols       (tx_ctrl_cols),
        .done       (tx_ctrl_done),
        .fifo_rd    (fifo_rd_en),
        .fifo_data  (fifo_rd_data),
        .fifo_avail (fifo_rd_avail),
        .tx_data    (tx_data),
        .tx_en      (tx_en),
        .tx_avail   (tx_avail)
    );

    reg [31:0] heartbeat = 32'd0;
    reg [7:0] progress = 8'd0;
    reg [3:2] debug_led_state = 2'd0;
    reg debug_uart_rx_pulse = 1'b0;
    reg debug_uart_tx_pulse = 1'b0;

    wire tx_accepted = tx_en && tx_avail;

    always @(posedge clk) begin
        heartbeat <= heartbeat + 1'b1;
        debug_uart_rx_pulse <= 1'b0;
        debug_uart_tx_pulse <= 1'b0;

        if (rst) begin
            progress <= 8'd0;
        end else begin
            if (compute_start)
                progress <= 8'd0;
            else if (fifo_wr_en && !fifo_full)
                progress <= progress + 1'b1;

            if (rx_avail)
                debug_uart_rx_pulse <= 1'b1;
            if (tx_accepted)
                debug_uart_tx_pulse <= 1'b1;
        end

        debug_led_state[2] <= heartbeat[25];
        debug_led_state[3] <= rst ^ progress[0];
    end

    debug_leds u_debug_leds (
        .clk           (clk),
        .rst           (rst),
        .led_state     (debug_led_state),
        .uart_rx_pulse (debug_uart_rx_pulse),
        .uart_tx_pulse (debug_uart_tx_pulse),
        .led           (led)
    );

endmodule
