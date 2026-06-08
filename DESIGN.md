# Mandelbrot FPGA Accelerator — 设计文档

> Historical design notes. Some timing notes below describe earlier iterations of the design. The current validated configuration is documented in `README.md` and `ARCHITECTURE.md`: FP64, `FP_CE_DIV=1`, true 100 MHz core operation, 460800 baud UART.

## 1. 使用过程

### 1.1 上位机 Python 脚本

```
python mandelbrot_host.py [参数]
```

| 参数 | 说明 | 默认值 |
|------|------|--------|
| `--center RE IM` | 复数中心点 | -0.5 0 |
| `--step S` | 每像素步长 | 0.005 |
| `--max-iter N` | 最大迭代次数 (≤65535) | 256 |
| `--width W` | 图像宽度 | 160 |
| `--height H` | 图像高度 | 120 |
| `--output PATH` | 输出文件 | mandelbrot.png |
| `--format png/bmp/txt` | 输出格式 | png |
| `--mode fp64/fp128` | 精度模式 | fp64 |
| `--verify` | 软件校验 | 否 |
| `--port COMx` | 串口号 | COM4 |

示例：
```bash
# 小图快速测试
python mandelbrot_host.py --center -0.5 0 --step 0.005 --max-iter 200 --width 160 --height 120

# 大图渲染
python mandelbrot_host.py --center -0.5 0 --step 0.002 --max-iter 500 --width 640 --height 480 --output m.png

# 纯文本输出
python mandelbrot_host.py --center -0.7 0 --step 0.1 --max-iter 64 --width 80 --height 40 --format txt

# 带软件校验
python mandelbrot_host.py --verify
```

### 1.2 FPGA 构建 & 烧写

```bash
# FP64 构建
vivado -mode batch -source build_fp64.tcl

# FP128 构建
vivado -mode batch -source build_fp128.tcl

# 烧写 (自动检测 bitstream)
vivado -mode batch -source program.tcl
```

---

## 2. 项目结构

```
Mandelbrot/
├── rtl/                         # RTL 源文件
│   ├── fp_defines.vh            # FP 参数宏定义 (FP64/FP128 切换)
│   ├── top.v                    # 顶层集成
│   ├── uart_rx.v                # UART 接收器 (115200 8N1)
│   ├── uart_tx.v                # UART 发送器
│   ├── queue.v                  # 参数化 FIFO (128×16bit)
│   ├── cmd_parser.v             # 二进制协议解析器
│   ├── tx_ctrl.v                # 响应数据发送控制器
│   ├── mandelbrot_core.v        # Mandelbrot 计算核心 (状态机+FP单元调度)
│   ├── fp_add.v                 # 参数化浮点加法器
│   └── fp_mul.v                 # 参数化浮点乘法器
├── constraints/
│   └── constraint.xdc           # 引脚约束 + 时钟约束
├── build_fp64.tcl               # FP64 Vivado 构建脚本
├── build_fp128.tcl              # FP128 Vivado 构建脚本
├── program.tcl                  # JTAG 烧写脚本
├── sim/
│   └── tb_fp.v                  # FP 单元仿真测试台
├── python/
│   ├── mandelbrot_host.py       # 上位机 Python 脚本
│   ├── test_esc.py              # 逃逸检测测试
│   └── test_center.py           # 像素中心比较测试
├── fp64_proj/                   # FP64 Vivado 项目
└── fp128_proj/                  # FP128 Vivado 项目
```

---

## 3. 设计思路

### 3.1 粗粒度任务卸载

UART 带宽仅 ~11.5KB/s (115200bps)，是系统瓶颈。为最小化协议开销：

- **一次命令 = 一整幅图像**：Host 发送中心点、步长、最大迭代数、图像尺寸后，FPGA 自行计算全部像素并通过 UART 返回。
- **像素级流水**：无需存储整幅图像，计算一个像素即通过 FIFO→UART 发出一个像素。
- **16-bit 迭代计数**：每像素 2 字节 (uint16 LE)，最大 65535 次迭代。

### 3.2 二进制协议

**Host → FPGA（33 bytes FP64 / 57 bytes FP128）：**

