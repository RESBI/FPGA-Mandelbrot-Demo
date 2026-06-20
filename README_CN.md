# Mandelbrot FPGA 加速器

这是一个基于 FPGA 的 Mandelbrot 渲染器。PC 通过 UART 发送一次图像命令，包含中心坐标、像素步长、最大迭代次数和图像尺寸；FPGA 使用 6 个 FP64 worker 计算像素，并以 16 位迭代次数流式返回。当前默认构建在 direct-200MHz 时钟下使用 6 个 worker、每 worker 4 个像素上下文，每个 worker 共享一个 FP64 乘法器和一个 FP64 加法器；该默认构建已通过 timing、烧录和 1080p 板级 benchmark。

详细硬件架构见 `doc/ARCHITECTURE_CN.md`，架构演进见 `doc/ARCHITECTURE_EVOLUTION_REPORT_CN.md`，worker 去气泡分析见 `doc/PIPELINE_BUBBLE_ANALYSIS_CN.md`，N-context 新旧结构对比英文主文档见 `doc/CONTEXT_WORKER_ARCHITECTURE_REPORT.md`，中文备份见 `doc/CONTEXT_WORKER_ARCHITECTURE_REPORT_CN.md`。直接 200 MHz 计算时钟尝试见 `doc/200MHZ_ATTEMPT_REPORT.md`。

## 当前默认配置

| 项目 | 当前值 |
|---|---:|
| FPGA | Xilinx Kintex-7 `xc7k70tfbg676-1` |
| Vivado | 2024.2 或兼容版本；使用本机安装路径 |
| 板级时钟输入 | 200 MHz 差分 `CLK_200_P/N` |
| 内部系统时钟 | direct 200 MHz，`DIRECT_200MHZ=1` |
| 100MHz 参考构建 | `build_fp64_100mhz.tcl` |
| 浮点模式 | FP64 |
| Mandelbrot worker | 6 |
| 每 worker 像素上下文 | 4 |
| 历史低 LUT 上下文 | 2 |
| 调度器 | 动态空闲 core 行调度，`SCHED_MODE=1` |
| FP 有效频率 | 200 MHz，`FP_CE_DIV=1` |
| UART | 12000000 baud，fractional NCO |
| 默认串口 | `COM9` |
| 像素格式 | little-endian `uint16` 迭代次数 |
| 最大迭代次数 | 65535 |
| 最大已验证帧 | 1920x1080 |
| 当前板级构建状态 | XC7K70T 完整 FP64 bitstream 已通过 |
| 烧录链路 | Vivado `hw_server` 在 `127.0.0.1:3122`，CH347 XVC 在 `127.0.0.1:2542` |
| 当前 routed timing | `WNS=0.003ns`, `TNS=0.000ns`, `WHS=0.042ns`, `THS=0.000ns` |
| 当前 routed utilization | `29891` LUTs, `25501` registers, `97` DSP48E1, `13.5` BRAM tiles |

当前默认 RTL 是 XC7K70T 上已验证的 direct-200MHz 6-worker、4-context-per-worker 配置。本分支已从旧 Zynq-7010 平台迁移到 XC7K70T，完整 FP64 bitstream 已在新器件上构建、满足 timing、烧录并完成六场景 1080p benchmark。100MHz 4ctx 和 4-worker direct-200MHz 版本保留为显式参考点。

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

如果 Vivado 不在 `PATH` 中，请先找到本机安装路径，再用完整路径调用 `vivado.bat`。示例路径仅供参考：`C:\Xilinx\Vivado\2024.2\bin\vivado.bat`。

## 推荐 1080p 高波特率运行方式

Host PNG/BMP 输出支持 `--palette` 选择软件上色方案，不影响 FPGA 计算结果或串口协议。可选值：

| Palette | 说明 |
|---|---|
| `classic` | 原始周期 RGB palette，默认值。 |
| `fire` | 黑/红/黄/白 heat-map 风格，escape band 对比强。 |
| `ocean` | 蓝/青渐变，适合冷色 deep zoom。 |
| `twilight` | 紫色到暖色的 HSV 循环 palette。 |
| `grayscale` | 单色亮度 ramp，适合观察结构。 |

