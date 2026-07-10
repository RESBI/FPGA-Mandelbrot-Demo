# Mandelbrot FPGA 加速器 — 设计审查与优化报告

> 本报告基于对 `rtl/`、`doc/`、`python/`、构建脚本与既有阶段报告的完整阅读后给出。基准点为当前默认 `fp64_rtr8_proj` 比特流（ZU4EV `xczu4ev-sfvc784-1-i`，direct 200MHz，12 worker × 8 context，FP64，`MUL_LAT=6`/`ADD_LAT=9`，`RESPONSE_TILE_ROW_SPLITS=8`，12 Mbaud）。
>
> 实测基准（该比特流 routed）：`WNS=0.103ns / WHS=0.010ns`，CLB LUT `85698/87840 = 97.56%`，CLB Reg `71473/175680 = 40.68%`，BRAM `25.5/128 = 19.92%`，DSP48E2 `123/728 = 16.90%`。

---

## 1. 项目设计意图

该项目是一个 UART 控制的 Mandelbrot 集合渲染加速器，核心设计哲学是“流式计算、零帧缓存”：

- **粗粒度任务卸载**：Host 一次 UART 命令携带 `center/step/max_iter/rows/cols`，FPGA 算完整幅（或一个 tile）并流式回传 `uint16` 迭代计数。
- **像素级流水**：不存整帧；算出一个像素即 `worker FIFO → raster collector → 输出 FIFO → tx_ctrl → UART`。
- **多 worker + 每 worker 多 context**：12 个 worker 并行处理不同行；每个 worker 用 1 个 FP64 乘法器 + 1 个 FP64 加法器，靠 8 个像素 context 的标记式 (tagged) 时间复用来掩盖 `MUL_LAT=6`/`ADD_LAT=9` 的 FP 流水延迟。
- **动态行调度 + 严格光栅回收**：`work_dispatch_dynamic_rows` 把“一整行”派给首个空闲 worker 并记录行主；`raster_collect_dynamic_rows` 用 owner 表按光栅序回收，恢复 Host 可见的行主序。
- **可靠传输层**：`tx_ctrl` 把响应切成 `RT / TD×N / TE` 的分块协议，`TD` 全宽行切片 (`M=8`) 各带独立 payload XOR 校验；Host 侧默认 host-tile `1920x120`，区分“仅校验和失败”与“帧错”两类恢复。

设计意图清晰、层次分明（计算 / 调度 / 回收 / 传输 / 协议解耦），是一份工程化程度很高的 FPGA 加速器实现。

---

## 2. 设计思路审查（做得好的地方）

| 维度 | 评价 |
|---|---|
| **时钟域** | 单 200MHz `sys_clk` + `BUFG`，`fp_ce` 仅作编译期节流 (`FP_CE_DIV=1`)，无 core/UART CDC，STA 直接、复位简单。正确。 |
| **FP 单元** | `fp_mul`/`fp_add` 均有多级寄存（输入/解码/DSP/对齐/规格化/输出），`mult_style=pipe_block`，DSP 友好；加法器把“比较选择/对齐加减/前导零/输出”切成多级，是 200MHz 能闭合的关键。 |
| **worker 去气泡** | 用 tagged 延迟线 (`mul_op_pipe/mul_ctx_pipe`, `add_op_pipe/add_ctx_pipe`) 按 `MUL_LAT/ADD_LAT` 把结果路由回正确 context，替代旧单 context 的 `PIPE_WAIT` 保守等待，方向正确。`PIPELINE_BUBBLE_ANALYSIS.md` 的模型与板上 80–85% 拟合度佐证了建模可信。 |
| **ordered commit** | 每个 worker 按 `commit_col` 局部列序提交，保证 per-core FIFO 仍是行内列序，下游 raster collector 协议不变。正确且必要。 |
| **动态调度防死锁** | 派发器在“该 core FIFO 为空”时才复用该 core 的新行，避免 UART 反压下“未来行填满 FIFO 而回收器在等更早行”的死锁。这是关键的工程细节。 |
| **大帧 32-bit 像素数** | `total_pixels = {16'd0,rows}*{16'd0,cols}` 显式 32 位，修了 >65535 像素帧的溢出 bug。 |
| **软复位** | `RST!RST!` 在任意 parser 状态识别，脉冲复位解析器/核/FIFO/tx_ctrl，Host 失败后可重同步。实用。 |
| **分块响应** | 把“检测”与“恢复”分离：FPGA 只做包边界 + 局部校验，不参与双向 ACK；Host 做恢复。保持 UART 单向流简单。架构上克制。 |
| **owner 表代际标记** | `raster_collect_dynamic_rows` 用 `frame_gen` 单 bit 翻转区分新旧帧的 owner 条目，避免每次清表。巧妙。 |
| **可配置性** | `config.vh` 集中默认 + `ifndef` 守护 + Vivado generic 覆盖，便于扫参。 |

