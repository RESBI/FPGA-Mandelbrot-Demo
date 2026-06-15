# Mandelbrot FPGA 加速器

这是一个基于 FPGA 的 Mandelbrot 渲染器。PC 通过 UART 发送一次图像命令，包含中心坐标、像素步长、最大迭代次数和图像尺寸；FPGA 使用 4 个 FP64 worker 计算像素，并以 16 位迭代次数流式返回。当前默认 worker 在一个 FP64 乘法器和一个 FP64 加法器上交错执行 2 个像素上下文。

详细硬件架构见 `doc/ARCHITECTURE_CN.md`，架构演进见 `doc/ARCHITECTURE_EVOLUTION_REPORT_CN.md`，worker 去气泡分析见 `doc/PIPELINE_BUBBLE_ANALYSIS_CN.md`，N-context 新旧结构对比英文主文档见 `doc/CONTEXT_WORKER_ARCHITECTURE_REPORT.md`，中文备份见 `doc/CONTEXT_WORKER_ARCHITECTURE_REPORT_CN.md`。直接 200 MHz 计算时钟尝试见 `doc/200MHZ_ATTEMPT_REPORT.md`。

## 当前默认配置

| 项目 | 当前值 |
|---|---:|
| FPGA | Xilinx Kintex-7 `xc7k70tfbg676-1` |
| Vivado | 2020.2，安装路径 `Z:\Softwares\Xilinx` |
| 板级时钟输入 | 200 MHz 差分 `CLK_200_P/N` |
| 内部系统时钟 | MMCM 生成的 100 MHz `sys_clk` |
| 浮点模式 | FP64 |
| Mandelbrot worker | 4 |
| 每 worker 像素上下文 | 2 |
| 已验证可选上下文 | 4，通过 `build_fp64_contexts.tcl 4` |
| 调度器 | 动态空闲 core 行调度，`SCHED_MODE=1` |
| FP 有效频率 | 100 MHz，`FP_CE_DIV=1` |
| UART | 12000000 baud，fractional NCO |
| 默认串口 | `COM9` |
| 像素格式 | little-endian `uint16` 迭代次数 |
| 最大迭代次数 | 65535 |
| 最大已验证帧 | 1920x1080 |
| 当前板级构建状态 | XC7K70T 完整 FP64 bitstream 已通过 |
| Hardware server | `127.0.0.1:2542` |
| 当前 routed timing | `WNS=1.148ns`, `TNS=0.000ns`, `WHS=0.042ns`, `THS=0.000ns` |
| 当前 placed utilization | `13726` LUTs, `14559` registers, `37` DSP48E1, `9.5` BRAM tiles |

当前默认 RTL 仍是 2-context worker。本分支已从旧 Zynq-7010 平台迁移到 XC7K70T，完整 FP64 bitstream 已在新器件上构建并满足 timing。Generic 4-context worker 现在也已在 XC7K70T 上完成构建、烧录和板级测试，但 LUT 占用很高，因此作为可选性能/架构实验而不是默认 bitstream。

## 目录结构

| 路径 | 说明 |
|---|---|
| `rtl/` | Verilog RTL 源码。 |
| `python/` | Host 工具、benchmark、图像输出脚本。 |
| `doc/` | 架构、设计、分析和 TODO 文档。 |
| `constraints_hvs_xc7k70t/` | XC7K70T 管脚和时钟约束。 |
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

当前默认启用 host-driven tile。如果不传 `--tile-width/--tile-height`，host 自动使用全宽、120 行高的 host stripe，并默认 `--tile-retries 3`、单次 tile 接收 read timeout 为 30 秒。默认 compute tile 等于 host tile 本身，但 compute 宽度上限为 4096。现在已有失败后 drain 串口、发送软复位 `RST!RST!`、重算该 tile 的方案，因此默认不再拆成较小 compute tile。1080p 默认形状为 `1920x120` host tile，同时也是 `1920x120` compute tile：

```bash
python python\mandelbrot_host.py --port COM9 --width 1920 --height 1080 --max-iter 128 --center 1.0 1.0 --step 0.002 --timeout 600 --verify --tile-width 1920 --tile-height 120 --tile-retries 3 --quiet --output python\hw_1080p_hosttile_fast_escape.png
```

`--quiet` 下现在使用单行进度条，不再刷屏。格式为：

```text
[progress] (n / total compute tile) (m / total host tile) current task
```

失败的 compute tile 会被记录坐标、drain stale UART bytes，并默认发送 soft reset 命令 `RST!RST!`，然后重算该 compute tile。可用 `--no-soft-reset-on-retry` 关闭自动软复位，也可以手动发送：

```powershell
python python\mandelbrot_host.py --port COM9 --soft-reset
```

如需旧的单命令整帧 response，显式传 `--full-frame`。不建议在 12 Mbaud 大帧下使用该模式。

如果高波特率 tile 中途丢字节，host 可能看起来暂时不动，直到当前串口 read timeout 后才进入 retry。默认 `--tile-read-timeout 30`；可以调低以更快触发 retry，也可以对特别慢的 tile 调高。

原因：12 Mbaud 单个 4.15 MiB 长 burst 偶发 byte slip；host tile 给失败提供重试边界，`1920x120` 已完成六场景 30-run 稳定性测试。

