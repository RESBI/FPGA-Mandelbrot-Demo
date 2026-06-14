# TODO

本文对应 `TODO.md`，列出后续工作方向。

## Transport

| 工作 | 原因 |
|---|---|
| `TD` sequence ID | 明确检测丢包、重复包和顺序错误。 |
| Request ID | 防止失败 tile 的迟到数据污染下一次请求。 |
| ACK/retry | 重传单个 packet，而不是 recompute whole host tile。 |
| 更强 transport | USB FIFO、Ethernet、SPI 或 Zynq PS memory-mapped interface。 |

## Compute

| 工作 | 原因 |
|---|---|
| 低 LUT 4ctx worker | generic kctx 仿真通过但 LUT 超量。 |
| 8ctx/16ctx `1M+1A` | 先增加 contexts 才能减少 FP pipeline bubbles。 |
| 16ctx 后评估 `1M+2A` | 低 context 下第二 ADD 无收益。 |
| 避免 `2M+1A` | 单 ADD 仍是瓶颈，第二 MUL 浪费。 |

## Verification

| 工作 | 原因 |
|---|---|
| 更多小图/中图 regression | 捕捉 context/tag/ordered commit bug。 |
| 更长 12M soak | 验证 host tile retry 长时间稳定性。 |
| FP128 保守路径 | 不影响默认 FP64 高性能路径。 |

## Documentation

保持英文主文档和 `_CN.md` 中文文档同步，历史数据归入架构演进文档，当前数据只放在 README/ARCHITECTURE 当前状态表中。
