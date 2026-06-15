# Mandelbrot FPGA 加速器

这是一个基于 FPGA 的 Mandelbrot 渲染器。PC 通过 UART 发送一次图像命令，包含中心坐标、像素步长、最大迭代次数和图像尺寸；FPGA 使用 4 个 FP64 worker 计算像素，并以 16 位迭代次数流式返回。当前默认 worker 在一个 FP64 乘法器和一个 FP64 加法器上交错执行 2 个像素上下文。

详细硬件架构见 `doc/ARCHITECTURE_CN.md`，架构演进见 `doc/ARCHITECTURE_EVOLUTION_REPORT_CN.md`，worker 去气泡分析见 `doc/PIPELINE_BUBBLE_ANALYSIS_CN.md`，N-context 新旧结构对比英文主文档见 `doc/CONTEXT_WORKER_ARCHITECTURE_REPORT.md`，中文备份见 `doc/CONTEXT_WORKER_ARCHITECTURE_REPORT_CN.md`。

## 当前默认配置

| 项目 | 当前值 |
|---|---:|
| FPGA | Xilinx Zynq-7010 `xc7z010clg400-1` |
| Vivado | 2020.2 |
| 系统时钟 | 100 MHz |
| 浮点模式 | FP64 |
| Mandelbrot worker | 4 |
| 每 worker 像素上下文 | 2 |
| 调度器 | 动态空闲 core 行调度，`SCHED_MODE=1` |
| FP 有效频率 | 100 MHz，`FP_CE_DIV=1` |
| UART | 12000000 baud，fractional NCO |
| 默认串口 | `COM6` |
| 像素格式 | little-endian `uint16` 迭代次数 |
| 最大迭代次数 | 65535 |
| 最大已验证帧 | 1920x1080 |
| 当前 routed timing | `WNS=0.285ns`, `TNS=0.000ns`, `WHS=0.021ns`, `THS=0.000ns` |
| 当前 placed utilization | `13917` LUTs, `14458` registers, `37` DSP48E1, `9.5` BRAM tiles |

当前默认 RTL 仍是 timing-clean 的 2-context worker。Generic 4/8-context scoreboard worker 以及后续 ring/lookahead 实验已放弃：它们小图行为仿真可通过，但无法在 xc7z010 上得到可布局且 timing-clean 的设计。数据见 `doc/CONTEXT_WORKER_ARCHITECTURE_REPORT.md` / `doc/CONTEXT_WORKER_ARCHITECTURE_REPORT_CN.md`。

## 目录结构

| 路径 | 说明 |
|---|---|
| `rtl/` | Verilog RTL 源码。 |
| `python/` | Host 工具、benchmark、图像输出脚本。 |
| `doc/` | 架构、设计、分析和 TODO 文档。 |
| `constraints/` | FPGA 管脚和时钟约束。 |
| `sim/` | Vivado testbench。 |
| `build_fp64.tcl` | 默认 FP64 bitstream 构建脚本。 |
| `program.tcl` | JTAG 烧录脚本。 |
| `doc/ARCHITECTURE.md` / `doc/ARCHITECTURE_CN.md` | 当前架构说明。 |
| `doc/TILE_DESIGN.md` / `doc/TILE_DESIGN_CN.md` | Tile response 和 host tile retry 设计。 |

## 构建和烧录

```bash
vivado -mode batch -source build_fp64.tcl
vivado -mode batch -source program.tcl
```

如果 Vivado 不在 `PATH` 中，可以使用本机安装路径调用 `vivado.bat`。

## 推荐 1080p 高波特率运行方式

当前默认启用 host-driven tile。如果不传 `--tile-width/--tile-height`，host 自动使用全宽、120 行高的 host stripe，并默认 `--tile-retries 3`、单次 tile 接收 read timeout 为 30 秒。每个 host stripe 内部会再拆成更小的硬件 compute tile；默认 compute tile 为 `512x120`。因此某个 packet 坏掉时，重试粒度是受影响的 compute tile，而不是整个 host stripe。1080p 推荐默认形状为 `1920x120` host stripe 加 `512x120` compute tile：

```bash
python python\mandelbrot_host.py --port COM6 --width 1920 --height 1080 --max-iter 128 --center 1.0 1.0 --step 0.002 --timeout 600 --verify --tile-width 1920 --tile-height 120 --compute-tile-width 512 --compute-tile-height 120 --tile-retries 3 --quiet --output python\hw_1080p_hosttile_fast_escape.png
```

