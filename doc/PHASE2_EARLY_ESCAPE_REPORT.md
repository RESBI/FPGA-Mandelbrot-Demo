# Phase 2 报告 — 平方项早退（early escape on squares）

> 目标：在 LUT 墙下寻找一项**可证明数值等价、可构建、可上板**的计算微优化，验证其能否在板上兑现收益。候选为“平方项早退”：`MOP_ZISQ` 写回时若 `quick_esc(z_im²)` 已成立，则直接判逃逸、跳过 magnitude add 与 `z_re*z_im` mul。

## 2.1 改动

文件：`rtl/mandelbrot_core_worker_kctx.v`，两处 `MOP_ZISQ` 写回（`mul_done`/`mul1_done`）。
- 原：写回 `z_im²` 后无条件置位 `AOP_MAG`（mag add）与 `MOP_ZRZI`（zrzi mul），进 `C_WAIT_MAG_ZRZI`，逃逸在 mag add 写回时由 `quick_esc(z_re²)||quick_esc(z_im²)||quick_esc(sum)` 判定。
- 改：写回 `z_im²` 后先判 `quick_esc(mul_result)`（即 `quick_esc(z_im²)`）；命中则直接 `c_result_iter<=c_iter; c_result_valid<=1; c_state<=C_DONE`，跳过 mag add 与 zrzi mul；未命中走原路径。
- **数值安全性**：`quick_esc(z_im²)` 是原逃逸条件的**子项**，命中即原路径必逃逸；`result_iter=c_iter` 与原逃逸写回一致。需要 `sum` 才判逃逸的像素仍走原路径。故输出逐像素不变（可证等价）。
- 附带：将 lane-1（`mul1_*`/`add1_*`）的每拍默认写与 tag-pipe 移位用 `if (MUL_UNITS>=2)/if (ADD_UNITS>=2)`（参数常量，综合消除）包起来，使 1M+1A 默认构建对 lane-1 死逻辑的剪除更显式、更抗综合波动。

## 2.2 仿真门（等价性）

```
sim_multicore_dynamic_contexts.tcl  WORKER_CONTEXTS=8 ADD=1 MUL=1 CORE_COUNT=12 12x160 i256
→ === DYNAMIC MULTICORE TEST PASS: 1920 pixels ===  (6300295 ns，略快于基线 6309655 ns)
```
1M+2A 仿真亦 PASS（8235265 ns，与改动前 8237835 ns 一致，证 lane-1 门控未改变 2A 行为）。等价性成立。

## 2.3 构建

```
build_fp64_phase2_esc.tcl (12w/8ctx/1A, M=8, +early-escape +lane-1 gating)
→ BUILD SUCCESSFUL
→ WNS=0.104ns  TNS=0  WHS=0.010  THS=0  (全部满足，与基线 0.103ns 相当)
→ LUT-as-Logic = 87513/87840 = 99.63%
```

| 指标 | 基线 rtr8 | Phase2 | Δ |
|---|---|---|---|
| routed LUT-as-Logic | 82686 (94.13%) | 87513 (99.63%) | **+4827** |
| routed CLB LUTs 总 | 85698 (97.56%) | 90525 (103.06%*) | +4827 |
| CLB Registers | 71453 (40.68%) | 71073 (40.46%) | -380 |
| BRAM Tile | 25.5 | 25.5 | 0 |
| DSP48E2 | 123 | 123 | 0 |
| WNS | 0.103ns | 0.104ns | ~0 |

*103.06% 是“逻辑+存储 LUT 总数 / 逻辑 LUT 池”的误导性求和；实际 LUT-as-Logic 99.63% 可布线（DRC 通过、布局布线成功）。

**关键意外**：本应只增加约 360 LUT 的“一个 quick_esc 比较”，实际增加 **4827 LUT-as-Logic**。原因是 `RETIMING=true` 下，新增的组合分支改变了时序图，重定时把寄存器重排、逻辑复制，导致 LUT 膨胀。在 97%+ 占用率下，加法性改动的 LUT 代价**不可预测**。

## 2.4 板上测试（COM6 / 12Mbaud，对照 Phase 0 锚点）

