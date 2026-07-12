# Mandelbrot FPGA 加速器

这是一个基于 FPGA 的 Mandelbrot 渲染器。PC 通过 UART 发送计算命令，包含中心坐标、像素步长、最大迭代次数和图像尺寸；FPGA 使用定点 Q8.55 (fx64) worker 计算像素，并以 16 位迭代次数返回。

**默认传输模式为 PL-PS DDR 模式**（`build.tcl`）：22 个定点 worker 在计算阶段通过 AXI 将像素写入 PS DDR4；下载阶段由 PL 侧 AXI reader 从 DDR 读取像素，并复用 `RT/TD/TE` 协议经 UART 返回 Host。XSDB 只用于初始化 PS DDR 和烧录 PL，不再承担像素回读。Host 默认 `--mode ddr`；使用 `--compute-only` 可只测试计算 + DDR 写入。

UART 模式（`build_fp64_fx24.tcl`）仍可用作替代：24 个定点 worker，12Mbaud UART 流式 `RT/TD/TE` 分块响应，浅场景受限于 ~555k pps 串口带宽。使用 `--mode fx64`。

详细硬件架构见 `doc/ARCHITECTURE_CN.md`，PL-PS DDR 设计见 `doc/PL_PS_DDR_DESIGN.md`，worker 去气泡分析见 `doc/PIPELINE_BUBBLE_ANALYSIS.md`。当前 ZU4EV 200MHz 适配、资源、时序和性能对比见 `doc/VMC_RTSB_ZU4EV_200MHZ_OPT_REPORT.md`。

## 当前默认配置

| 项目 | 当前值 |
|---|---:|
| FPGA | VMC_RTSB ZU4EV，DDR 构建使用 `xczu4ev-sfvc784-2-i`（来自 `reference/design_1.bd`） |
| Vivado | 2024.2 或兼容版本 |
| 板级时钟输入 | E12 单端 200 MHz `sys_clk` |
| 内部系统时钟 | direct 200 MHz 单时钟域 |
| 算术模式 | 定点 Q8.55 (fx64), `WORKER_MODE=1` |
| **默认传输** | **PL-PS DDR (AXI HPC0 → PS DDR4 → UART 下载)** |
| Mandelbrot worker | 22 (DDR 模式) / 24 (UART 模式) |
| 每 worker 像素上下文 | 4 |
| 历史低 LUT 上下文 | 2, 4 |
| 调度器 | 动态空闲 core 行调度，`SCHED_MODE=1` |
| FP 有效频率 | 200 MHz，`FP_CE_DIV=1` |
| UART | 12000000 baud，fractional NCO |
| 默认串口 | `COM6` |
| Host `--mode` 默认 | `ddr` (PL-PS DDR + fx64) |
| 像素格式 | little-endian `uint16` 迭代次数 |
| 最大迭代次数 | 65535 |
| 最大已验证 UART-DDR 回传 | 1920x1080，`2073600/2073600` 与 Q8.55 软件参考一致 |
| 当前板级构建状态 | ZU4EV DDR bitstream 已通过构建、烧录和 1080p DDR→UART 闭环验证 |
| 烧录链路 | XSDB JTAG 空白启动 (DDR 模式) 或 Vivado hardware auto-connect (UART 模式) |
| 当前 routed timing (DDR 22w) | `WNS=0.114ns`, `TNS=0.000ns`, `WHS=0.011ns`, `THS=0.000ns` |
| 当前 routed utilization (DDR 22w) | `86450` LUTs (98.42%), `73894` registers, `445` DSP48E2, `46` BRAM tiles |

当前默认 RTL 是 ZU4EV 上已验证的 direct-200MHz 22-worker、4-context-per-worker 定点 (fx64) 配置，使用 PL-PS DDR 传输。24-worker UART fx64 构建 (`build_fp64_fx24.tcl`) 保留为替代方案。项目当前只支持 fx64 算术模式；fx128 为未来预留。

## 构建和烧录

### DDR 模式（默认）

```bash
Z:\Softwares\Xilinx\Vivado\2024.2\bin\vivado.bat -mode batch -source build.tcl
Z:\Softwares\Xilinx\Vitis\2024.2\bin\xsdb.bat boot_jtag_with_ram.tcl
```

### UART 模式（替代）

```bash
vivado -mode batch -source build_fp64_fx24.tcl
vivado -mode batch -source program.tcl
```

如果 Vivado 不在 `PATH` 中，请使用完整路径调用 `vivado.bat`：`Z:\Softwares\Xilinx\Vivado\2024.2\bin\vivado.bat`。

