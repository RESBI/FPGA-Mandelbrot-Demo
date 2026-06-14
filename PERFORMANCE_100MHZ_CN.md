# 100 MHz 性能报告

本文对应 `PERFORMANCE_100MHZ.md`，总结 FP64 datapath 从有效 50 MHz 到 true 100 MHz 的迁移。

## 问题

早期稳定设计使用 100 MHz 物理时钟，但通过 `FP_CE_DIV=2` 让 FP/core 每两个周期推进一次。直接改为 `FP_CE_DIV=1` 后 timing 严重失败。

| 尝试 | 结果 |
|---|---:|
| 旧有效 50 MHz | timing pass |
| 直接 true 100 MHz | `WNS=-4.626ns`, `TNS=-593.205ns` |
| adder pipeline cut | `WNS=-1.221ns` |
| adder + multiplier cuts | `WNS=0.258ns` |

## 解决方法

对 FP add/mul datapath 做 pipeline cut：

| 单元 | 改动 |
|---|---|
| `fp_add` | 在 decode/compare、alignment/add、normalize/output 之间切分长组合路径。 |
| `fp_mul` | 注册 decoded mantissa、DSP product 和 metadata。 |

核心原则：通过 datapath pipeline 解决 timing，而不是长期依赖 multicycle exceptions。

## 性能影响

Compute-bound 1080p 场景提升约 `1.40x-1.41x`。低迭代 fast scenes 受 UART 限制，提升较小。

代表结果：

| Scene | Effective 50 MHz | True 100 MHz | Speedup |
|---|---:|---:|---:|
| Deep tendrils @8192 | `478.776s` | `340.055s` | `1.41x` |
| Deep mini-brot @8192 | `1198.049s` | `850.711s` | `1.41x` |
| Deep seahorse @1024 | `511.486s` | `363.254s` | `1.41x` |

## 结论

True 100 MHz 是后续 4-worker、2-context 和 12M transport 的基础。它证明了该设计应通过明确 pipeline stage 收敛 timing。
