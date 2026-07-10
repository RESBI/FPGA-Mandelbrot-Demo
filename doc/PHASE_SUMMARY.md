# 阶段优化总览（Phase 0–2）

> 本文档汇总“设计审查 + 分阶段优化/仿真/烧板/测试”的执行结果与结论。环境：Vivado 2024.2，VMC_RTSB ZU4EV `xczu4ev-sfvc784-1-i`，COM6/FT232HL @12Mbaud。详见各阶段报告。

## 交付物

| 文档 | 内容 |
|---|---|
| `doc/DESIGN_REVIEW_AND_OPTIMIZATION_REPORT.md` | 完整设计审查：架构评估、按文件的问题清单、10 项优化方案排序、分阶段计划 |
| `doc/PHASE0_BASELINE_REPORT.md` | 基线复现：烧 `fp64_rtr8` 比特流，小图 100% verify，1080p 锚点（fast 3.733s / minibrot 9.192s） |
| `doc/PHASE1_1M2A_REPORT.md` | `1M+2A` 实验：仿真 PASS，构建失败（93971 LUT > 87840），证 generic 8ctx worker 不可加第二加法器 |
| `doc/PHASE2_EARLY_ESCAPE_REPORT.md` | 平方项早退：仿真+小图 verify 等价，构建成功（WNS=0.104），但 +4827 LUT（重定时膨胀）、零速度收益，已回退 |
| 本文件 | 阶段总览与最终结论 |

## 阶段结果矩阵

| 阶段 | 改动 | 仿真 | 构建 | 烧板 | 性能 | 裁定 |
|---|---|---|---|---|---|---|
| P0 基线 | 无（用 rtr8 既有比特流） | — | — | ✅ | fast 3.733s / minibrot 9.192s | 锚点建立 |
| P1 1M+2A | 8w/8ctx/2A | ✅ 1920px | ❌ 93971>87840 LUT | — | — | 不可构建 |
| P2 早退 | 12w/8ctx + early-escape + lane-1 门控 | ✅ 1920px 等价 | ✅ WNS=0.104，LUT 99.63% | ✅ 小图 100% | fast 3.745s（无收益）；minibrot slip 噪声 | 拒绝（零收益+密度代价），已回退 |

## 关键实测发现

1. **LUT 墙是硬约束**：基线 synth LUT-as-Logic 82686（94.13%），器件 87840。加第二加法器（+8271）直接超器件；加一个 quick_esc 比较（应 ~360 LUT）经重定时膨胀为 +4827，把密度推到 99.63%。**97%+ 占用下，加法性改动的 LUT 代价不可预测**。
2. **UART 是浅场景天花板**：fast escape @128 = 553k pps，已贴 12Mbaud ~600k pps 理论上限；计算优化（早退）被串口吞掉，**零可见收益**。
3. **12Mbaud 长 burst 固有 slip**：1080p minibrot（~4MiB burst）在**基线与 Phase2 上都偶发** byte slip（README 已记载）；Phase0 的 9.192s 是幸运 0-retry 单跑。slip→重算整 tile 是当前主要可靠性损耗。
4. **owner 表/FIFO 已是 BRAM**：综合日志证 `owner_mem/owner_gen/u_fifo/mem` 均被推断为 Block RAM，故原报告 O2（强制 BRAM）无收益可拿；97.56% LUT 几乎全是纯 scoreboard 逻辑。
5. **几何早退（心形/bulb）对深zoom 无效**：minibrot 视野不含主集合；浅场景含主集合但被 UART 封顶。

## 最终结论

本设计在 **ZU4EV + 12Mbaud UART** 下已**系统性到达实用天花板**。任何“加一点计算”的尝试都撞 LUT 墙（P1）或被 UART 吞掉（P2）。**RTL 已回退至 HEAD，板载恢复为可靠基线 `fp64_rtr8`**。

### 唯一可行的前进路径（均为大工程，建议作为后续 Phase）

| 优先级 | 方向 | 预期 | 工作量 |
|---|---|---|---|
| 1 | **减法式降 LUT worker（ring/barrel 固定槽位）** | 砍宽 mux/扫描/demux → 预算内塞更多 context（计算杠杆）或 FPU lane | 大（新 RTL + 全量验证） |
| 2 | **传输换代（FT245/SPI/Ethernet/PS MMIO）** | 抬升 600k pps 天花板，让浅场景与计算优化可见 | 大 |
| 3 | **可靠性（request_id+TD序号+CRC16 / retry-tile cache）** | slip 后重传一包而非重算整 tile | 中大（RTL+host 同改） |

### 当前状态

- 板：`fp64_rtr8`（12w/8ctx/M=8）已烧录，小图 verify 100%，处于可靠基线。
- RTL：`rtl/` 全部回到 HEAD（`git checkout` 完成，无 diff）。
- 新增未跟踪文件：4 份报告 + `build_fp64_phase2_esc.tcl`（Phase2 复现用，其比特流 `fp64_phase2_esc_proj/` 已被回退弃用）。
- 原工作树既有的未提交改动（README.md/TILE_DESIGN.md/mandelbrot_host.py/RETRY_TILE_CACHE_DESIGN.md）未触碰。

> 若需推进上述大工程方向（如先做 ring/barrel worker 原型仿真，或 retry-tile cache），可作为 Phase 3+ 继续。
