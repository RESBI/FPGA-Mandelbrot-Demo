# Mandelbrot FPGA 加速器架构摘要

本文是当前架构的中文摘要。最新、完整、可执行命令级文档请以 [ARCHITECTURE.md](ARCHITECTURE.md) 为准。

## 当前目标

当前已验证目标为 VMC_RTSB ZU4EV，Vivado part 为 `xczu4ev-sfvc784-1-i`。板级输入为单端 `sys_clk`，频率 `24.576 MHz`。顶层 `rtl/top.v` 使用 `BUFG` 直接生成单一系统时钟域，不再使用旧板的差分 200 MHz 输入或 MMCM 路径。

| 项目 | 当前值 |
|---|---:|
| 约束文件 | `../constraints_vmc_rtsb_zu4ev/led.xdc` |
| UART RX/TX | RX `D12`, TX `C12` |
| 默认串口 | `COM6` |
| UART | `6,144,000` baud |
| Host 命令 byte gap | `50 us` |
| Worker | `12` |
| 每 worker contexts | `8` |
| FPU tag latency | `MUL_LAT=6`, `ADD_LAT=9` |
| 调度 | 动态行调度 |
| 最大验证帧 | `1920x1080` |

## 数据路径

```text
Host PC
  -> uart_rx
  -> cmd_parser
  -> mandelbrot_multicore
     -> work_dispatch_dynamic_rows
     -> 12 x mandelbrot_core_worker_kctx
     -> raster_collect_dynamic_rows
  -> output queue
  -> tx_ctrl
  -> uart_tx
  -> Host PC
```

每个 worker 共享一个 FP64 乘法器和一个 FP64 加法器，通过 8 个像素上下文隐藏 FPU pipeline latency。`14 workers / 4 contexts` 虽然资源更低、timing slack 更大，但六场景全部慢于 `12/8`，因此未作为最终默认。

## UART 结论

`6.144 Mbaud` 是当前项目本体最高已接受速率，但需要 host 命令发送使用 `--tx-byte-gap 0.00005`。原因是 33 字节 FP64 命令在无 gap 的连续 burst 下会出现 PC->FPGA RX 错位或丢字节；图像 payload 的 FPGA->PC 方向仍保持完整高 baud 回传。

## 构建与验证

默认构建：

```powershell
& "Z:\Softwares\Xilinx\Vivado\2024.2\bin\vivado.bat" -mode batch -source ../build_fp64.tcl -nolog -nojournal
```

参数扫描使用：

```powershell
& "Z:\Softwares\Xilinx\Vivado\2024.2\bin\vivado.bat" -mode batch -source ../build_fp64_zu4ev_24576_sweep.tcl -tclargs 4 14 -nolog -nojournal
```

详细资源、时序、六场景性能和优化过程见 [VMC_RTSB_ZU4EV_24576_OPT_REPORT.md](VMC_RTSB_ZU4EV_24576_OPT_REPORT.md)。
