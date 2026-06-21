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
    input  wire CLK_200_P,
    input  wire CLK_200_N,
    output wire [14:3] LED,
    output wire J1_GREEN,
    output wire J1_RED
);

    wire sys_clk;
    wire clk_fb;
    wire clk_fb_unbuf;
    wire clk_100_unbuf;
    wire clk_locked;

    generate
        if (DIRECT_200MHZ) begin : g_direct_200
            IBUFGDS #(
                .DIFF_TERM("TRUE"),
                .IBUF_LOW_PWR("FALSE"),
                .IOSTANDARD("LVDS")
            ) u_clk_200_ibufgds (
                .I(CLK_200_P),
                .IB(CLK_200_N),
                .O(sys_clk)
            );

            assign clk_locked = 1'b1;
            assign clk_fb = 1'b0;
            assign clk_fb_unbuf = 1'b0;
            assign clk_100_unbuf = 1'b0;
        end else begin : g_mmcm_100
            wire clk_200;

            IBUFDS #(
                .DIFF_TERM("TRUE"),
                .IBUF_LOW_PWR("FALSE"),
                .IOSTANDARD("LVDS")
            ) u_clk_200_ibufds (
                .I(CLK_200_P),
                .IB(CLK_200_N),
                .O(clk_200)
            );

            MMCME2_BASE #(
                .CLKIN1_PERIOD(5.000),
                .CLKFBOUT_MULT_F(5.000),
                .CLKOUT0_DIVIDE_F(10.000),
                .CLKOUT0_DUTY_CYCLE(0.500)
            ) u_clk_mmcm (
                .CLKIN1(clk_200),
                .CLKFBIN(clk_fb),
                .RST(1'b0),
                .PWRDWN(1'b0),
                .CLKFBOUT(clk_fb_unbuf),
                .CLKFBOUTB(),
                .CLKOUT0(clk_100_unbuf),
                .CLKOUT0B(),
                .CLKOUT1(),
                .CLKOUT1B(),
                .CLKOUT2(),
                .CLKOUT2B(),
                .CLKOUT3(),
                .CLKOUT3B(),
                .CLKOUT4(),
                .CLKOUT5(),
                .CLKOUT6(),
                .LOCKED(clk_locked)
            );

            BUFG u_sys_clk_bufg (
                .I(clk_100_unbuf),
                .O(sys_clk)
            );

            BUFG u_clk_fb_bufg (
                .I(clk_fb_unbuf),
                .O(clk_fb)
            );
        end
    endgenerate

    // Clock enable for FP operations
    reg [`FP_CE_DIV-1:0] ce_counter;
    wire fp_ce;
    assign fp_ce = (`FP_CE_DIV == 1) ? 1'b1 : (ce_counter == `FP_CE_DIV - 1);

    always @(posedge sys_clk) begin
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
    assign power_on_rst = !clk_locked || (rst_cnt < 15);
    assign rst = power_on_rst || (soft_rst_cnt != 0);

    always @(posedge sys_clk) begin
        if (!clk_locked)
            rst_cnt <= 0;
        else if (rst_cnt < 15)
            rst_cnt <= rst_cnt + 1;
    end

    always @(posedge sys_clk) begin
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
        .clk        (sys_clk),
        .data       (rx_data),
        .data_avail (rx_avail)
    );

    uart_tx #(
        .CLK_HZ(CLK_HZ)
    ) u_tx (
        .tx             (uart_tx),
        .clk            (sys_clk),
        .data           (tx_data),
        .transmit_en    (tx_en),
        .transmit_avail (tx_avail)
    );

    cmd_parser u_cmd (
        .clk            (sys_clk),
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
        .clk            (sys_clk),
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
        .clk         (sys_clk),
        .rst         (rst),
        .write_avail (fifo_write_avail),
        .read_avail  (fifo_rd_avail),
        .write_en    (fifo_wr_en),
        .read_en     (fifo_rd_en),
        .data_in     (fifo_wr_data),
        .data_out    (fifo_rd_data)
    );

    tx_ctrl u_txctrl (
        .clk        (sys_clk),
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
    reg [14:3] debug_led_state = 12'd0;
    reg debug_uart_rx_pulse = 1'b0;
    reg debug_uart_tx_pulse = 1'b0;

    wire tx_accepted = tx_en && tx_avail;

    always @(posedge sys_clk) begin
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

        debug_led_state[3]  <= heartbeat[25];
        debug_led_state[4]  <= rst;
        debug_led_state[5]  <= progress[0];
        debug_led_state[6]  <= progress[1];
        debug_led_state[7]  <= progress[2];
        debug_led_state[8]  <= progress[3];
        debug_led_state[9]  <= progress[4];
        debug_led_state[10] <= progress[5];
        debug_led_state[11] <= progress[6];
        debug_led_state[12] <= progress[7];
        debug_led_state[13] <= debug_uart_rx_pulse;
        debug_led_state[14] <= debug_uart_tx_pulse;
    end

    debug_leds u_debug_leds (
        .clk           (sys_clk),
        .rst           (rst),
        .led_state     (debug_led_state),
        .uart_rx_pulse (debug_uart_rx_pulse),
        .uart_tx_pulse (debug_uart_tx_pulse),
        .LED           (LED),
        .J1_GREEN      (J1_GREEN),
        .J1_RED        (J1_RED)
    );

endmodule