| 偏移 | 大小 | 字段 |
|------|------|------|
| 0 | 1 | Magic: 0x4D |
| 1 | 1 | Precision: bit0=0→FP64, 1→FP128 |
| 2-3 | 2 | rows (uint16 LE) |
| 4-5 | 2 | cols (uint16 LE) |
| 6-7 | 2 | max_iter (uint16 LE) |
| 8.. | 8/16 | center_re (FP64/FP128 LE) |
| | 8/16 | center_im |
| | 8/16 | step |
| -1 | 1 | Checksum (XOR of bytes 0..N-1) |

**FPGA → Host（6 + 2×rows×cols + 1 bytes）：**

| 偏移 | 大小 | 字段 |
|------|------|------|
| 0 | 1 | 0x52 ('R') |
| 1 | 1 | 0x4B ('K') |
| 2-3 | 2 | rows (uint16 LE) |
| 4-5 | 2 | cols (uint16 LE) |
| 6.. | 2×N | pixel data (uint16 LE per pixel) |
| -1 | 1 | Checksum (XOR of bytes 2..N+5) |

### 3.3 模块化架构

```
                  ┌──────────┐
  UART_RX ───────►│cmd_parser│────► center_re/im, step, max_iter, rows, cols
                  └──────────┘              │
                                        ┌───▼──────────┐
                                        │mandelbrot    │
                                        │   _core      │
                                        │              │──► fifo_wr → [FIFO] → tx_ctrl → UART_TX
                                        │ ┌──────────┐ │
                                        │ │ fp_mul   │ │
                                        │ │ fp_add   │ │
                                        │ └──────────┘ │
                                        └──────────────┘
```

### 3.4 精度切换

通过 Verilog `define FP128_MODE` 宏实现编译时切换。`fp_defines.vh` 定义位宽、指数偏置等参数。`build_fp128.tcl` 使用 `set_property verilog_define {FP128_MODE}` 配置。

---

## 4. RTL 详细设计

### 4.1 浮点格式

内部使用类 IEEE 754 格式（不支持 denormal/NaN/Inf，遇零刷新为零）：

| 参数 | FP64 | FP128 |
|------|------|-------|
| 总位宽 | 64 | 128 |
| 符号位 | 1 | 1 |
| 指数位 | 11 | 15 |
| 尾数位 | 52 | 112 |
| 指数偏置 | 1023 | 16383 |

### 4.2 fp_mul（浮点乘法器）

**算法**：
1. `sign = s_a ^ s_b`
2. `exp_sum = e_a + e_b`, 检测下溢 (`< BIAS`) 和上溢 (`≥ MAX`)
3. `man_prod = (1.ma) × (1.mb)` → 2×(MAN_W+1) 位积
4. 规范化：若 MSB=1（积 ≥ 2.0），右移 1 位，指数 +1
5. 取 `[MAN_W-1:0]` 为结果尾数

**流水线（2级）**：
- Stage1: 寄存器捕获 DSP 乘积 + 符号 + 指数和
- Stage2: 规范化组合逻辑 → 输出寄存器

**时序瓶颈**：Stage1 的 DSP48E1 53×53 级联输出到寄存器路径约 12-15ns，在 xc7z010-1 上无法闭合 100MHz。

### 4.3 fp_add（浮点加法器）

**算法**：
1. 检测零操作数，记录到旁路寄存器
2. 比较指数，确定较大者。`diff = e_large - e_small`
3. 对齐：较小尾数右移 diff 位（最多 MAN_W+2 位）
4. 加减：`man_result = man_large ± man_aligned`
5. 前导零检测（LZC），确定左移量
6. 规范化移位 + 指数调整
7. 零旁路：若操作数为零，直接输出另一操作数

**流水线（2级）**：
- Stage1: 对齐 + 加减 → 寄存器 + 输入寄存（a_store, b_store 用于零旁路）
- Stage2: LZC + 规范化 → 输出寄存器

**关键设计**：零旁路必须使用流水线对齐的寄存器值（a_store/b_store 与 man_result_r 同一拍捕获），否则读到错拍的输入值。

### 4.4 mandelbrot_core（计算核心状态机）

