# 原始设计说明

本文对应 `DESIGN.md`，保留早期设计思想的中文摘要。

## 初始目标

项目目标是实现一个可以通过 PC 控制的 FPGA Mandelbrot renderer：

1. Host 发送图像参数。
2. FPGA 计算每个像素的 escape iteration。
3. FPGA 通过 UART 返回像素流。
4. Host 渲染 PNG 或文本图像。

## 初始架构

早期架构非常直接：

```text
uart_rx -> cmd_parser -> mandelbrot_core -> queue -> tx_ctrl -> uart_tx
```

`mandelbrot_core` 使用一个 FP multiplier 和一个 FP adder，通过 FSM 分时执行 Mandelbrot 迭代。

## 关键设计选择

| 选择 | 原因 |
|---|---|
| UART | 易调试，Python 易驱动。 |
| Raster-order stream | Host 简单，无需坐标 packet。 |
| Streaming output | FPGA 不需要存整帧。 |
| FP64 | 支持实用 zoom。 |
| 简单 FSM | 初期 correctness 和 timing 容易控制。 |

## 后续演进

该早期设计后来演进为：

| 阶段 | 改进 |
|---|---|
| True 100 MHz | FP add/mul pipeline cut。 |
| 4-worker | 并行计算多行。 |
| Dynamic scheduler | 空闲 core 动态取行。 |
| 2-context worker | worker 内部去气泡。 |
| Fractional UART | 12 Mbaud 高速串口。 |
| Tiled response | packet checksum + host tile retry。 |

## 当前状态

当前默认设计已远超原始版本，但仍保持最初几个核心原则：流式输出、host 可验证、RTL 不存整帧、协议尽量简单。