## 目录结构

| 路径 | 说明 |
|---|---|
| `rtl/` | Verilog RTL 源码。 |
| `python/` | Host 工具、benchmark、图像输出脚本。 |
| `doc/` | 架构、设计、分析和 TODO 文档。 |
| `constraints_vmc_rtsb_zu4ev/` | VMC_RTSB ZU4EV 管脚和 200MHz 单端时钟约束。 |
| `sim/` | Vivado testbench。 |
| `build.tcl` | 默认 DDR-to-UART 构建入口。 |
| `build_fp64.tcl` | 历史 FP64 UART 回归构建脚本。 |
| `program.tcl` | JTAG 烧录脚本。 |
| `doc/ARCHITECTURE.md` / `doc/ARCHITECTURE_CN.md` | 当前架构说明。 |
| `doc/TILE_DESIGN.md` / `doc/TILE_DESIGN_CN.md` | Tile response 和 host tile retry 设计。 |

## 历史 FP64 UART 构建

```bash
vivado -mode batch -source build_fp64.tcl
vivado -mode batch -source program.tcl
```

如果 Vivado 不在 `PATH` 中，请先找到本机安装路径，再用完整路径调用 `vivado.bat`。示例路径仅供参考：`C:\Xilinx\Vivado\2024.2\bin\vivado.bat`。

