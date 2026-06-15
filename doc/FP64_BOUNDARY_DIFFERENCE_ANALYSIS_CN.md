# FP64 边界差异分析

本文对应 `FP64_BOUNDARY_DIFFERENCE_ANALYSIS.md`，解释 FPGA FP64 与 Python reference 在 Mandelbrot 边界附近的少量差异。

## 背景

FPGA 浮点单元是 IEEE-like 实现，并非完整 IEEE-754。Python 使用硬件 double，通常是 round-to-nearest-even。RTL 中某些路径更接近 truncation/round-toward-zero。

Mandelbrot 边界具有混沌特性，sub-ULP 差异可能在多次迭代后放大，导致某些像素的 escape iteration 不同。

## 差异来源

| 来源 | 说明 |
|---|---|
| Rounding mode | Python RNE vs RTL truncation。 |
| Normalization 简化 | RTL 未实现完整 IEEE corner cases。 |
| Chaotic amplification | 边界附近初始微小误差会改变 escape 时间。 |
| Deep zoom | step 很小时坐标差异更敏感。 |

## 如何判断是否为传输错误

| 现象 | 解释 |
|---|---|
| 少量边界像素 mismatch | 通常是数值差异，可接受。 |
| 大量连续错位 | 更可能是 transport byte slip 或 parser 问题。 |
| checksum mismatch | transport 错误，不是 FP 差异。 |
| 小图 deterministic mismatch | 需要检查 ../RTL/host coordinate 或 FP bug。 |

## 结论

少量边界差异是当前 FP64 实现的预期行为，不影响视觉图像质量。验证时应区分数值边界差异和传输完整性错误。Transport pass 的标准是 frame/packet checksum、尺寸、bounds 和 payload 完整；`--verify` 的 pixel match 不一定需要在复杂边界场景达到 100%。