| 测试 | Phase 0 基线 | Phase 2 | 结论 |
|---|---|---|---|
| 160×120 i256 `--verify` | 19200/19200 (100%) | 19200/19200 (100%) | 等价，硬件确认 |
| 64×48 i8192 deep `--verify` | — | 3064/3072 (99.74%，8 像素边界差) | 与文档记载的 FP64 截断/RNE 深zoom 边界差异一致，非 bug |
| 1080p fast escape @128 | 3.733s / 555460 pps | 3.745s / 553710 pps | **无收益**（UART 限带，计算节省被串口吞掉） |
| 1080p deep minibrot @8192（第 1 次） | 9.192s / 225579 pps（0 retry，幸运单跑） | 23.182s / 89447 pps（3 retry，Bad tile magic） | 见下 |
| 1080p deep minibrot @8192（第 2 次） | — | 13.875s / 149446 pps（3 retry，Bad tile magic） | 见下 |

### minibrot 的 UART slip 归属

- **关键复核**：把基线 rtr8 重新烧回后再跑 minibrot，**也出现 1 次 `Incomplete tile payload (57588/57600)` retry、15.432s**。
- 即：1080p minibrot 的长 burst（~4MiB）在 12Mbaud 下**本就会偶发 byte slip**（README 已记载“12M 单帧长 burst 偶发 byte slip；推荐 host tile”）。Phase 0 的 9.192s 是一次**幸运的 0-retry 单跑**，不代表基线无 slip。
- 因此 Phase 2 minibrot 的 23s/13.8s 主要是 **slip→重算**（每次重算一个 `1920x120` 深 tile 约 4–5s；3 retry ≈ +13s，与 9.2→23s 量级吻合），**非计算变慢**。小图 deep `--verify` 99.74% 也证明计算逻辑正确。
- 样本太小（Phase2 两跑各 3 slip；基线两跑 0+1 slip），**不能判定** Phase2 的更高密度（99.63%）是否显著增加 slip 概率；但密度升高通常无益于信号完整性，趋势上 Phase2 略差。

## 2.5 结论：拒绝该优化

| 维度 | 评价 |
|---|---|
| 数值安全 | ✅ 可证等价（sim + 小图 verify 100% + deep 小图仅边界差） |
| 速度收益 | ❌ fast escape UART 限带，无可见收益（553k vs 555k 为噪声）；minibrot 计算不变（内点不逃逸，早退不触发） |
| 资源代价 | ❌ +4827 LUT（重定时膨胀）→ 99.63% 密度，逼近布线极限 |
| 可靠性 | ⚠️ 未证更差，但密度升高无益；minibrot slip 在两设计都存在（12M 固有） |

**裁定**：early-escape 提供零速度收益、增加密度代价，**不予采纳**。RTL 已 `git checkout` 回退至 HEAD，基线 rtr8 已重新烧录并通过小图 100% verify。

## 2.6 阶段性收敛结论

经 Phase 0/1/2 实测，本设计在当前器件+传输下的优化空间已**系统性见底**：

| 方向 | 实测结论 |
|---|---|
| 加 FPU lane（1M+2A） | Phase 1：+8271 LUT 超 87840，**不可构建** |
| 加 context（8→12/16，generic） | 模型+面积推算同样撞 LUT 墙 |
| 计算微优化（早退） | Phase 2：逻辑安全但**零收益 + 重定时致 +4827 LUT**，密度风险 |
| 几何早退（心形/bulb） | Phase 0 复核：深zoom 视野无主集合、浅场景被 UART 封顶，**零收益** |
| 周期性检测 | 数值不安全（eps 误判→错误 max_iter），不在低风险阶段引入 |
| 传输侧 | 12Mbaud 长 burst 固有 slip；浅场景 ~555k pps 已贴 ~600k 理论上限 |

**唯一可行的前进路径均为大工程**：
1. **减法式降 LUT**：用 ring/barrel 固定槽位 worker 替代 generic scoreboard，砍掉宽 64-bit 操作数 mux / N-way ready 扫描 / writeback demux → 在 LUT 预算内塞入更多 context（计算杠杆）或 FPU lane。
2. **传输换代**：FT245 FIFO / SPI / Ethernet / Zynq PS MMIO，抬升 ~600k pps 的 UART 天花板。
3. **可靠性**：request_id + TD 序号 + CRC16（TODO P0）、retry-tile cache（`RETRY_TILE_CACHE_DESIGN.md`），把 slip 后的“重算整 tile”降为“重传一包”。

这三者之前，任何“加一点计算”都会撞 LUT 墙或被 UART 吞掉，已由 Phase 1/2 实测坐实。