---

## 3. 发现的问题、瓶颈与风险

### 3.1 计算侧：单 context 仍有大量气泡，且加法器是瓶颈
- 每次非逃逸迭代需 **3 乘 + 5 加**；`1M+1A` 的理想 issue 极限是 `max(3/1,5/1)=5` 拍/迭代。
- 8 context 已接近 `1M+1A` 饱和起点，但**加法器** (`ADD_LAT=9` 且 5 次/迭代) 才是真正瓶颈；`PIPELINE_BUBBLE_ANALYSIS.md` 模型显示第二个 ADD 要到约 **16 context** 才显著见效，第二个 MUL 几乎无用。
- **内点浪费**：集合内点（主心形 + period-2 bulb）必然跑满 `max_iter`。deep mini-brot @8192 = 9.166s 主要就是内点在烧 8192 次迭代。当前**没有任何几何早退**。

### 3.2 资源/时序：已触 LUT/布线天花板
- `97.56%` CLB LUT；最差路径是 `u_cmd/step_reg → worker step_val_reg` 的**参数高扇出布线**（~98% route delay，0 LUT level），不是算术路径。
- 直接加 worker 或加 FPU lane 风险高；generic scoreboard 的宽 64-bit 操作数 mux / N-way ready 扫描 / writeback demux 是 LUT 大户，扩 context 成本陡增。

### 3.3 传输侧：UART 是天花板且不可重传
- 12 Mbaud 理论 payload 上限 ~600k pps；fast/standard 场景已 ~545k pps，接近上限，**任何计算优化在浅场景都看不见**。
- `TD` 仅 payload XOR 校验，头字段靠语义检查；无 request_id / 序号 → 旧/错位包只能靠“drain 到静默 + 严格命令序”规避，不能显式判重/判序。
- 失败只能**重算** compute tile，FPGA 不缓存已发包 → 一次单字节 slip 可能重算整块 `1920x120`。

### 3.4 RTL 具体问题（按文件）

**`mandelbrot_core_worker_kctx.v`**
- L46–47：`MUL_LAT=6`/`ADD_LAT=9` 是**硬编码 localparam**，与 `fp_mul/fp_add` 实际级数耦合但无编译期断言；改 FP 流水级数时极易踩错（历史已踩过 `11/11` 与 `7/8` 的 tag 错拍 bug）。
- L765/800/838/858：`issue_base = launch_col[CTX_W-1:0]` 用 `launch_col` 低位作轮转起点——`CONTEXTS` 必须是 2 的幂（8 满足，但 `& (CONTEXTS-1)` 隐含该约束，未在参数处断言）。若有人设 `CONTEXTS=12` 会静默错。
- L751/756：`max_iter==0` 时直接 `c_result_valid=1`/`C_DONE`，逻辑对，但 `c_mul_ready<=(max_iter!=0)` 与 `c_state<=(max_iter==0)?C_DONE:C_NEED_ZRSQ` 分两处写，可读性弱。
- L66/L672/762：`half_w` 在 `S_INIT_LATCH` 与 `AOP_INIT_W_SUB` 写回处各算一次 `(cols-1)>>1`，重复且分散。
- 初始化序列 `S_INIT_*` 占 ~8 个状态串行跑 4 次 FP（half_w*step, center_re-, half_h*step, center_im+, row_stride*step, row_start*step, c_im_top-），**每个 worker 每行都重算一遍** `c_re_start/c_im_top/row_step`——这些其实对同一命令是常量，可在 `mandelbrot_multicore` 层算一次广播给所有 worker，省掉每 worker/每行的 ~8 拍初始化。深场景每行只有 ~cols 个像素，这部分开销在窄 tile 下占比不小。

