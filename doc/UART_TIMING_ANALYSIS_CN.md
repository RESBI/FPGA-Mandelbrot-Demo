# UART 时序分析

本文对应 `UART_TIMING_ANALYSIS.md`，说明 UART RX/TX 的采样、波特率误差和 fractional NCO 改进。

## UART 基本参数

| 项目 | 当前值 |
|---|---:|
| 格式 | 8N1 |
| 系统时钟 | 100 MHz |
| 当前 baud | 12000000 |
| RX/TX tick | 32-bit fractional NCO |
| 硬件流控 | 无 |

## 旧整数 divider 问题

整数 `CLOCKS_PER_BIT = CLK_HZ / BAUD` 只能表示整数周期 bit time。当目标 baud 不能整除 100 MHz 时，实际 baud 与 host baud 发生偏差。低 baud 下误差相对可接受，高 baud 下采样窗口变小，误差会快速吞掉 margin。

## RX 采样风险

UART RX 必须在 start bit 后接近每个 data bit 中心采样。旧实现缺少 oversampling 和 majority vote，因此高 baud 下更容易受以下因素影响：

| 因素 | 影响 |
|---|---|
| baud quantization | bit center 漂移。 |
| host USB-UART 实际 baud 偏差 | 与 FPGA divider 偏差叠加。 |
| start-bit 检测误差 | 后续 8 个 bit 采样点整体偏移。 |
| Windows/USB latency | 不直接影响 bit-level，但影响长 burst 接收稳定性。 |

## Fractional NCO 改进

NCO 不要求 bit time 是整数周期。以 12 Mbaud 为例，tick 在 8 和 9 个 cycle 之间抖动，但平均 bit time 正确。

RX 还加入 half-bit start validation，降低 false start 风险。

## 当前限制

Fractional NCO 解决了 baud 精度，但没有提供可靠传输层。长 1080p burst 仍可能因 host/USB/driver receive starvation 或 byte slip 导致失败。当前通过 `RT/TD/TE` packet 和 host tile retry 降低失败代价。

## 后续改进

| 改进 | 价值 |
|---|---|
| RX oversampling | 增大 bit-level margin。 |
| Packet sequence ID | 明确检测丢包/重复包。 |
| Request ID | 防止 stale response 被误收。 |
| ACK/retry | 重传 packet 而不是 recompute host tile。 |
| 更强 transport | 从根本上消除 UART 长 burst 瓶颈。 |