## UART 替代模式的 1080p 运行方式

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
python python\mandelbrot_host.py --mode fx64 --width 160 --height 120 --max-iter 256 --palette ocean --output python\mandelbrot_160x120_ocean.png
```

当前默认启用 host-driven tile。如果不传 `--tile-width/--tile-height`，host 自动使用全宽、120 行高的 host stripe，并默认 `--tile-retries 3`、单次 tile 接收 read timeout 为 5 秒。默认 compute tile 高度等于 host tile 高度，compute 宽度上限改为 2048。因此 1080p 仍是 `1920x120` compute tile，而 `4096x120` host stripe 会自动拆成两个 `2048x120` compute tile。RTL 使用 `RESPONSE_TILE_ROW_SPLITS=8`，因此默认 `1920x120` compute response 会被切成 8 个全宽 `1920x15` retry tile，各自独立 checksum。1080p 默认形状为 `1920x120` host tile，同时也是 `1920x120` compute tile：

```bash
python python\mandelbrot_host.py --mode fx64 --port COM6 --width 1920 --height 1080 --max-iter 128 --center 1.0 1.0 --step 0.002 --timeout 600 --verify --tile-width 1920 --tile-height 120 --tile-retries 3 --quiet --output python\hw_1080p_hosttile_fast_escape.png
```

`--quiet` 下现在使用单行进度条，不再刷屏。格式为：

```text
[progress] (n / total compute tile) (m / total host tile) current task
```

Host 会区分两类失败：如果完整收到 `RT/TD/TE` frame 但某个 retry tile checksum mismatch，则先记录该局部矩形，继续完成剩余 compute tile，最后统一重算并回填；如果出现 bad magic、payload 不完整、缺 checksum 等 framing/short-read 失败，则说明串口流失同步，会 drain stale UART bytes，并默认发送 soft reset 命令 `RST!RST!`，然后立即重算当前 compute tile。可用 `--no-soft-reset-on-retry` 关闭自动软复位，也可以手动发送：

```powershell
python python\mandelbrot_host.py --mode fx64 --port COM6 --soft-reset
```

如需旧的单命令整帧 response，显式传 `--full-frame`。不建议在 12 Mbaud 大帧下使用该模式。

如果高波特率 tile 中途丢字节，host 可能看起来暂时不动，直到当前串口 read timeout 后才进入 retry。默认 `--tile-read-timeout 5.0`；对特别大的实验 tile 可显式调高。

原因：12 Mbaud 单个 4.15 MiB 长 burst 偶发 byte slip；host tile 给失败提供重试边界，`1920x120` 已完成六场景 30-run 稳定性测试。

`4096x4096` 默认 host-tiled 路径也已做 RTL packetizer 级验证：逻辑图像拆成 35 个硬件 response，检查 262144 个 `TD` packet 和 16777216 个像素，checksum、frame boundary、tail tile 均通过。该验证覆盖当前 host tiling geometry 的 packet/count/tail 行为，但不能替代板级 USB-UART 长时间 soak。

## 历史 UART FP64 资源和时序

以下为历史 UART FP64 12-worker/8-context 数据，不是当前 DDR 默认构建：

| 场景 | Transport pass | Retry events | 平均 FPGA 时间 | Min | Max | CV | 平均吞吐 | 对比 7K70T 6w/4ctx 200MHz |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fast escape @128 | `10/10` | `1` | `3.821s` | `3.720s` | `4.702s` | `8.11%` | `545436.22 pps` | `1.215x` |
| standard @64 | `10/10` | `1` | `3.816s` | `3.715s` | `4.696s` | `8.10%` | `546090.60 pps` | `1.215x` |
| Seahorse zoom @512 | `10/10` | `1` | `3.964s` | `3.864s` | `4.855s` | `7.89%` | `525491.58 pps` | `1.442x` |
| deep tendrils @8192 | `10/10` | `0` | `3.994s` | `3.991s` | `3.997s` | `0.04%` | `519243.89 pps` | `2.145x` |
| deep mini-brot @8192 | `10/10` | `0` | `9.166s` | `9.164s` | `9.168s` | `0.02%` | `226235.12 pps` | `2.287x` |
| deep Seahorse @1024 | `10/10` | `1` | `4.575s` | `4.472s` | `5.485s` | `6.99%` | `454952.34 pps` | `2.113x` |

上表的倍数是当前 ZU4EV 12w/8ctx 10-run mean 相对上一阶段 7K70T 6w/4ctx 200MHz 10-run mean 结果计算的。fast/standard 场景已接近 UART/host/packet overhead 限制，且偶发 tile retry 会拉低均值；deep 场景收益更大。

该 12-worker/8-context 设计保留为 UART/FP64 回归点。当前默认 DDR-to-UART 构建的最终数据见本文件顶部配置表。

## 当前 DDR-to-UART 端到端性能

旧 UART 设计中计算与传输流水重叠（总时间 ≈ max(计算, 传输)）。DDR 设计将流程分为串行的计算阶段和下载阶段（总时间 = 计算 + 下载）。

| 场景 | 旧 UART 24w (s) | DDR 计算 (s) | DDR 下载 (s) | DDR 合计 (s) | 端到端 |
|---|---|---|---|---|---|
| fast escape @128 | 3.733 | 0.221 | 4.369 | 4.590 | 0.81× |
| standard @64 | 3.727 | 0.223 | 4.373 | 4.596 | 0.81× |
| Seahorse @512 | 3.882 | 1.086 | 5.009 | 6.095 | 0.64× |
| deep tendrils @8192 | 5.029 | 1.950 | 5.002 | 6.952 | 0.72× |
| deep minibrot @8192 | 5.091 | 5.104 | 4.418 | 9.522 | 0.53× |
| deep Seahorse @1024 | 4.074 | 2.254 | 4.406 | 6.660 | 0.61× |

端到端 DDR 模式比 UART 慢，因为计算和下载串行。DDR 设计的价值在于计算阶段解耦（1.8-17× 无 UART 反压）、从 DDR 无损重传，以及未来 PS 推送（Ethernet/USB）可将下载从 ~4.4s 降至 <0.1s。

| Resource | Used | Device | Utilization |
|---|---:|---:|---:|
| CLB LUTs | 85171 | 87840 | 96.96% |
| CLB Registers | 71453 | 175680 | 40.67% |
| DSP48E2 | 121 | 728 | 16.62% |
| Block RAM Tile | 25.5 | 128 | 19.92% |

| Build | Scheduler | Workers | Contexts | WNS | TNS | WHS | THS |
|---|---|---:|---:|---:|---:|---:|---:|
| `build_fp64.tcl` | direct-200MHz dynamic rows + tiled response | 12 | 8 | `0.148ns` | `0.000ns` | `0.010ns` | `0.000ns` |

## 重要限制

| 限制 | 说明 |
|---|---|
| UART 长 burst | 12 Mbaud 单帧长 burst 偶发 byte slip；推荐 host tile。 |
| FP64 实现 | IEEE-like，非完整 IEEE-754；不完整支持 NaN/Inf/denormal/rounding。 |
| FP64 边界差异 | RTL truncation 与 Python RNE 在边界点可能不同，视觉上可接受。 |
| 12-worker 8ctx FP64 | 历史 UART 回归点，不是当前默认。 |
| LUT/routing 压力 | 当前 `96.96%` CLB LUT，最差路径主要是参数分发 route delay，继续增加 worker 风险高。 |
| 7K70T 4/6-worker direct-200MHz | 历史参考点，仍可用于面积/性能对比。 |
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