**`work_dispatch_dynamic_rows.v`**
- L54–68：每拍只派 1 行（`assigned=1` 即 break）；`core_done_block` 的逻辑 `<= (core_done_block | core_done) & core_done` 语义晦涩（实质是“仅当本拍 done 拉高时保留 done 屏蔽”，用于避免 done 尖刺重复派发），无注释，易误改。
- 派发只在 `!core_fifo_avail[i]`（FIFO 空）时复用——正确但保守：意味着一个 worker 算完一行后必须等 FIFO 被回收器抽空才能接下一行，**UART 慢时 worker 会被反压空转**，降低计算并行度（这是为防死锁的刻意取舍，但限制了深场景的 worker 占用率）。

**`raster_collect_dynamic_rows.v`**
- L43–44：`owner_mem` 4096×4bit + `owner_gen` 4096×1bit = 显式 reg 数组，**未加 `(* ram_style="block" *)`**，综合可能塞进分布式 RAM/LUT 而非 BRAM，加剧 LUT 压力（当前 97.56% LUT 里很可能含这块）。
- L94–96：`S_READ_WAIT` 固定 1 拍（同步 FIFO 读延迟），每像素消耗 `S_WAIT→S_READ_WAIT→S_WRITE` 至少 3 拍；UART 12Mbaud 每 16-bit 像素 ~3.33µs ≈ 667 拍，回收器远快于 UART，不是瓶颈，但 `fifo_full` 时 `S_WRITE` 会回 `S_WAIT` 而非原地等，略多一次状态切换。

**`tx_ctrl.v`**
- L248–262：`S_TILE_CKSUM` 与 `S_TILE_GAP` 之间，`RESPONSE_TILE_GAP_CYCLES=1000`（~5µs）每包都插；8 包/响应 × 多响应 → 累积可观。对 12Mbaud 稳定性有帮助，但可在“无失败历史”时动态缩短。
- L201–208：`S_READ_FIFO` 在 `pixel_idx>=tile_pixels` 时跳 `S_TILE_CKSUM`，但若此时 `fifo_avail` 仍为 1 也不读——逻辑对，但 `fifo_rd` 是组合赋值在 `S_READ_FIFO` 内，`data_out` 下一拍才有效（`S_READ_WAIT`），序列正确。
- 无 request_id / 包序号（见 3.3）。

**`cmd_parser.v`**
- L125：`S_EXEC` 仅在 `!compute_busy` 时 `compute_start<=1`；意味着**前一帧 tx 还在发时新命令会被阻塞**，无法“边发边算下一 tile”。这是 `RETRY_TILE_CACHE_DESIGN.md` 也指出的 blocker，限制了 compute/TX 重叠。

**`queue.v`**
- L19 `reg [DATA_W-1:0] mem [0:DEPTH-1];` 未加 BRAM 属性；`CFG_CORE_FIFO_DEPTH=4096` × 12 个 per-core FIFO + 输出 FIFO 1024，深度足够推断 BRAM，但显式属性更稳。

### 3.5 协议/可靠性缺口
- 无 request_id → 旧包风险。
- `TD` XOR 校验弱（多字节错可能漏）。
- 失败只能重算，无 FPGA 侧重传。
- `cols`/`rows` 16-bit，单命令 ≤65535；owner 表 ≤4096 行（host-tiling 下按 tile 高度受限，已缓解）。

### 3.6 数值
- FP64 类 IEEE、截断 rounding（非 RNE），边界点与 Python 参考有可接受差异；深 zoom <1e-12 起精度敏感，FP128 未充分验证。

---

## 4. 优化方案（按收益/风险/工作量排序）

