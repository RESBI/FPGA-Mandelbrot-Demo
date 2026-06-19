# 架构演进与优化报告

本文是 `ARCHITECTURE_EVOLUTION_REPORT.md` 的中文版本，概述项目如何从最初单核 UART renderer 演进到当前 4-worker、4-context、12 Mbaud host-tiled FP64 默认设计。

## 当前最终状态

| 项目 | 当前值 |
|---|---:|
| FPGA | Xilinx Kintex-7 `xc7k70tfbg676-1` |
| 板级时钟输入 | 200 MHz 差分 `CLK_200_P/N` |
| 内部系统时钟 | MMCM 生成的 100 MHz `sys_clk` |
| 当前系统时钟 | direct 200 MHz，`DIRECT_200MHZ=1` |
| 100MHz 参考构建 | `build_fp64_100mhz.tcl` |
| 浮点模式 | FP64 |
| Worker | 4 |
| 每 worker context | 4 |
| 历史低 LUT context | 2 |
| 调度器 | 动态空闲 core 行调度 |
| UART | 12000000 baud fractional NCO |
| 默认串口 | `COM9` |
| 烧录链路 | Vivado `hw_server` 在 `127.0.0.1:3122`，CH347 XVC 在 `127.0.0.1:2542` |
| Host 协议 | raster order response，当前使用 tiled response |
| 最大已验证帧 | 1920x1080 |
| 当前 XC7K70T 板级状态 | 完整 FP64 bitstream 已通过 |
| 当前 XC7K70T timing/resource | `WNS=0.015ns`, `TNS=0.000ns`; 20288 LUTs, 17202 registers, 37 DSP48E1, 9.5 BRAM tiles |
| direct-200MHz timing/resource | `WNS=0.015ns`, `TNS=0.000ns`; 20288 LUTs, 17202 registers, 37 DSP48E1, 9.5 BRAM tiles |
| 历史 2ctx XC7K70T timing/resource | `WNS=1.148ns`, `TNS=0.000ns`; 13726 LUTs, 14559 registers, 37 DSP48E1, 9.5 BRAM tiles |

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

## 阶段 11：N-context worker 实验与 XC7K70T 4ctx 验证

在 2-context worker 成为 timing-clean 设计后，曾评估继续增加 worker 内 context 数，以隐藏更多 FP latency。相关实验在 xc7z010 上不可部署，但迁移到更大的 XC7K70T 后，4ctx generic worker 已经可以构建、烧录并通过板级测试，现在是默认配置。

第一组是 generic K-context scoreboard worker，`mandelbrot_core_worker_kctx`。它把 2ctx 的 tagged writeback 推广到 4/8ctx，行为仿真可通过，但 LUT 成本不可接受：

| Case | 行为仿真 | Slice LUTs | 结果 |
|---|---:|---:|---|
| 当前 2ctx 专用 worker | board baseline | `13917 / 17600` (`79.07%`) | timing-clean 默认设计 |
| Generic 4ctx scoreboard | PASS, 192 pixels | `37350 / 17600` (`212.22%`) | 不可布局 |
| Generic 8ctx scoreboard | PASS, 192 pixels | `71462 / 17600` (`406.03%`) | 不可布局 |

XC7K70T 上 4ctx 版本变为可部署：

| Case | Target | Timing | Slice LUTs | Registers | DSPs | 板级结果 |
|---|---|---:|---:|---:|---:|---|
| Generic 4ctx scoreboard | XC7K70T | `WNS=0.583ns` | `36367 / 41000` (`88.70%`) | `19149 / 82000` (`23.35%`) | `37 / 240` (`15.42%`) | timing-clean 默认，`160x120` verify PASS |
| 历史 2ctx worker | XC7K70T | `WNS=1.148ns` | `13726 / 41000` (`33.48%`) | `14559 / 82000` (`17.75%`) | `37 / 240` (`15.42%`) | timing-clean 低 LUT 对照，`160x120` verify PASS |

4ctx bitstream 使用 `build_fp64_contexts.tcl 4` 构建，烧录文件为 `fp64_ctx4_proj/mandelbrot_fp64_ctx4.runs/impl_1/top.bit`。小图 gate 为 `160x120`、`--verify`、`19200/19200` match (`100.00%`)，FPGA elapsed `0.091s`。

12 Mbaud、`1920x120` host/compute tile 的 1080p 单次测试结果：

| Scene | 历史 2ctx FPGA s | 默认 4ctx FPGA s | 4ctx pps | 4ctx vs 2ctx |
|---|---:|---:|---:|---:|
| Fast escape @128 | `5.127` | `4.683` | `442824.20` | `1.09x` |
| Standard @64 | `4.731` | `5.782` | `358640.05` | `0.82x` |
| Seahorse zoom @512 | `19.440` | `9.836` | `210825.06` | `1.98x` |
| Deep tendrils @8192 | `37.326` | `17.677` | `117303.25` | `2.11x` |
| Deep mini-brot @8192 | `83.561` | `44.146` | `46971.46` | `1.89x` |
| Deep Seahorse @1024 | `36.626` | `19.965` | `103861.51` | `1.83x` |

