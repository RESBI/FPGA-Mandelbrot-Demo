# 架构演进与优化报告

本文是 `ARCHITECTURE_EVOLUTION_REPORT.md` 的中文版本，概述项目如何从最初单核 UART renderer 演进到当前 4-worker、2-context、12 Mbaud host-tiled FP64 设计。

## 当前最终状态

| 项目 | 当前值 |
|---|---:|
| FPGA | Xilinx Zynq-7010 `xc7z010clg400-1` |
| 系统时钟 | 100 MHz |
| 浮点模式 | FP64 |
| Worker | 4 |
| 每 worker context | 2 |
| 调度器 | 动态空闲 core 行调度 |
| UART | 12000000 baud fractional NCO |
| Host 协议 | raster order response，当前使用 tiled response |
| 最大已验证帧 | 1920x1080 |
| 当前 timing | `WNS=0.285ns`, `TNS=0.000ns`, `WHS=0.021ns`, `THS=0.000ns` |
| 当前资源 | 13917 LUTs, 14458 registers, 37 DSP48E1, 9.5 BRAM tiles |

## 初始设计思想

最初目标不是最大理论吞吐，而是一个容易 bring-up、容易调试、能端到端生成图像的 FPGA 加速器。因此早期选择了：

| 优先级 | 设计选择 | 原因 |
|---|---|---|
| 简单调试 | UART command/response | Python 和串口工具容易驱动。 |
| 低存储 | 流式输出像素 | 不需要在 FPGA 上存整帧。 |
| 可验证 | raster order stream | Host 可直接渲染和比对。 |
| RTL 可控 | 单 Mandelbrot FSM + 1M + 1A | 面积小，latency 明确。 |
| 精度 | FP64 默认 | 支持实用 deep zoom。 |

## 阶段 1：正确性和流式可靠性

早期修复包括 FP add/mul corner case、escape 调度、坐标约定、TX FIFO read wait、32-bit pixel count 和 UART TX 单时钟域化。

结果：FP unit simulation、core simulation、host reference、硬件 smoke test 和小图 verify 均通过。

## 阶段 2：true 100 MHz FP64

早期稳定设计使用 100 MHz 物理时钟，但 FP/core 每两个周期推进一次。直接改为 `FP_CE_DIV=1` 时 timing 失败：

| 尝试 | 结果 |
|---|---:|
| 直接 true 100 MHz | `WNS=-4.626ns`, `TNS=-593.205ns` |
| adder cut 后 | `WNS=-1.221ns` |
| adder + multiplier pipeline cut 后 | `WNS=0.258ns` |

compute-bound 场景提升约 `1.40x-1.41x`，但 fast scenes 很快暴露 UART 输出瓶颈。

## 阶段 3：UART 波特率优化

整数 divider 阶段选择了 576000 baud 作为稳定 baseline。关键结论：

| Baud | 结果 | 说明 |
|---:|---|---|
| 500000 | pass | exact divider。 |
| 576000 | pass | 标准 PC baud，稳定。 |
| 625000+ | TX-only pass，但 full protocol fail | 问题在 FPGA RX uplink。 |

576000 baud 将 payload ceiling 提升到约 `28800 pixels/s`。

## 阶段 4：多核可行性

资源模型显示 4 个 FP64 worker 可以放入 xc7z010。单个 FP64 multiplier-heavy worker 大约消耗 9 个 DSP，4-worker 设计约 38 DSP，适合 80 DSP 的目标器件。

## 阶段 5：4-core 实现

实现 4 个 worker、静态 interleaved rows、per-core FIFO 和 raster merger。4-core timing 最终通过：

| Metric | Value |
|---|---:|
| WNS | `0.224ns` |
| TNS | `0.000ns` |
| WHS | `0.005ns` |
| THS | `0.000ns` |

资源：8597 LUTs、9807 registers、38 DSP48E1、8.5 BRAM tiles。compute-bound 1080p 场景相比 single-core 提升约 `3.5x-3.6x`。