| # | 方案 | 类型 | 预期收益 | 风险 | 工作量 | 优先级 |
|---|---|---|---|---|---|---|
| **O1** | **主心形 + period-2 bulb 几何早退** | 计算 | deep mini-brot 等“大内点”场景显著（内点从 max_iter 次迭代→常数次）；其它场景不变 | 低（数值等价：内点本就返回 max_iter） | 中 | **P0** |
| O2 | owner 表加 `(* ram_style="block" *)` 并移到 BRAM | 资源/时序 | 释放数百~上千 LUT，缓解 97.56% | 极低 | 小 | P0 |
| O3 | `mandelbrot_multicore` 层预算 `c_re_start/c_im_top/row_step` 广播 | 计算 | 省每 worker/每行 ~8 拍初始化；窄 tile 收益可见 | 低 | 中 | P1 |
| O4 | 低 LUT ring/barrel worker（替代 generic scoreboard） | 架构 | 为 12/16 context 铺路，降 LUT/布线 | 中高（新验证） | 大 | P1 |
| O5 | retry-tile cache（`RETRY_TILE_CACHE_DESIGN.md`） | 可靠性 | 失败包重传而非重算 | 中（协议+RTL+host 同改） | 中大 | P1 |
| O6 | request_id + TD 序号 + CRC-16 | 可靠性 | 显式判重/判序/强校验 | 中 | 中 | P1 |
| O7 | `1M+2A` worker（先 8/10 worker 试） | 计算 | 深场景 1.10–1.30× | 中高（97% LUT 下布线险） | 中大 | P2 |
| O8 | compute/TX 重叠（命令队列 + per-request 缓冲） | 吞吐 | 隐藏 UART 传输期的计算空闲 | 高（架构大改） | 大 | P2 |
| O9 | 更高带宽传输（FT245/SPI/Ethernet/PS） | 吞吐 | 浅场景也能受益 | 高 | 大 | P3 |
| O10 | FP128 保守路径定型 + 验证 | 精度 | <1e-12 深 zoom 可用 | 中 | 中 | P3 |

### 关键判断
- **当前最大单点收益是 O1（几何早退）**：它直接砸向最慢场景 deep mini-brot @8192 (9.166s)，且数值安全、不破协议、可在仿真级先证等价、LUT 增量小（局部逻辑）。
- **O2 是“免费午餐”**：一行属性，可能降 LUT、稳布线，先做。
- **O7/O8/O9 受限于 3.2 的 LUT 天花板与 3.3 的 UART 天花板**，应在 O4（降 LUT）或 O9（换传输）打开空间后再上。

---

## 5. 分阶段执行计划

> 环境：Vivado 2024.2 (`Z:\Softwares\Xilinx\Vivado\2024.2\bin\vivado.bat`)，COM6/FT232HL @12Mbaud，目标 `xczu4ev-sfvc784-1-i`。测试命令参考 `README.md`（小图 `--verify`、1080p 六场景、`test_esc.py` 等）。

- **Phase 0 — 基线复现（不重建）**：用现有 `fp64_rtr8_proj` 比特流烧板，跑 `test_esc.py` + 160×120 `--verify` + 一个 1080p 场景，确认板/串口/工具链闭环，记录实测基线。产出 `Phase 0 报告`。
- **Phase 1 — 资源/时序免费优化 (O2)**：owner 表打 BRAM 属性 + queue 打 BRAM 属性。仿真 → 构建 → 烧板 → 小图 verify + 1080p 对照。验证 LUT 下降且功能/时序不退。产出 `Phase 1 报告`。
- **Phase 2 — 几何早退 (O1)**：worker 加主心形/period-2 bulb 预判，命中则直接 `result=max_iter` 跳过迭代。仿真证 HW/SW 等价（含边界）→ 构建 → 烧板 → 六场景 benchmark，重点看 deep mini-brot。产出 `Phase 2 报告`。
- **Phase 3 — 预算初始化广播 (O3)**：`mandelbrot_multicore` 算一次 `c_re_start/c_im_top/row_step` 广播给 worker，worker 删 `S_INIT_*` 串行链。仿真/构建/烧板/对照。产出 `Phase 3 报告`。
- **Phase 4+**：按 O4/O5/O6 视前序结果与资源余量再定。

每阶段统一门槛：① 行为仿真 PASS；② routed 200MHz 无 setup/hold 违例；③ 资源不劣化；④ 小图 `--verify` 100% 匹配（O1 需证等价）；⑤ 至少一个 1080p 场景 transport pass。

---

## 6. 结论

该设计是一份成熟、工程化、文档完备的 FPGA Mandelbrot 加速器，架构层次清晰、关键工程细节（防死锁派发、ordered commit、tag 延迟线、分块响应、软复位）处理得当。当前主要矛盾是**LUT/布线天花板（97.56%）**与**UART 天花板（~600k pps）**双重夹击下的优化空间收窄。最稳妥的下一步是先拿“免费”的 BRAM 属性优化 (O2) 与数值安全的几何早退 (O1) 兑现可见收益，再以低 LUT ring/barrel worker (O4) 打开 context/FPU lane 的扩展空间，最后才考虑传输换代 (O9) 与 compute/TX 重叠 (O8)。
