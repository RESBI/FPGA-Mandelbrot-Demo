# UART 波特率调查

本文对应 `UART_BAUDRATE_INVESTIGATION.md`，总结 UART baudrate 从保守低速到 12 Mbaud fractional NCO 的调查过程。

## 背景

早期设计使用整数 `CLOCKS_PER_BIT` divider。该方案在低 baud 下稳定，但当 baud 不是 100 MHz 的整数约数时会产生量化误差。随着 FPGA compute 性能提升，UART 成为 fast scenes 的主要瓶颈。

## 关键发现

| 阶段 | 发现 |
|---|---|
| 460800/500000 baud | 可稳定运行，但 1080p fast scenes 被 UART ceiling 限制。 |
| 576000 baud | 标准 PC baud，整数 divider 路径稳定，成为历史默认。 |
| 625000+ baud integer divider | TX-only 可工作，但 full protocol 失败，主要问题在 RX uplink。 |
| Fractional NCO | 解决 100 MHz 与目标 baud 不整除的问题。 |
| 12 Mbaud | 小图 gate 通过，1080p throughput 大幅提升，但长 burst 可靠性成为新瓶颈。 |

## Integer Divider 结论

早期 sweep 表明，某些 baud 虽然 FPGA TX 可以发送，但完整 command/response 失败。这说明问题不只是 host 接收，而是 FPGA RX 在高 baud 下缺少足够采样裕量。

TX-only pattern 实验证明 FPGA TX 在更高 baud 下可以被 host 正确接收；失败主要来自 RX uplink 的 start-bit/采样误差。

## Fractional NCO 方案

当前 UART RX/TX 使用：

```text
BAUD_INC = round(BAUD * 2^ACC_WIDTH / CLK_HZ)
```

12 Mbaud 下，一个 bit 是 `100 MHz / 12 MHz = 8.333...` 个周期。NCO 产生 8/9 cycle 混合 tick，长期平均 baud 准确。

## 当前建议

| Baud | 角色 |
|---:|---|
| 12000000 | 当前默认实验高性能配置，配合 host-driven tile 使用。 |
| 8000000 | 较稳 high-baud fallback。 |
| 576000 | 保守历史 baseline。 |

## 结论

波特率问题已经从“bit timing 精度”转移到“multi-megabyte burst 可靠性”。12 Mbaud 需要 tile packet 和 host retry 边界。长期更优方案是 USB FIFO、Ethernet 或 Zynq memory-mapped transport。