这个结果更新了早期结论：generic K-context 在小 xc7z010 上不可部署，但 4ctx 在 XC7K70T 上可部署。它仍不是理想长期形态，因为 `88.70%` LUT 占用说明宽 context array、operand mux、writeback demux 和 scan 仍然很贵。后续 8/12/16ctx 应转向低 LUT explicit-slot 或 barrel/ring worker。

第二组是 ring/lookahead 方向。模型显示 `4ctx ring_la4` 有潜力恢复 rigid ring 的性能损失，但最小 RTL 尝试是在 generic kctx 上加入 lookahead 窗口，仍保留 generic FP64 context arrays 和宽 mux/writeback fabric，结果不可部署：

| Case | 行为仿真 | 实现结果 |
|---|---:|---|
| `4ctx LA1` generic lookahead | PASS, 192 pixels, `497905 ns` | 可生成 bitstream，但 timing failed：`WNS=-0.271ns`, `TNS=-3.574ns` |
| `4ctx LA2` generic lookahead | PASS, 192 pixels, `468745 ns` | LUT 超量：synth `25194 / 17600` Slice LUTs (`143.15%`) |
| `4ctx LA4` generic lookahead | PASS, 192 pixels, `444355 ns` | LUT 超量：synth `39025 / 17600` Slice LUTs (`221.73%`) |
| `8ctx LA4` generic lookahead | PASS, 192 pixels, `328325 ns` | 4ctx 已失败，因此未继续实现 |

因此没有进行新 4ctx lookahead 的 1080p 板级测试：没有合适的 timing-clean 候选 bitstream。当前决策是默认使用 timing-clean XC7K70T 4ctx generic worker，把 2ctx worker 作为低 LUT 对照；旧 ring/lookahead 新方案放弃，仅在 `CONTEXT_WORKER_ARCHITECTURE_REPORT.md` / `_CN.md` 中保留分析数据。

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

## 阶段 12：Compute tile retry、soft reset 与 N-context 规划

Host tile retry 仍会重算较大的 stripe，且失败后的 stale bytes 可能让 host/FPGA 链路暂时不同步。当前 host 失败时记录 compute tile 坐标、drain stale bytes、发送 UART soft reset 命令 `RST!RST!`，然后只重算该 compute tile。默认 compute tile 现在等于 host tile 本身，1080p 为 `1920x120`，compute 宽度上限为 4096；需要更小 retry unit 时可显式传 `--compute-tile-width` / `--compute-tile-height`。`--quiet` 也增加了 compute tile / host tile 单行进度条。

当前 2-context worker 的 RTL 形态是 tagged two-entry scoreboard：两份像素 context 状态共享一个 FP64 multiplier 和一个 FP64 adder，operation/context tag 通过 latency-matched delay line 返回，最后按列顺序 ordered commit。这是已经部署验证的最小正确实现，但 LUT 成本主要来自 FP64 operand mux、writeback demux、in-flight check 和 ordered commit，而不是 DSP 复制。

Generic 4/8-context 实验证明功能方向可行，但直接把 scoreboard 参数化会导致 wide mux 和 context scan 过大，在 xc7z010 上 LUT 超量；XC7K70T 4ctx 虽然可部署，但 LUT 占用很高。后续推荐低 LUT N-context worker 采用 CPU-like barrel/ring 思路：N 个固定 slot 保存像素状态，round-robin issue pointer 选择当前 slot，FP 结果按 `MUL_LAT` / `ADD_LAT` delayed return pointer 写回固定 slot，并通过 ordered result ring 保持 FIFO 顺序。

## 阶段 13：direct-200MHz 4ctx 时序收敛

100MHz 4ctx 默认设计验证后，下一个问题是能否直接使用板上 200MHz 输入作为完整 compute/UART 时钟。初始直接切换失败，主要瓶颈不是单纯 FP 算术，而是 `mandelbrot_core_worker_kctx` 中 context scan、launch/commit 控制、64-bit FPU operand mux 和 per-context 状态更新的 route-dominated 路径。

本阶段当时的规则：当时默认 100MHz 4ctx 不被破坏；200MHz 使用独立 `build_fp64_200mhz.tcl`；RTL 控制改动先跑行为仿真；timing-failing bitstream 不烧录；timing-clean 但 HW/SW verify 失败也不能作为有效性能点。

被否定但有价值的尝试：

