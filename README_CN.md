# Mandelbrot FPGA 加速器

这是一个 UART 控制的 FPGA Mandelbrot 渲染器。当前已验证目标为 VMC_RTSB ZU4EV，使用单端 `24.576 MHz` 系统时钟。当前默认构建为 `12 workers / 8 contexts`、FP64、动态行调度，并使用 `6.144 Mbaud` FT232HL UART；host 发送短命令时需要 `50 us` byte gap。

最新详细架构请以英文主文档 [doc/ARCHITECTURE.md](doc/ARCHITECTURE.md) 为准。ZU4EV 迁移和优化记录见 [doc/VMC_RTSB_ZU4EV_24576_OPT_REPORT.md](doc/VMC_RTSB_ZU4EV_24576_OPT_REPORT.md)。架构演进与历史性能对比见 [doc/ARCHITECTURE_EVOLUTION_REPORT.md](doc/ARCHITECTURE_EVOLUTION_REPORT.md)。

## 当前配置

| 项目 | 当前值 |
|---|---:|
| FPGA | `xczu4ev-sfvc784-1-i` |
| 板卡 | VMC_RTSB ZU4EV |
| 时钟 | 单端 `sys_clk`, `24.576 MHz` |
| 约束 | `constraints_vmc_rtsb_zu4ev/led.xdc` |
| UART 管脚 | FPGA RX `D12`, FPGA TX `C12` |
| UART | `6,144,000` baud |
| Host TX byte gap | `0.00005 s` |
| 默认串口 | `COM6` |
| 浮点 | FP64 |
| Worker | `12` |
| 每 worker contexts | `8` |
| 调度 | 动态空闲 worker 行调度 |
| 最大已验证帧 | `1920x1080` |
| 六场景结果 | `6/6 PASS`, `0` retries |

## 构建

默认已验证构建：

```powershell
& "Z:\Softwares\Xilinx\Vivado\2024.2\bin\vivado.bat" -mode batch -source build_fp64.tcl -nolog -nojournal
```

worker/context 参数扫描，例如 `14 workers / 4 contexts`：

```powershell
& "Z:\Softwares\Xilinx\Vivado\2024.2\bin\vivado.bat" -mode batch -source build_fp64_zu4ev_24576_sweep.tcl -tclargs 4 14 -nolog -nojournal
```

`build_fp64_200mhz.tcl` 仅保留为兼容 wrapper。当前板级时钟不是 200 MHz，因此新脚本名使用 `zu4ev_24576`。

## 烧录

```powershell
& "Z:\Softwares\Xilinx\Vivado\2024.2\bin\vivado.bat" -mode batch -source program.tcl -tclargs "./fp64_zu4ev_proj/mandelbrot_fp64.runs/impl_1/top.bit" -nolog -nojournal
```

当前流程使用 Vivado hardware auto-connect，不需要 XVC。

## 验证

小图验证：

```powershell
python python\mandelbrot_host.py --port COM6 --baud 6144000 --tx-byte-gap 0.00005 --width 160 --height 120 --max-iter 128 --center -0.5 0.0 --step 0.005 --timeout 180 --verify --tile-width 160 --tile-height 120 --tile-retries 1 --output python\hw_24576_160x120_6144k.png
```

六场景 1080p benchmark：

```powershell
python python\host_tile_stability_benchmark.py --port COM6 --baud 6144000 --tx-byte-gap 0.00005 --runs 1 --tile-width 1920 --tile-height 120 --tile-retries 3 --run-tag zu4ev24576_6144k_c12ctx8 --summary-name zu4ev24576_6144k_c12ctx8_6scene.md
```

## 当前性能

| 场景 | Transport | Retries | FPGA s | Pixels/s |
|---|---:|---:|---:|---:|
| fast escape @128 | PASS | 0 | `9.587` | `216,288.01` |
| standard @64 | PASS | 0 | `9.622` | `215,498.75` |
| Seahorse zoom @512 | PASS | 0 | `15.192` | `136,492.42` |
| deep tendrils @8192 | PASS | 0 | `27.377` | `75,742.33` |
| deep mini-brot @8192 | PASS | 0 | `71.977` | `28,809.10` |
| deep Seahorse @1024 | PASS | 0 | `31.128` | `66,614.27` |

当前 `12/8` routed 资源/时序：

| 项目 | 数值 |
|---|---:|
| WNS | `25.024 ns` |
| TNS | `0.000 ns` |
| WHS | `0.010 ns` |
| CLB LUTs | `84,949 / 87,840 = 96.71%` |
| LUT as Logic | `81,937 / 87,840 = 93.28%` |
| CLB Registers | `71,408 / 175,680 = 40.65%` |
| BRAM Tile | `25.5 / 128 = 19.92%` |
| DSPs | `121 / 728 = 16.62%` |

历史 XC7K70T direct-200MHz 和 100MHz 结果保留在 `doc/ARCHITECTURE_EVOLUTION_REPORT.md`、`doc/200MHZ_ATTEMPT_REPORT.md`、`doc/WORKER_COUNT_SCALING.md` 中作为对比，不再是当前默认目标。