## 阶段 6：动态行调度

加入 `SCHED_MODE=1` 动态空闲 core 行调度和 `raster_collect_dynamic_rows`。实测六个 1080p 场景与静态模式几乎相同，说明当时瓶颈主要不是 row-level tail imbalance，而是 UART 和 worker 内部 FP latency。

## 阶段 7：2-context worker 去气泡

实现 `mandelbrot_core_worker_2ctx`，每 worker 保持两个像素上下文，用 tagged FP writeback 处理 delayed results，并在写 per-core FIFO 前按列顺序 commit。

关键细节：

| 细节 | 原因 |
|---|---|
| FP result tag | back-to-back issue 后必须把结果写回正确 context。 |
| 实际 tag latency | `MUL_LAT=6`, `ADD_LAT=7`，不是旧 `PIPE_WAIT+1=11`。 |
| Ordered commit | context 完成可乱序，但 FIFO 必须保持行内顺序。 |

历史 2ctx integration timing/resource：

| Metric | Value |
|---|---:|
| WNS | `0.091ns` |
| TNS | `0.000ns` |
| WHS | `0.011ns` |
| THS | `0.000ns` |
| Slice LUTs | `13630 / 17600` |
| Slice Registers | `14391 / 35200` |
| DSP48E1 | `38 / 80` |

## 阶段 8：动态 backpressure 修复

大帧 UART-bound 场景曾在 dynamic scheduler 下死锁。修复方式：只有当目标 core FIFO 为空时才分配下一行。这样避免 future rows 填满 FIFO，而 collector 正等待同一 core 的 earlier row。

## 阶段 9：12 Mbaud fractional UART

将 UART RX/TX 从整数 divider 改为 fractional NCO。12 Mbaud 的 bit period 是 8.333 个 100 MHz cycle，NCO 通过 8/9 cycle 混合保持平均 baud。

12 Mbaud 单 burst 六场景结果显示 fast scenes 达到 `443k-493k pps`，但 full-frame 4.15 MiB 长 burst 偶发 tail timeout，说明瓶颈从 baud 精度转移到 host/FT232H/driver 长 burst 可靠性。

## 阶段 10：Tiled response 和 host-driven stripe retry

RTL 增加 `RT/TD/TE` response packet。Host 增加 `--tile-width`、`--tile-height`、`--tile-retries`，把大图拆为可重试 compute tile。

推荐 1080p 模式为 `1920x120`，每帧 9 个 stripe。六场景各 5 次的 30-run stability sweep 全部 transport pass，出现的两个 checksum error 均通过 tile retry 恢复。

当前 tiled build timing/resource：

| Metric | Value |
|---|---:|
| WNS | `0.285ns` |
| TNS | `0.000ns` |
| WHS | `0.021ns` |
| THS | `0.000ns` |
| Slice LUTs | `13917 / 17600` (`79.07%`) |
| Slice Registers | `14458 / 35200` (`41.07%`) |
| DSP48E1 | `37 / 80` (`46.25%`) |
| Block RAM Tile | `9.5 / 60` (`15.83%`) |

## 主要经验

| 经验 | 说明 |
|---|---|
| 流式设计是正确起点 | 低存储、易验证，后续可插入多核和 tile。 |
| 协议既是优势也是约束 | raster order 简化 host，但限制 out-of-order 扩展。 |
| timing 要靠 datapath pipeline | multicycle constraint 不是长期方案。 |
| 4 worker 适合 576k 阶段 | 更多 worker 会受 UART 限制。 |
| 2ctx 证明了 tagged worker | 但仍远未填满 FP pipeline。 |
| 12 Mbaud 后深场景重新 compute-sensitive | fast scenes 仍受 output/host 限制。 |
| generic 4/8ctx 不可部署 | LUT 超量，需要低 LUT 专用实现。 |

## 后续方向

优先级：更强传输层、packet sequence/request ID、低 LUT 4/8ctx worker、16ctx 后再评估第二 adder，最后才考虑更多 multiplier。
