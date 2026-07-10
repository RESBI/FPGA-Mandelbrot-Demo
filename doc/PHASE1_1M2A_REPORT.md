# Phase 1 报告 — `1M+2A` 加法器 lane 实验（构建不可行）

> 目标：按 `VMC_RTSB_ZU4EV_200MHZ_OPT_REPORT.md` 推荐的“下一步可行实验”，验证在 8 context 下增加第二个 FP64 加法器是否能在板上兑现深场景收益。该路径的 RTL（`mandelbrot_core_worker_kctx.v` 的 `add1_*`/`g_add1` 分支）与构建脚本（`build_fp64_zu4ev_c8_w8_a2m1.tcl`）已预置但从未上板。

## 1.1 仿真门（先于构建）

```
vivado.bat -mode batch -source sim_multicore_dynamic_contexts.tcl \
  -tclargs WORKER_CONTEXTS=8 WORKER_ADD_UNITS=2 WORKER_MUL_UNITS=1 \
  CORE_COUNT=8 ROWS=12 COLS=160 MAX_ITER=256 CORE_FIFO_DEPTH=4096 TIMEOUT_CYCLES=30000000
→ === DYNAMIC MULTICORE TEST PASS: 1920 pixels ===
```
`add1` 写回路径功能正确（与既有 `multicore_dynamic_c8_ctx8_a2m1_sim_proj` 的历史 PASS 一致）。仿真门通过，进入构建。

## 1.2 构建

```
vivado.bat -mode batch -source build_fp64_zu4ev_c8_w8_a2m1.tcl
→ Synthesis finished with 0 errors, 0 critical warnings
→ ERROR: [DRC UTLZ-1] Resource utilization: LUT as Logic over-utilized in Top Level Design
   (requires 93971 of such cell types but only 87840 compatible sites are available)
→ place_design failed; impl_1 FAILED
```

| 阶段 | 结果 |
|---|---|
| 综合 | 0 error，但需 **93971 LUT-as-Logic** |
| 布局 DRC | **失败**：93971 > 87840（器件上限） |
| 比特流 | 未生成 |

## 1.3 失败解读

- 基线 `12w/8ctx/1A` = 85698 LUT（97.56%）。`8w/8ctx/2A` = 93971 LUT，**超出器件 6140 LUT**。
- 反推第二加法器代价：8w/1A 外推约 57132 LUT；8w/2A = 93971 → 第二加法器 lane 为 8 个 worker 共增加约 **36839 LUT（~4605 LUT/worker）**。
- 这与设计报告 3.2 节的判断一致：generic scoreboard 加第二加法器会**复制 64-bit 操作数 mux、ready 扫描、tag 延迟线、writeback demux**，是 LUT 大户；在当前 97.56% 占用下无法容纳。
- 综合日志另确认 `owner_mem`、`owner_gen`、各 `u_fifo/mem` **已被推断为 Block RAM**（`Synth 8-7052` INFO），故原报告 O2（强制 owner 表入 BRAM）**无收益可拿**——Vivado 已自动推断。97.56% LUT 几乎全是纯逻辑（scoreboard mux/扫描/控制/参数扇出），非 RAM。

## 1.4 与模型的对照

`PIPELINE_BUBBLE_ANALYSIS.md` 模型预测“8 context 下 1M+2A 相对 1M+1A 无收益（context 仍是瓶颈，第二 ADD 要到 ~16 context 才显著）”。本阶段**未能在板上证伪或证实**——因为构建本身不可行。但构建失败这一事实本身比模型预测更强：在 ZU4EV 上，generic 8ctx worker **连第二加法器都放不下**，更谈不上验证其收益。

## 1.5 结论与方向修正

- `1M+2A` 在当前 generic scoreboard + ZU4EV 上**不可部署**（LUT 超 6140）。
- 降 worker 到 6 或降 context 到 4 虽能塞下，但模型已指出 8ctx 以下 2A 无收益，且 worker 减半会重创深场景，无实测价值。
- **真正的计算提升路径被确认为 O4（低 LUT ring/barrel worker 重写）**：只有先把每 context 的宽 mux/扫描/demux 换成固定槽位 barrel，才能在 LUT 预算内塞入更多 context（计算杠杆）或更多 FPU lane。
- 数值安全的几何早退（O1）经 Phase 0 复核对深场景无效（视野无主集合）、对浅场景被 UART 封顶，已降级。

## 1.6 下一阶段（Phase 2）选择

鉴于：① 计算侧加法器/加 context 均撞 LUT 墙；② 几何早退对深场景无效；③ 周期性检测数值不安全——Phase 2 选择一项**可证明数值等价、LUT 中性偏负、可构建可上板**的优化以维持“构建-烧板-测试”闭环：

**Phase 2 = 平方项早退（early escape on squares）**：在 `MOP_ZISQ` 写回时，若 `quick_esc(z_re²)||quick_esc(z_im²)` 已成立，则直接判定逃逸、跳过后续的 magnitude add 与 `z_re*z_im` mul。该项与现行逃逸检测的前两项完全相同，只是提前一步行动并省去冗余 FP 操作；需要 `add_result`（平方和）才判逃逸的像素仍走原路径，故**输出逐像素不变**，可在仿真级证等价。预期对“快速逃逸”类场景（多数像素在第 1~2 次迭代的平方项即逃逸）减少每像素 ~2 次 FP 操作；深场景几乎不变。无论板上是否可见收益，结果都有定论价值。
