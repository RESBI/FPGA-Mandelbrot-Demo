# 架构演进与优化报告摘要

本文是当前演进报告的中文摘要。最新完整英文主文档请以 [ARCHITECTURE_EVOLUTION_REPORT.md](ARCHITECTURE_EVOLUTION_REPORT.md) 为准。

## 当前阶段

项目已经从早期单核 UART renderer、100MHz FP64、XC7K70T direct-200MHz、多 worker/多 context 架构，迁移到当前 VMC_RTSB ZU4EV `24.576 MHz` 分支。

当前最终配置：

| 项目 | 当前值 |
|---|---:|
| FPGA | `xczu4ev-sfvc784-1-i` |
| 时钟 | 单端 `sys_clk`, `24.576 MHz` |
| UART | `6,144,000` baud |
| Host 命令 byte gap | `50 us` |
| Worker / contexts | `12 / 8` |
| 调度 | 动态空闲 worker 行调度 |
| FPU tag latency | `MUL_LAT=6`, `ADD_LAT=9` |
| 六场景结果 | `6/6 PASS`, `0` retries |

## 最新阶段：ZU4EV 24.576 MHz 优化

板级迁移改变了优化目标：旧 XC7K70T direct-200MHz 设计主要受 timing 和 routing 限制；ZU4EV 当前时钟只有 `24.576 MHz`，timing margin 很大，但频率降低 `8.138x`。因此本轮优化重点变成：在资源允许范围内增加 worker/context 并筛选可用 UART 速率。

关键结论：

| 候选 | 结果 | 结论 |
|---|---|---|
| `24 workers / 8 contexts` | RTL 仿真通过，但实现资源 DRC 失败 | LUT 超限，拒绝。 |
| `12 workers / 8 contexts` | build/route/上板/六场景通过 | 当前最终默认。 |
| `14 workers / 4 contexts` | build/route/上板/六场景通过 | 全部六场景慢于 `12/8`，拒绝。 |

UART 筛选结论：`6.144 Mbaud` 是当前项目本体最高已接受速率，但必须使用 `--tx-byte-gap 0.00005`。无 gap 时，33 字节 FP64 命令 burst 会在 PC->FPGA 方向发生错位/丢字节；加 gap 后短命令可靠，图像 payload 仍以高 baud 从 FPGA 返回 host。

pipeline latency 试验结论：简单把 `MUL_LAT` 或 `ADD_LAT` 提前一拍会在大图 RTL 仿真中产生约 `1902` 个 mismatch。当前 worker/FPU 对齐必须保持 `MUL_LAT=6`, `ADD_LAT=9`。真正缩短 latency 需要重构 `fp_mul.v`/`fp_add.v` 并加入专门 scoreboard。

## 最终性能

| 场景 | Transport | Retries | FPGA s | Pixels/s |
|---|---:|---:|---:|---:|
| fast escape @128 | PASS | 0 | `9.587` | `216,288.01` |
| standard @64 | PASS | 0 | `9.622` | `215,498.75` |
| Seahorse zoom @512 | PASS | 0 | `15.192` | `136,492.42` |
| deep tendrils @8192 | PASS | 0 | `27.377` | `75,742.33` |
| deep mini-brot @8192 | PASS | 0 | `71.977` | `28,809.10` |
| deep Seahorse @1024 | PASS | 0 | `31.128` | `66,614.27` |

详细数据和历史阶段请查看英文主报告。