示例：

```bash
python python\mandelbrot_host.py --width 160 --height 120 --max-iter 256 --palette ocean --output python\mandelbrot_160x120_ocean.png
```

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

最新默认 direct-200MHz 6-worker 4ctx 1080p 六场景 10 轮板级稳定性测试，12 Mbaud，默认 `1920x120` host tile，compute tile 等于 host tile：

| 场景 | Transport pass | Retry events | 平均 FPGA 时间 | Min | Max | CV | 平均吞吐 | 对比 100MHz 4ctx |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fast escape @128 | `10/10` | `2` | `4.641s` | `4.423s` | `6.592s` | `14.77%` | `453333.47 pps` | `1.009x` |
| standard @64 | `10/10` | `2` | `4.636s` | `4.416s` | `5.515s` | `9.92%` | `450824.12 pps` | `1.247x` |
| Seahorse zoom @512 | `10/10` | `2` | `5.715s` | `5.418s` | `6.937s` | `10.87%` | `366227.26 pps` | `1.721x` |
| deep tendrils @8192 | `10/10` | `1` | `8.567s` | `8.409s` | `9.968s` | `5.75%` | `242675.75 pps` | `2.063x` |
| deep mini-brot @8192 | `10/10` | `0` | `20.963s` | `20.962s` | `20.965s` | `0.00%` | `98916.27 pps` | `2.106x` |
| deep Seahorse @1024 | `10/10` | `1` | `9.668s` | `9.511s` | `11.065s` | `5.08%` | `214934.36 pps` | `2.065x` |

100MHz 4ctx 参考构建小图 gate 为 `160x120`、`--verify`、`100.00%` match，FPGA elapsed `0.091s`。上表的倍数是当前默认 6-worker direct-200MHz 10 轮均值相对 100MHz 4ctx 数据（`4.683/5.782/9.836/17.677/44.146/19.965s`）计算的结果。相对上一版 4-worker direct-200MHz 默认，当前 6-worker 版本在 compute-heavy 场景提升约 `1.38x-1.51x`。

直接使用 200 MHz 作为完整计算时钟的 6-worker 4ctx 设计已成为当前默认有效性能点：修复后 timing-clean，`WNS=0.003ns`, `TNS=0.000ns`，并通过烧录和上述 10 轮 1080p 测试。历史性能、资源、时序和阶段对比见 `doc/ARCHITECTURE_EVOLUTION_REPORT_CN.md`；direct-200MHz 细节见 `doc/200MHZ_ATTEMPT_REPORT.md`，worker 数量横向对比见 `doc/WORKER_COUNT_SCALING.md`。

| Resource | Used | Device | Utilization |
|---|---:|---:|---:|
| Slice LUTs | 29891 | 41000 | 72.90% |
| Slice Registers | 25501 | 82000 | 31.10% |
| DSP48E1 | 97 | 240 | 40.42% |
| Block RAM Tile | 13.5 | 135 | 10.00% |

| Build | Scheduler | Workers | Contexts | WNS | TNS | WHS | THS |
|---|---|---:|---:|---:|---:|---:|---:|
| `build_fp64.tcl` | direct-200MHz dynamic rows + tiled response | 6 | 4 | `0.003ns` | `0.000ns` | `0.042ns` | `0.000ns` |

## 重要限制

| 限制 | 说明 |
|---|---|
| UART 长 burst | 12 Mbaud 单帧长 burst 偶发 byte slip；推荐 host tile。 |
| FP64 实现 | IEEE-like，非完整 IEEE-754；不完整支持 NaN/Inf/denormal/rounding。 |
| FP64 边界差异 | RTL truncation 与 Python RNE 在边界点可能不同，视觉上可接受。 |
| 6-worker 4ctx 默认 | 当前默认，XC7K70T 可构建、timing-clean、可烧录并完成 1080p 六场景测试。 |
| 4-worker 4ctx direct-200MHz | 历史低面积参考点，仍可用于面积/性能对比。 |
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
