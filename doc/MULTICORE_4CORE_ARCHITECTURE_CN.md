# 4-Core Mandelbrot 架构

本文对应 `MULTICORE_4CORE_ARCHITECTURE.md`，说明 4-worker FP64 架构。

## 架构

4-core 版本复制四个 Mandelbrot worker，并通过调度器分配行：

```text
cmd_parser
  -> mandelbrot_multicore
      -> work_dispatch_static_rows 或 work_dispatch_dynamic_rows
      -> worker0..worker3
      -> per-core FIFO
      -> raster merge/collect
      -> output FIFO
      -> tx_ctrl
```

## Static 4-core

最早实现使用 interleaved rows：worker 0 处理 0,4,8... 行，worker 1 处理 1,5,9... 行，以此类推。这样可以在相邻行相似的 Mandelbrot 图像中获得较好负载均衡。

## Dynamic 4-core

后续加入 dynamic row scheduler。空闲 worker 获取下一行，collector 用 row-owner table 按原始行顺序输出。为了避免 UART backpressure deadlock，dynamic scheduler 只在目标 core FIFO 为空时复用该 core。

## 资源和 timing

历史 4-core stage：

| Resource | Used | Available | Utilization |
|---|---:|---:|---:|
| Slice LUTs | 8597 | 17600 | 48.85% |
| Slice Registers | 9807 | 35200 | 27.86% |
| Block RAM Tile | 8.5 | 60 | 14.17% |
| DSP48E1 | 38 | 80 | 47.50% |

Final timing：`WNS=0.224ns`, `TNS=0.000ns`, `WHS=0.005ns`, `THS=0.000ns`。

## 性能

4-core 对 compute-bound 场景接近 `3.5x-3.6x` 提升。Fast scenes 受 UART 限制，收益较小。

## 结论

4-core 是当前设计的重要中间点。它保持原有 host 协议不变，同时把 compute-heavy 场景推近 UART ceiling，为后续 2-context 和高波特率工作奠定基础。
