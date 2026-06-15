# UART 波特率 Benchmark

本文对应 `UART_BAUDRATE_BENCHMARK.md`，记录不同 UART baud 下的系统表现。

## 背景

当 compute 性能提升到 4-worker FP64 后，fast scenes 主要受 UART 输出速率限制。理论 payload ceiling：

```text
pixels/s = baud / 10 / 2
```

其中 10 是 8N1 每字节 bit 数，2 是每像素两个 payload byte。

## 历史结果

| Baud | 理论像素上限 | 角色 |
|---:|---:|---|
| 460800 | 23040 pps | 早期稳定 baseline。 |
| 500000 | 25000 pps | 早期 benchmark 点。 |
| 576000 | 28800 pps | 历史稳定默认。 |
| 12000000 | 600000 pps | 当前高性能默认，需要 tile retry。 |

## 576000 阶段结论

Fast escape、standard 等低迭代场景接近 UART ceiling，因此 compute 改进几乎不可见。Deep mini-brot 等 compute-bound 场景仍能体现 worker 优化收益。

## 12 Mbaud 阶段结论

12 Mbaud 显著提高 fast scenes 吞吐，但单个 full-frame burst 可靠性不足。推荐使用 host-driven `1920x120` tile。

当前 12M host-tiled 代表数据：

| Scene | Mean pps |
|---|---:|
| Fast escape @128 | `428068.64` |
| Standard @64 | `466030.04` |
| Seahorse zoom @512 | `118207.86` |
| Deep tendrils @8192 | `61080.26` |
| Deep mini-brot @8192 | `24898.89` |
| Deep Seahorse @1024 | `57056.36` |

## 结论

UART baud 提升是 fast scenes 的关键，但不能只提高 baud。高 baud 下必须配合 packet framing、retry boundary 或更强 transport。
