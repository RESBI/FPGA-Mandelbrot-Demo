# Mandelbrot FPGA 加速器

这是一个基于 FPGA 的 Mandelbrot 渲染器。PC 通过 UART 发送一次图像命令，包含中心坐标、像素步长、最大迭代次数和图像尺寸；FPGA 使用 4 个 FP64 worker 计算像素，并以 16 位迭代次数流式返回。当前默认 worker 在一个 FP64 乘法器和一个 FP64 加法器上交错执行 2 个像素上下文。

详细硬件架构见 `ARCHITECTURE_CN.md`，架构演进见 `ARCHITECTURE_EVOLUTION_REPORT_CN.md`，worker 去气泡分析见 `PIPELINE_BUBBLE_ANALYSIS_CN.md`。

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

## 目录结构

| 路径 | 说明 |
|---|---|
| `rtl/` | Verilog RTL 源码。 |
| `python/` | Host 工具、benchmark、图像输出脚本。 |
| `constraints/` | FPGA 管脚和时钟约束。 |
| `sim/` | Vivado testbench。 |
| `build_fp64.tcl` | 默认 FP64 bitstream 构建脚本。 |
| `program.tcl` | JTAG 烧录脚本。 |
| `ARCHITECTURE.md` / `ARCHITECTURE_CN.md` | 当前架构说明。 |
| `TILE_DESIGN.md` / `TILE_DESIGN_CN.md` | Tile response 和 host tile retry 设计。 |

## 构建和烧录

```bash
vivado -mode batch -source build_fp64.tcl
vivado -mode batch -source program.tcl
```

如果 Vivado 不在 `PATH` 中，可以使用本机安装路径调用 `vivado.bat`。

## 推荐 1080p 高波特率运行方式

当前推荐使用 host-driven tile，将 1080p 切成 9 个 `1920x120` stripe：

```bash
python python\mandelbrot_host.py --port COM6 --width 1920 --height 1080 --max-iter 128 --center 1.0 1.0 --step 0.002 --timeout 600 --verify --tile-width 1920 --tile-height 120 --tile-retries 3 --quiet --output python\hw_1080p_hosttile_fast_escape.png
```

原因：12 Mbaud 单个 4.15 MiB 长 burst 偶发 byte slip；host tile 给失败提供重试边界，`1920x120` 已完成六场景 30-run 稳定性测试。

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

## 更多中文文档

| 文档 | 说明 |
|---|---|
| `ARCHITECTURE_CN.md` | 当前 RTL、协议、tile、host 软件和资源。 |
| `ARCHITECTURE_EVOLUTION_REPORT_CN.md` | 从单核到当前高波特率 tile 模式的演进。 |
| `PIPELINE_BUBBLE_ANALYSIS_CN.md` | FP pipeline 去气泡、context/ADD/MUL 取舍。 |
| `TILE_DESIGN_CN.md` | Tile response 和 host-driven tile 可靠性方案。 |
| `UART_BAUDRATE_INVESTIGATION_CN.md` | UART baudrate 调查。 |
| `UART_TIMING_ANALYSIS_CN.md` | UART 采样和时序分析。 |
