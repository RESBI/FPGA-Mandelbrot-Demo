# Mandelbrot FPGA 加速器架构

本文说明当前默认架构。英文原文为 `ARCHITECTURE.md`。

## 1. 总览

当前设计是 UART 控制的流式 Mandelbrot FPGA 加速器。Host 发送完整图像命令，FPGA 返回每个像素的 16 位迭代次数。当前默认配置为 FP64、4 个 worker、每 worker 2 个像素上下文、动态行调度、`FP_CE_DIV=1` 真 100 MHz、12 Mbaud fractional-NCO UART，并使用 tiled response 加 host-driven tile retry 提高长帧可靠性。

| 项目 | 当前值 |
|---|---:|
| 系统时钟 | 100 MHz |
| FP/core enable | 100 MHz，`FP_CE_DIV=1` |
| Worker 数量 | 4 |
| 每 worker 上下文 | 2 |
| 调度器 | `SCHED_MODE=1` 动态空闲 core 行调度 |
| UART | 12000000 baud |
| 像素格式 | little-endian `uint16` |
| 最大迭代 | 65535 |
| 最大已验证图像 | 1920x1080 |
| 当前 timing | `WNS=0.285ns`, `TNS=0.000ns`, `WHS=0.021ns`, `THS=0.000ns` |
| 当前资源 | `13917` LUTs, `14458` registers, `37` DSP48E1, `9.5` BRAM tiles |

## 2. 顶层结构

顶层模块为 `rtl/top.v`。数据路径如下：

```text
Host PC
  -> uart_rx
  -> cmd_parser
  -> mandelbrot_multicore
  -> queue(1024 x 16-bit)
  -> tx_ctrl
  -> uart_tx
  -> Host PC
```

`mandelbrot_multicore` 内部包含：

| 模块 | 作用 |
|---|---|
| `work_dispatch_dynamic_rows` | 把行动态派给空闲 worker。 |
| `mandelbrot_core_worker_2ctx` | 默认 2-context worker。 |
| per-core FIFO | 暂存每个 worker 的行输出。 |
| `raster_collect_dynamic_rows` | 按 row-owner 表恢复 raster order。 |

## 3. 命令和响应协议

FP64 命令长度为 33 字节，FP128 命令长度为 57 字节。字段包括 magic、precision、rows、cols、max_iter、center、step 和 XOR checksum。

Legacy response：

```text
RK rows(u16) cols(u16) payload checksum
```

当前 tiled response：

```text
RT rows(u16) cols(u16)
TD row(u16) col(u16) tile_rows(u16) tile_cols(u16) payload checksum
TD ...
TE rows(u16) cols(u16)
```

所有多字节字段为 little-endian。`TD` checksum 只覆盖 payload，header 通过 magic、尺寸、边界和长度检查保护。

## 4. 时钟和 clock enable

全设计只有一个实际时钟域：100 MHz `sys_clk`。UART、parser、FIFO、TX controller、FP datapath 和 Mandelbrot core 都在同一时钟域。`fp_ce` 仍保留为编译期节流参数，但当前 FP64 默认 `FP_CE_DIV=1`，即每周期推进。

当前 100 MHz 单周期约束已收敛，不再需要 `u_core` multicycle exception。

## 5. FP64 浮点实现

`fp_add.v` 和 `fp_mul.v` 是参数化 FP 单元。实现为 IEEE-like，足够用于本项目 Mandelbrot 负载，但不是完整 IEEE-754：不完整支持 denormal、NaN、Inf 和标准 rounding。

FP64 边界差异来自 RTL truncation 和 Python 软件参考的 round-to-nearest-even 差异。边界附近 Mandelbrot 迭代会放大 sub-ULP 差异，因此少量边界像素不匹配是预期行为。

## 6. Worker pipeline

默认 worker 为 `mandelbrot_core_worker_2ctx`。每个 worker 有一个 FP64 multiplier 和一个 FP64 adder，并维护两个像素上下文。一个上下文等待 FP 结果时，另一个上下文可以向 FP pipeline issue 新操作。

