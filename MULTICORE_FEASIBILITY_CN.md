# 多核可行性分析

本文对应 `MULTICORE_FEASIBILITY.md`，总结从单 worker 扩展到多 worker 的资源和协议可行性。

## 目标

评估在 Zynq-7010 上复制多个 FP64 Mandelbrot worker 是否可行，以及在 UART 输出约束下是否有系统收益。

## 资源模型

单个 FP64 multiplier-heavy worker 消耗较多 DSP。经验模型约为每 worker 9 个 DSP，加上少量共享开销。

| Worker 数 | DSP 估计 | 结论 |
|---:|---:|---|
| 1 | 约 10 | 轻量。 |
| 4 | 约 38 | 适合 80 DSP 目标器件。 |
| 8 | 约 74+ | DSP 接近上限，routing/timing 风险高。 |

## 输出顺序约束

Host 协议期望 raster-order 像素流。如果多个 worker 并行计算，必须在 FPGA 内部恢复输出顺序，否则 host 会把像素写到错误位置。

可选策略：

| 策略 | 说明 |
|---|---|
| Static interleaved rows | 每个 worker 处理固定 row stride。实现简单。 |
| Dynamic rows | 空闲 worker 获取下一行，需要 row-owner table。 |
| Tagged output | 输出带坐标，需要协议升级。 |

## 结论

4-worker 是当前器件和 UART 协议下的合理点。它显著提升 compute-bound 场景，同时不需要改变 host-visible raster stream。更多 worker 在 UART 限制下收益有限，且资源/timing 风险高。