`--quiet` 下现在使用单行进度条，不再刷屏。格式为：

```text
[progress] (n / total compute tile) (m / total host tile) current task
```

失败的 compute tile 会被记录坐标、drain stale UART bytes，并默认发送 soft reset 命令 `RST!RST!`，然后只重算该 compute tile。可用 `--no-soft-reset-on-retry` 关闭自动软复位，也可以手动发送：

```powershell
python python\mandelbrot_host.py --port COM6 --soft-reset
```

如需旧的单命令整帧 response，显式传 `--full-frame`。不建议在 12 Mbaud 大帧下使用该模式。

如果高波特率 tile 中途丢字节，host 可能看起来暂时不动，直到当前串口 read timeout 后才进入 retry。默认 `--tile-read-timeout 30`；可以调低以更快触发 retry，也可以对特别慢的 tile 调高。

原因：12 Mbaud 单个 4.15 MiB 长 burst 偶发 byte slip；host tile 给失败提供重试边界，`1920x120` 已完成六场景 30-run 稳定性测试。

`4096x4096` 默认 host-tiled 路径也已做 RTL packetizer 级验证：逻辑图像拆成 35 个硬件 response，检查 262144 个 `TD` packet 和 16777216 个像素，checksum、frame boundary、tail tile 均通过。该验证覆盖当前 host tiling geometry 的 packet/count/tail 行为，但不能替代板级 USB-UART 长时间 soak。

## 当前资源和时序

| Resource | Used | Device | Utilization |
|---|---:|---:|---:|
| Slice LUTs | 13917 | 17600 | 79.07% |
| LUT as Logic | 13641 | 17600 | 77.51% |
| LUT as Memory | 276 | 6000 | 4.60% |
| Slice Registers | 14458 | 35200 | 41.07% |
| DSP48E1 | 37 | 80 | 46.25% |
| Block RAM Tile | 9.5 | 60 | 15.83% |

| Build | Scheduler | Contexts | WNS | TNS | WHS | THS |
|---|---|---:|---:|---:|---:|---:|
| `build_fp64.tcl` | dynamic rows + tiled response | 2 | `0.285ns` | `0.000ns` | `0.021ns` | `0.000ns` |

## 重要限制

| 限制 | 说明 |
|---|---|
| UART 长 burst | 12 Mbaud 单帧长 burst 偶发 byte slip；推荐 host tile。 |
| FP64 实现 | IEEE-like，非完整 IEEE-754；不完整支持 NaN/Inf/denormal/rounding。 |
| FP64 边界差异 | RTL truncation 与 Python RNE 在边界点可能不同，视觉上可接受。 |
| 4/8ctx generic worker | 行为仿真通过，但 LUT 超量，不能在 xc7z010 部署。 |
| 动态 owner 表 | 默认 `DYNAMIC_OWNER_DEPTH=4096`，超高帧需要重新配置。 |

默认 host tile 会把逻辑大图拆成多个硬件命令，因此 4096 行限制作用于每个 tile 的高度，而不是逻辑整图高度。`--full-frame` 会恢复旧行为，此时超过 4096 行的单硬件请求仍可能 stall。

## 更多中文文档

| 文档 | 说明 |
|---|---|
| `doc/ARCHITECTURE_CN.md` | 当前 RTL、协议、tile、host 软件和资源。 |
| `doc/ARCHITECTURE_EVOLUTION_REPORT_CN.md` | 从单核到当前高波特率 tile 模式的演进。 |
| `doc/PIPELINE_BUBBLE_ANALYSIS_CN.md` | FP pipeline 去气泡、context/ADD/MUL 取舍。 |
| `doc/CONTEXT_WORKER_ARCHITECTURE_REPORT.md` / `doc/CONTEXT_WORKER_ARCHITECTURE_REPORT_CN.md` | 旧 N-context scoreboard 与新 ring/barrel/lookahead worker 架构及模拟对比。 |
| `doc/TILE_DESIGN_CN.md` | Tile response 和 host-driven tile 可靠性方案。 |
| `doc/UART_BAUDRATE_INVESTIGATION_CN.md` | UART baudrate 调查。 |
| `doc/UART_TIMING_ANALYSIS_CN.md` | UART 采样和时序分析。 |