`4096x4096` 默认 host-tiled 路径也已做 RTL packetizer 级验证：逻辑图像拆成 35 个硬件 response，检查 262144 个 `TD` packet 和 16777216 个像素，checksum、frame boundary、tail tile 均通过。该验证覆盖当前 host tiling geometry 的 packet/count/tail 行为，但不能替代板级 USB-UART 长时间 soak。

## 当前资源和时序

最新 1080p 六场景板级测试，12 Mbaud，默认 `1920x120` host tile，compute tile 等于 host tile：

| 场景 | 状态 | FPGA 时间 | 吞吐 |
|---|---:|---:|---:|
| fast escape @128 | PASS | `5.127s` | `404464.49 pps` |
| standard @64 | PASS | `4.731s` | `438328.75 pps` |
| Seahorse zoom @512 | PASS | `19.440s` | `106668.12 pps` |
| deep tendrils @8192 | PASS | `37.326s` | `55553.03 pps` |
| deep mini-brot @8192 | PASS | `83.561s` | `24815.51 pps` |
| deep Seahorse @1024 | PASS | `36.626s` | `56615.56 pps` |

可选 4-context worker 在同一 XC7K70T 环境下也已验证，bitstream 为 `fp64_ctx4_proj/mandelbrot_fp64_ctx4.runs/impl_1/top.bit`：

| 场景 | 状态 | FPGA 时间 | 吞吐 |
|---|---:|---:|---:|
| fast escape @128 | PASS | `4.683s` | `442824.20 pps` |
| standard @64 | PASS | `5.782s` | `358640.05 pps` |
| Seahorse zoom @512 | PASS | `9.836s` | `210825.06 pps` |
| deep tendrils @8192 | PASS | `17.677s` | `117303.25 pps` |
| deep mini-brot @8192 | PASS | `44.146s` | `46971.46 pps` |
| deep Seahorse @1024 | PASS | `19.965s` | `103861.51 pps` |

4ctx 小图 gate 为 `160x120`、`--verify`、`100.00%` match，FPGA elapsed `0.091s`。深度 compute-bound 场景相对默认 2ctx 提升约 `1.78x-2.17x`；fast scenes 仍接近 12 Mbaud host/transport ceiling。`standard @64` 在这次 4ctx 单次测量中反而更慢，应视为场景和调度敏感结果。

主要阶段性能对比：

| 阶段 | 模式 | fast escape @128 | standard @64 | Seahorse @512 | deep mini-brot @8192 |
|---|---|---:|---:|---:|---:|
| 历史 576k 4-worker 1ctx | UART-bound baseline | `72.736s` | `72.735s` | `74.265s` | `234.231s` |
| 12M single-burst 4-worker 2ctx | 高 baud 长 burst | `4.678s` | `4.202s` | `17.280s` | `83.428s` |
| 12M tiled `512x120` compute | 较小 retry tile | `7.010s` | `7.374s` | `18.721s` | `84.984s` |
| 12M tiled host tile = compute tile | 当前默认，1080p 为 `1920x120` | `5.127s` | `4.731s` | `19.440s` | `83.561s` |
| 12M tiled 可选 4ctx worker | `build_fp64_contexts.tcl 4`，1080p 为 `1920x120` | `4.683s` | `5.782s` | `9.836s` | `44.146s` |

直接使用 200 MHz 作为完整计算时钟的尝试没有得到 timing-clean bitstream。最好的 200 MHz 尝试仍为 `WNS=-0.651ns`, `TNS=-306.186ns`，因此没有下载跑分。详见 `doc/200MHZ_ATTEMPT_REPORT.md`。

| Resource | Used | Device | Utilization |
|---|---:|---:|---:|
| Slice LUTs | 13726 | 41000 | 33.48% |
| Slice Registers | 14559 | 82000 | 17.75% |
| DSP48E1 | 37 | 240 | 15.42% |
| Block RAM Tile | 9.5 | 135 | 7.04% |

| Build | Scheduler | Contexts | WNS | TNS | WHS | THS |
|---|---|---:|---:|---:|---:|---:|
| `build_fp64.tcl` | dynamic rows + tiled response | 2 | `1.148ns` | `0.000ns` | `0.042ns` | `0.000ns` |
| `build_fp64_contexts.tcl 4` | dynamic rows + tiled response | 4 | `0.583ns` | `0.000ns` | `0.039ns` | `0.000ns` |

可选 4ctx XC7K70T 资源：

| Resource | Used | Device | Utilization |
|---|---:|---:|---:|
| Slice LUTs | 36367 | 41000 | 88.70% |
| Slice Registers | 19149 | 82000 | 23.35% |
| DSP48E1 | 37 | 240 | 15.42% |
| Block RAM Tile | 9.5 | 135 | 7.04% |

## 重要限制

| 限制 | 说明 |
|---|---|
| UART 长 burst | 12 Mbaud 单帧长 burst 偶发 byte slip；推荐 host tile。 |
| FP64 实现 | IEEE-like，非完整 IEEE-754；不完整支持 NaN/Inf/denormal/rounding。 |
| FP64 边界差异 | RTL truncation 与 Python RNE 在边界点可能不同，视觉上可接受。 |
| 4ctx generic worker | XC7K70T 可构建并通过板级测试，但 LUT 占用 `88.70%`，仍不是默认配置。 |
| 8ctx generic worker | 行为仿真通过，但旧 generic 实现在早期 xc7z010 目标上 LUT 超量，XC7K70T 尚未作为默认候选验证。 |
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
