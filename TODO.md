# TODO — Mandelbrot FPGA Accelerator Debug Issues

## 当前状态

FP64 设计在任何配置下（2-stage/3-stage, ce_div=1/2/4, PIPE_WAIT=1/2/3）都产生**完全相同的 45.02% (8643/19200) 匹配率**。结果具有确定性——相同输入永远产生相同输出——但计算错误。

RTL 仿真 (`sim/tb_fp.v`) 证明 fp_mul 和 fp_add 的**逻辑完全正确**。2.5×2.5=6.25 产生正确的 exp=1025, man=0x9000000000000。

---

## Issue #1: DSP 时序违规 [根因已确认]

### 现象

- Vivado 报告 WNS ≈ -3.8ns @ 100MHz
- `z_re_sq[51]`（6.25 尾数 MSB）在硬件上为 0，仿真中为 1
- `quick_esc()` 对于 exp=1025 且 man≠0 的值（如 6.25）返回 false
- 对于 exp>1025 的值（如 9.0, 16.81），逃逸检测正常工作

### 定位

DSP48E1 的 53×53 级联乘法器输出到 man_product_r 寄存器的组合路径约 12-15ns，在 100MHz (10ns) 下无法收敛。CE 分频 (`ce_div=2/4`) 在硬件上给足了时间，但 Vivado 的综合器不做 CE 感知的时序分析，始终按单周期 (10ns) 评估。导致 stage1 寄存器捕获未稳定的 DSP 输出——对于某些 bit pattern（如 6.25 的 0x9000000000000），关键尾数位恰好落在违规路径上，被捕获为 0。

### 为什么 CE 分频无效

`ce_div=2` 时 CE 每 2 拍 1 次，硬件有 20ns。但 Vivado 分析路径 `core_reg → DSP → fp_mul_stage1_reg` 时，源寄存器和目标寄存器都在 `posedge sys_clk` 上更新——工具只看到 10ns 周期，不感知 CE 门控逻辑。

### 修复方案

**方案 A（推荐）**：用 `(* mult_style = "pipe_block" *)` 或在 DSP 乘积后显式插入一级寄存器，强制 Vivado 使用 DSP48E1 的内部 MREG/PREG 流水寄存器。将 DSP 级联的 12ns 路径切为两条 < 5ns 的 reg-to-reg 路径。

改动：
- `fp_mul.v`: 在 `man_product` 和 `man_product_r` 之间插入 `man_product_dsp <= man_product` 寄存器
- 同时给 fp_add 加一级输入寄存器 (`a_r <= a; b_r <= b;`)
- `mandelbrot_core.v`: `PIPE_WAIT = 2`（或 `3`，取决于最终流水级数）
- 验证：`pipe_wait` 递减逻辑需要正确处理复位后的首个 ce 周期（确保不会在复位期间开始处理）

**方案 B**：用 MMCM/PLL 从 100MHz 生成真 50MHz 时钟域，将整个 FP 单元和 core 状态机放入 50MHz 域。UART 留在 100MHz 域，FIFO 做 CDC。

**方案 C**：添加正确的 `set_multicycle_path` 约束（之前尝试失败，regex 未匹配到网表中的 cell 名称）。

---

## Issue #2: 3-stage 流水线结果更差 [待查]

### 现象

将 fp_add 拆为 3 级（对齐 | 加减+LZC | 规范化）、fp_mul 拆为 3 级后，PIPE_WAIT=2。结果从 2-stage 的 81%（4×4 测试）降到 63%。

### 推测

3-stage 版本的 fp_add 可能存在内部流水寄存器对齐 bug。具体来说，`man_small_aligned_s1`（Stage1 捕获的对齐后较小尾数）在 Stage2 进行加减时可能与 `same_sign_s1` 不匹配（两者捕获自不同流水级）。

### 修复方向

- 写完整的 core 级仿真测试台，逐一验证每个迭代的中间值
- 或用 2-stage fp_add + 3-stage fp_mul 的混合方案：fp_add 保持 2 级（时序余量较大），仅加速 fp_mul

---

## Issue #3: 大图输出混乱 [关联 Issue #1]

### 现象

160×120 图像渲染后为竖条纹状乱码，无 Mandelbrot 分形结构。

### 分析

- 条纹来自大部分像素输出 max_iter (=256=0x0100 → bytes 0x00 0x01 重复)
- 少数像素触发逃逸（iter=1），产生不同值
- 这导致同一列中大部分像素同色、偶有异色 → 竖条纹视觉效果
- 根因是 Issue #1：DSP 乘积累积输出 0 或错误小值，逃逸检测几乎全失效

### 修复

Issue #1 修复后应自然解决。若修复后仍有条纹，则需排查：
- pixel 中心计算（int2fp 函数）
- c_re 增量累加精度
- FIFO 溢出/数据错位

---

## Issue #4: 像素中心与软件不匹配 [已知偏差]

### 现象

HW 用 `half_w = (cols-1)>>1`（整数截断），SW 用 `(width-1)/2.0`（浮点）。两者差 0.5 像素，对于 160×120@step=0.005 差 0.0025 复平面单位。

### 影响

单独测试：两种中心法在 160×120 图上有 93.66% 像素相同。仅 6.3% 差异。不是当前 55% 错误的主因。

### 修复

Issue #1 修复后，可在 Python 验证代码中改用 HW 中心法（整数 half_w），或修改 HW 使用浮点半宽。

---

## 待做列表

| 优先级 | 任务 | 阻塞 |
|--------|------|------|
| P0 | fp_mul 加 DSP 输出寄存器 + fp_add 加输入寄存器 + PIPE_WAIT 对齐 | — |
| P0 | 验证 c=2.5 逃逸检测通过 | P0 |
| P1 | 160×120 全图验证 (SW 用 HW 中心法) | P0 |
| P1 | 时序收敛 (WNS ≥ 0) | P0 |
| P2 | FP128 综合测试 (资源占用 + 时序) | — |
| P3 | 上位机 GUI / 实时缩放 | — |
