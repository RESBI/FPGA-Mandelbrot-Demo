# TODO - Mandelbrot FPGA Accelerator

本文对应 `TODO.md`，记录当前 12 Mbaud、4-worker、dynamic row、tiled response、compute subtile retry 设计之后的后续工作。

## 当前默认配置

| 项目 | 当前值 |
|---|---:|
| 精度 | FP64 |
| 系统时钟 | 100 MHz |
| Worker 数 | 4 |
| 每 worker contexts | 2 |
| 调度 | Dynamic idle-core row scheduler |
| Dynamic owner depth | 每个硬件命令 4096 行 |
| UART | 12000000 baud |
| Response protocol | `RT` / `TD` / `TE` tiled response |
| RTL response tile width | 64 columns |
| Host tiling | 默认开启 |
| 默认 host tile | 全宽，最多 120 行 |
| 默认 compute tile | host tile 内部 `512x120` |
| Retry 单元 | 一个硬件 compute tile |
| Soft reset command | `RST!RST!` |
| 默认串口 | `COM6` |

## 最近已完成

- RTL 默认配置集中到 `../rtl/config.vh`。
- UART RX/TX 改成 32-bit fractional-NCO baud generator。
- 当前 host/RTL 默认 baudrate 为 12 Mbaud。
- `../rtl/tx_ctrl.v` 增加 `RT` / `TD` / `TE` tiled response framing。
- Host parser 同时支持 legacy `RK` 和 tiled response。
- Host-driven tiling 默认开启，`--full-frame` 保留旧单命令路径。
- 增加 `--tile-read-timeout`，避免 byte slip 后等待全局 timeout。
- Host tile 内部增加 compute sub-tiling，默认 retry 单元为 `512x120`。
- 失败 compute tile 记录坐标并单独 retry。
- 增加 UART soft reset command `RST!RST!`，失败重试时默认自动发送。
- 增加 `--soft-reset`、`--no-soft-reset-on-retry`。
- `--quiet` 增加单行进度条，显示 compute tile 和 host tile 计数。
- `queue.v` 增加同步 reset，soft reset 可清 output FIFO 和 per-core FIFO。
- 增加 `4096x120`、host-tiled `4096x4096` 的 `tx_ctrl` 仿真。
- 增加 `cmd_parser` soft reset 仿真。

## P0 - 可靠性和正确性

### Compute Sub-Tile Retry 板级 Soak

之前 30-run 1080p 稳定性数据使用 host-tile retry；当前默认变成 `512x120` compute subtile retry 和自动 soft reset，需要重新板级验证。

任务：

- 用默认 compute sub-tiling 重跑六场景 1080p stability benchmark。
- 记录 retry 次数、恢复的 compute tile 坐标、耗时、是否使用 soft reset。
- 至少跑一次不带 `--verify` 的 `4096x4096` 长图。
- 失败时按既定序列继续记录，不缩小图像或二分边界。

### Request ID 和 Packet Sequence ID

当前依赖 drain-until-quiet 和严格命令顺序；如果旧请求的迟到数据看起来合法，仍有理论污染风险。

任务：

- 在 command 和 response header 中加入 host-generated request ID。
- 在每个 response frame 内给 `TD` 加递增 sequence number。
- request ID 和 sequence ID 纳入 checksum 或 CRC 覆盖。
- Host 明确拒绝 stale、duplicate、skipped、reordered packet。

### 更强 Checksum

当前 `TD` 是 payload-only XOR checksum；header corruption 靠 semantic checks 发现，XOR 对多字节错误较弱。

任务：

- 评估 header+payload 的 CRC-8 或 CRC-16。
- 控制 RTL LUT/时序成本，适配 xc7z010。
- 除非明确移除，否则继续保留 legacy `RK` parser。

### Host Transport 单元测试

Host parser 已经较复杂，应增加不依赖板子的测试。

任务：

- command packet 和 checksum 测试。
- 正常 `RT` / `TD` / `TE` parsing 测试。
- bad magic、short payload、bad checksum、out-of-bounds tile、stale dims、retry bookkeeping 测试。
- host/compute tile 坐标和拼接 seam 测试。
- quiet progress 格式测试。

## P1 - 架构演进

### 从 Recompute Retry 走向 Packet Retransmission