关键点：

| 项目 | 当前值 |
|---|---:|
| `MUL_LAT` | 6 |
| `ADD_LAT` | 7 |
| FP 单元 | 1M + 1A per worker |
| 上下文 | 2 per worker |
| commit | worker-local column order |

旧单 context worker 保留为 regression 路径。实验性 `mandelbrot_core_worker_kctx` 支持 4/8 context 行为仿真，但通用数组式实现 LUT 超量，不能部署在 xc7z010。

## 7. 动态行调度

动态调度器每次把一整行分派给一个空闲 worker，并记录 row owner。collector 按原始行顺序读取对应 worker FIFO，保证 host 看到的输出仍是 raster order。

调度器只在目标 core FIFO 为空时分派下一行。这条规则避免 UART backpressure 下未来行填满 FIFO，而 collector 正等待同一 core 的早期行，造成死锁。

## 8. UART

UART 为 8N1，无硬件流控。当前默认 12 Mbaud，RX 和 TX 都使用 32-bit fractional NCO 产生 bit tick。12 Mbaud 的 bit 时间为 8.333 个 100 MHz 周期，不能用整数 divider 精确表示，因此 fractional NCO 会产生 8/9 cycle 的平均节拍。

12 Mbaud 使理论 payload 上限达到约 `600000 pixels/s`，但 1080p 单帧是约 4.15 MiB 长 burst，host/FT232H/driver 偶发 byte slip。当前推荐用 host-driven tile 降低失败代价。

## 9. Tile response 和 host-driven tile

Tile 方案分两层：

| 层 | 位置 | 作用 |
|---|---|---|
| RTL response tiling | `rtl/tx_ctrl.v` | 把像素流封装为 `RT/TD/TE` packet，并提供 per-packet checksum。 |
| Host-driven compute tiling | `python/mandelbrot_host.py` | 把大图拆成可重试 compute tile，并拼回最终图像。 |

推荐 1080p tile shape 是 `1920x120`。它把一帧分成 9 个 stripe。每个 stripe 失败时只重算 120 行，而不是重算整帧。

当前 `CFG_RESPONSE_TILE_COLS=64`，因此一个 `1920x120` host tile 产生：

```text
120 * ceil(1920 / 64) = 360 TD packets
```

Host 校验 `RT` 维度、`TD` bounds、payload length、payload checksum、像素覆盖和 `TE` 维度。如果失败，host drain serial until quiet、reset input buffer，然后重试该 compute tile。

## 10. Host 软件

`python/mandelbrot_host.py` 负责：

| 功能 | 说明 |
|---|---|
| 命令编码 | 打包 FP64/FP128 参数和 checksum。 |
| 串口传输 | 默认 `COM6`，12 Mbaud。 |
| 响应解析 | 支持 legacy `RK` 和 tiled `RT/TD/TE`。 |
| Host tile | `--tile-width`, `--tile-height`, `--tile-retries`。 |
| 渲染 | 输出 PNG/text。 |
| 验证 | `--verify` 计算 Python reference。 |

## 11. 当前资源

| Resource | Used | Device | Utilization |
|---|---:|---:|---:|
| Slice LUTs | 13917 | 17600 | 79.07% |
| LUT as Logic | 13641 | 17600 | 77.51% |
| LUT as Memory | 276 | 6000 | 4.60% |
| Slice Registers | 14458 | 35200 | 41.07% |
| DSP48E1 | 37 | 80 | 46.25% |
| Block RAM Tile | 9.5 | 60 | 15.83% |

## 12. 已知限制和后续方向

| 限制 | 说明 |
|---|---|
| 12 Mbaud UART | 长 burst 仍可能 byte slip，缺少 packet-level retransmission。 |
| 2-context worker | 只能隐藏部分 FP latency。 |
| generic 4/8ctx | 仿真通过但 LUT 超量。 |
| FP64 | 深 zoom 会受精度影响。 |

后续方向包括更强传输层、packet sequence/request ID、低 LUT 高 context worker、FP128 优化和更强 tile/retry 协议。
