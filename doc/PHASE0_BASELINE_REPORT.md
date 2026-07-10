# Phase 0 报告 — 基线复现（不重建）

> 目标：在不动 RTL 的前提下，用现有已构建比特流验证板/JTAG/串口/工具链闭环，并记录当前默认配置的实测基线，作为后续各阶段的对照锚点。

## 0.1 环境与基线比特流

| 项 | 值 |
|---|---|
| Vivado | 2024.2 (`Z:\Softwares\Xilinx\Vivado\2024.2\bin\vivado.bat`) |
| 目标器件 | `xczu4ev-sfvc784-1-i`（VMC_RTSB ZU4EV） |
| 串口 | `COM6`，FT232HL（VID_0403&PID_6014），12 Mbaud |
| 基线比特流 | `./fp64_rtr8_proj/mandelbrot_fp64_rtr8.runs/impl_1/top.bit`（12 worker × 8 ctx，FP64，`M=8`，direct 200MHz） |
| 基线 routed 时序 | `WNS=0.103ns / WHS=0.010ns`，全部满足 |
| 基线资源 | CLB LUT `85698/87840 = 97.56%`，Reg `71473 (40.68%)`，BRAM `25.5 (19.92%)`，DSP48E2 `123 (16.90%)` |

说明：README 记载默认点为 `fp64_proj`（WNS=0.148ns，LUT 85171，DSP 121）。经核验，`fp64_rtr8_proj` 是更新的同配置（`RESPONSE_TILE_ROW_SPLITS=8`）构建，时序/资源略优于 README 记值，故采用其作为基线比特流。两者配置等价（12w/8ctx/M=8）。

## 0.2 烧录

```
vivado.bat -mode batch -source program.tcl -tclargs ./fp64_rtr8_proj/.../top.bit
→ Found 2 device(s), Target device: xczu4_0, Programming complete, Done
```
JTAG 自动连接、识别 `xczu4_0`、烧录成功。

## 0.3 功能基线（小图 HW/SW 校验）

```
python python\mandelbrot_host.py --port COM6 --width 160 --height 120 --max-iter 256 \
  --center -0.5 0.0 --step 0.005 --verify --quiet --timeout 60 \
  --tile-width 160 --tile-height 120 --tile-retries 3
```
结果：`HW vs SW: 19200/19200 match (100.00%)`，FPGA elapsed `0.053s`（360443 pps）。
→ 计算正确，串口/协议/解析全链路闭环。

## 0.4 性能基线（1080p 单跑）

| 场景 | 命令 | FPGA 时间 | 吞吐 | README 10-run 均值 |
|---|---|---|---|---|
| fast escape @128 | `--center 1.0 1.0 --step 0.002 --max-iter 128` | **3.733s** | **555460.65 pps** | 3.821s / 545436 pps |
| deep mini-brot @8192 | `--center -1.25066 0.02012 --step 1e-9 --max-iter 8192` | **9.192s** | **225579.94 pps** | 9.166s / 226235 pps |

均落在 README 记载的 10-run 区间内（单跑略优于均值属正常）。fast escape 接近 12Mbaud ~600k pps 理论上限 → **传输受限**；deep mini-brot 远低于上限 → **计算受限**，是后续计算优化的关键观测点。

## 0.5 结论

- 板/JTAG/COM6/12Mbaud/Vivado/Python 全闭环正常。
- 功能 100% 匹配，性能与文档基线一致。
- 锚点已建立：**fast=3.733s、minibrot=9.192s**，后续各阶段以同命令同参数对照。

## 0.6 复盘：原报告 O1（心形早退）可行性修正

在进入 Phase 1 前，对设计报告中的“P0 优化 O1 = 主心形+period-2 bulb 几何早退”做了一次定向复核，结论是**该项对本项目实际测试场景收益≈0，应降级**：

- 经典心形+period-2 bulb 测试只能识别**主集合**（原点附近的主心形 x∈[-0.75,0.25] 与主 period-2 bulb x∈[-1.25,-0.75]）。
- 计算受限的深 zoom 场景 `deep mini-brot @8192`（center `-1.25066,0.02012`，step `1e-9`）视野仅 ~2e-6 宽，位于主 period-2 bulb 左缘之外，**视野内不含主集合** → 早退命中率为 0。
- 含主集合的 `standard @64`（center `-0.5,0`）虽命中率高，但该场景 `max_iter=64` 且已 546k pps 接近 UART 上限 → **传输受限**，计算节省被 UART 吞掉。
- 因此 O1 在“深场景无主集合可命中、浅场景被 UART 封顶”的双重夹击下无可见收益。

替代方向：对深 zoom 真正有效的是**周期性检测（periodicity detection）**捕捉 mini-brot 内点的周期轨道，但存在误判风险（eps 选取不当会输出错误 `max_iter`，使 HW/SW verify 失败），数值不安全，不在低风险阶段引入。

故后续阶段改以项目自身推荐的、已仿真验证但未上板的 **`1M+2A` 加法器 lane 实验**（`build_fp64_zu4ev_c8_w8_a2m1.tcl`）作为首个真实构建优化阶段，实测“8 context 下第二加法器是否见效”——这是 `VMC_RTSB_ZU4EV_200MHZ_OPT_REPORT.md` 明确建议的下一步，且其模型预测“8ctx 下 2A 收益甚微”，板上实测可定论。