当前一个 `TD` packet 坏掉后需要重算整个 compute tile，因为 FPGA 不保存已发送 packet。

任务：

- 定义双向 ACK/NACK 协议。
- 决定 FPGA 需要缓存最近多少 packet、row 或 compute tile。
- 评估 BRAM replay 成本和 recompute 成本。
- 保留当前简单单向协议作为 fallback build mode。

### 超大图 Streaming/Tiled Writer

Host tiling 解决 FPGA 命令限制，但 Python host 仍把最终图完整存成 list。

任务：

- 用 `array('H')`、`numpy` 或 streaming row buffer 替换 Python object list。
- 增加 tiled PNG/BMP writer 或 raw `uint16` 输出。
- 让 `16384x16384` 不再需要巨大的 Python object list。
- 将 `65536x65536` 视为 streaming-only 目标；raw pixels 就约 8 GiB。

### 更强 Transport

12 Mbaud UART 可用，但长传输仍有 USB/driver byte-slip 风险。

任务：

- 评估 FT245 FIFO、SPI、Ethernet 或 Zynq PS memory-mapped transport。
- 定义 transport-neutral frame layer，让 host parser 可复用。
- UART 保留为最简单 baseline。

### 低 LUT 高 Context Worker

Generic 4/8-context worker 行为仿真通过，但 LUT 超过 xc7z010 容量。

任务：

- 设计低控制/寄存器开销的专用 4-context worker。
- 先复用 1 个 multiplier + 1 个 adder；context 不够前不要增加 FP units。
- 对 4ctx/8ctx 候选重新跑 pipeline simulator 和 RTL sim。
- 高 context `1M+1A` 可行后再评估 `1M+2A`；避免 `2M+1A`。

### FP128 保守路径

FP128 结构存在，但不是当前高性能默认路径。

任务：

- FP128 build 显式走保守配置，例如 static scheduling 或更低 context。
- 记录 FP128 resource/timing。
- 跑 FP128 unit/core sim 和小图 hardware smoke。
- 不影响 FP64 默认性能路径。

## P2 - 性能和体验

### 重新调 compute tile size

现有 tile-size matrix 早于默认 compute sub-tiling。

任务：

- sweep `--compute-tile-width 256/512/1024/2048`，保持 `--tile-height 120`。
- 比较 retry cost、command overhead 和六场景总时间。
- 如果 `512x120` 不是最佳折中，更新默认和文档。

### 降低 Python Host Overhead

Compute tile 更小后，host command/parser 开销更重要。

任务：

- profile receive、unpack、slice assignment、PNG rendering。
- 评估 `array('H')`、`memoryview` 或 `numpy` final buffer。
- 不要在正常 hot path 恢复 duplicate bitmap 检查，除非用于 debug。

### 输出和 UX

任务：

- 增加 named palettes。
- 增加 metadata sidecar JSON，记录参数、timing、retry count、bitstream defaults。
- 增加 raw `uint16` 输出。
- 增加常用 zoom preset。

## 重要回归命令

Host syntax：

```bash
python -m py_compile python\mandelbrot_host.py
python python\mandelbrot_host.py --help
```

RTL regression：

```bash
vivado -mode batch -source sim_multicore_dynamic.tcl
vivado -mode batch -source sim_tx_ctrl_tiled.tcl
vivado -mode batch -source sim_tx_ctrl_host_tiled_4096.tcl
vivado -mode batch -source sim_cmd_parser_soft_reset.tcl
```

小图板级验证：

```bash
python python\mandelbrot_host.py --verify --width 160 --height 120 --max-iter 256 --output python\verify_160x120.png
```

1080p transport smoke：

```bash
python python\mandelbrot_host.py --port COM6 --width 1920 --height 1080 --max-iter 128 --center 1.0 1.0 --step 0.002 --timeout 600 --tile-width 1920 --tile-height 120 --compute-tile-width 512 --compute-tile-height 120 --tile-retries 3 --quiet --output python\hw_1080p_transport_smoke.png
```

4096 大图 smoke，不带 software verify：

```bash
python python\mandelbrot_host.py --port COM6 --width 4096 --height 4096 --max-iter 8192 --center -0.743643887037151 0.13182590420533 --step 1.2e-09 --timeout 3600 --quiet --output python\hw_4096x4096_smoke.png
```