**主循环（每像素）**：

```
S_ITER_START: z=0, iter=0, mul_a=0, mul_b=0
  ↓ (PIPE_WAIT)
S_MUL_ZRSQ_CAPT:  z_re_sq = z_re²,   mul_a=z_im, mul_b=z_im
  ↓
S_MUL_ZISQ_CAPT:  z_im_sq = z_im²,   mul_a=z_re, mul_b=z_im,
                   add_a=z_re_sq, add_b=z_im_sq  (escape add)
  ↓
S_MUL_ZRZI_CAPT:  z_re_z_im = z_re×z_im,
                   quick_esc(z_re_sq) || quick_esc(z_im_sq) || quick_esc(add_result)
                     → escaped: S_OUTPUT_WAIT
                     → else: add_a=z_re_sq, add_b=z_im_sq, add_neg=1 (subtract)
  ↓
S_SUB_RE_CAPT:    add_a=diff, add_b=c_re (z_re_next)
  ↓
S_ADD_NEXTRE_CAPT: z_re = z_re_next
                   add_a=z_re_z_im, add_b=z_re_z_im (2x)
  ↓
S_ADD_2X_CAPT:    add_a=2x, add_b=c_im (z_im_next)
  ↓
S_ADD_NEXTIM_CAPT: z_im = z_im_next, iter++
  ↓
S_ITER_INC:       if iter ≥ max_iter → S_OUTPUT_WAIT
                  else → mul_a=z_re, mul_b=z_re → S_MUL_ZRSQ_CAPT
```

**逃逸检测** `quick_esc(val)`：
- 若 `exp > BIAS+2`（值 > 4.0）→ 逃逸
- 若 `exp == BIAS+2 && man ≠ 0`（值 > 4.0）→ 逃逸
- 三重检测：同时检查 `z_re_sq`, `z_im_sq`, `add_result(z_re_sq+z_im_sq)`

**像素遍历**：
```
S_OUTPUT → fifo_wr=1, add_a=c_re, add_b=step → S_NEXT_COL
S_NEXT_COL → c_re+=step, col++ → next pixel or S_NEXT_ROW
S_NEXT_ROW → c_im-=step, row++, c_re=c_re_start → next row or S_DONE
```

**初始化**：
```
half_w = (cols-1)>>1; half_h = (rows-1)>>1
re_offset = int2fp(half_w) × step
c_re_start = center_re - re_offset
// 同理计算 c_im_start
```

### 4.5 CE 门控流水线时序

```
PIPE_WAIT 机制：
  setup_state:  pipe_wait = PIPE_WAIT,  state = NEXT
  wait_cycles:  pipe_wait 递减 (仅 ce=1 时)
  capture_state: pipe_wait == 0, 捕获 FP 结果

FP 流水线与 core 的同步：
  core 在 ce 周期 N 设置 mul_a/mul_b → FP 在 N 拍捕获旧值
  → N+1 ce 拍捕获新值 → 经过 STAGES 拍流水 → core 在 N+1+PIPE_WAIT 拍读取
```

### 4.6 UART 协议处理

- **cmd_parser**：非 ce 门控，始终监听 UART。接收 33/57 字节命令，XOR 校验，解析后触发 `compute_start`。
- **tx_ctrl**：非 ce 门控。`start` 脉冲触发后发送 `RK` 头 + 像素数据 + 校验和。`tx_en` 采用握手协议（等待 `tx_avail=0` 后释放），适配 UART 的 `pseudo_clk` 跨时钟域。
- **start_latched**：由于 core 仅在 ce=1 时检测 `start`，而 `compute_start` 可能在 ce=0 时产生——因此用 `start_latched` 寄存器在非 ce 门控时钟域捕获。

---

## 5. FP128 模式

通过 `build_fp128.tcl` 构建。FP_CE_DIV=4（25MHz 有效速率）。113×113 位乘法器将消耗约 35 个 DSP48E1 和大量 LUT。在 xc7z010-1 上资源紧张但可综合。功能正确性取决于 DSP 时序是否能收敛（FP128 的 114 位加法器 + 桶形移位器关键路径）。