| 尝试 | 结果 | 经验 |
|---|---|---|
| 首个 `C_CHECK_ITER` timing-clean 版本 | `WNS=0.001ns`，但硬件 `17200/19200` match | timing-clean 不代表功能正确。 |
| state-qualified issue gating / ready clear | timing 变差 | 把 `c_state` 条件放回 issue mux 会重新拉长热路径。 |
| 本地 issue round-robin pointer | 行为仿真过，`WNS=-0.374ns` | 简化概念调度不等于减少实际 routing/control。 |
| operand-latched request slicing | 行为过，post-route phys-opt `WNS=-0.042ns` | 锁存 64-bit operand 会把 timing endpoint 移到 request regs。 |
| 简单 `MUL_LAT/ADD_LAT +1` | 功能仍失败 | 问题是精确 tag/result pulse 对齐，不是简单多等一拍。 |

最终采用的 200MHz 时序设计：

```text
Cycle N:   扫描 ready context，只锁存 req_valid / req_op / req_ctx
Cycle N+1: 根据 req_ctx / req_op 驱动 64-bit FPU operand，并送入 tag pipe
Cycle N+latency: tag 返回，result 写回对应 context
```

例子：

```text
N:   context 2 有 MOP_ZRZI ready，mul_req_op=MOP_ZRZI，mul_req_ctx=2
N+1: mul_a=c_z_re[2]，mul_b=c_z_im[2]，mul_op_pipe[0]=MOP_ZRZI，mul_ctx_pipe[0]=2
N+6: mul_done_op=MOP_ZRZI，mul_done_ctx=2，mul_result 写入 c_z_re_z_im[2]
```

功能修复的关键是重新实测 request-sliced FPU latency。`fp_add` 保持 `ADD_LAT=9`，但 `fp_mul` 在 request-sliced worker 中需要 `MUL_LAT=6`。使用 `MUL_LAT=7/8` 会在部分高迭代边界像素抓到下一拍 0，导致本应 escape 的像素输出 `max_iter`。

最终 200MHz kctx 常量：

```verilog
localparam MUL_LAT = 6;
localparam ADD_LAT = 9;
```

验证链路：

| Gate | 结果 |
|---|---|
| worker-only row 0，`160x12`, `max_iter=256` | PASS，160 pixels |
| worker-only row 9，`160x12`, `max_iter=256` | PASS，160 pixels |
| multicore dynamic，`160x12`, `CORE_FIFO_DEPTH=4096` | PASS，1920 pixels |
| multicore dynamic，`160x120`, `CORE_FIFO_DEPTH=4096` | 运行到 10240/19200 pixels 未见 mismatch，仿真时间到 |
| routed timing | `WNS=0.015ns`, `TNS=0.000ns`, `WHS=0.002ns`, `THS=0.000ns` |
| 板级小图 | `19200/19200` exact match，FPGA elapsed `0.158s` |
| 1080p 稳定性 | 六场景各 10 轮，共 60/60 transport pass |

direct-200MHz 10 轮结果：

| 场景 | Pass | Retry | 平均 FPGA s | 平均 pps | 对比 100MHz 4ctx |
|---|---:|---:|---:|---:|---:|
| fast escape @128 | `10/10` | `6` | `5.072` | `413592.02` | `0.923x` |
| standard @64 | `10/10` | `6` | `5.066` | `414046.70` | `1.141x` |
| Seahorse zoom @512 | `10/10` | `6` | `7.879` | `273303.15` | `1.248x` |
| deep tendrils @8192 | `10/10` | `3` | `12.820` | `162504.12` | `1.379x` |
| deep mini-brot @8192 | `10/10` | `2` | `31.625` | `65709.99` | `1.396x` |
| deep Seahorse @1024 | `10/10` | `0` | `13.886` | `149325.97` | `1.438x` |

结论：direct-200MHz 是有效性能点，现在已作为仓库默认构建。相对 100MHz 4ctx，它在 fast escape 场景更慢，在 standard 和深场景提升 `1.14x-1.44x`。100MHz 4ctx 保留为显式参考构建。

## 主要经验

| 经验 | 说明 |
|---|---|
| 流式设计是正确起点 | 低存储、易验证，后续可插入多核和 tile。 |
| 协议既是优势也是约束 | raster order 简化 host，但限制 out-of-order 扩展。 |
| timing 要靠 datapath pipeline | multicycle constraint 不是长期方案。 |
| 4 worker 适合 576k 阶段 | 更多 worker 会受 UART 限制。 |
| 2ctx 证明了 tagged worker | 但仍远未填满 FP pipeline。 |
| 12 Mbaud 后深场景重新 compute-sensitive | fast scenes 仍受 output/host 限制。 |
| XC7K70T 4ctx 成为默认 | 深场景提升明显，但 `88.70%` LUT 占用说明 generic scoreboard 不适合继续放大。 |
| direct-200MHz 已验证并成为默认 | 相对 100MHz 4ctx，非 fast 场景 `1.14x-1.44x`，fast escape 更慢。 |

## 后续方向

优先级：更强传输层、packet sequence/request ID、保留 100MHz 4ctx 作为显式参考、低 LUT 8/12/16ctx worker、16ctx 后再评估第二 adder，最后才考虑更多 multiplier。当前默认是 XC7K70T direct-200MHz 4ctx；2ctx 保留为低 LUT 对照。
