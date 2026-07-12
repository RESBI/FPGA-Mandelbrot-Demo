# Mandelbrot PL-PS DDR 加速器设计文档

> 当前目标：计算阶段将像素流写入 PS DDR，下载阶段由 PL 通过 AXI 读回 DDR，再以现有 `RT/TD/TE` 格式经 UART 返回 Host。XSDB/JTAG 只负责初始化 PS DDR 和烧录 bitstream，不属于像素数据通路。
>
> **规范优先级**：第 0 章和第 13 章描述当前实现，是权威规范。第 1-12 章保留早期双缓冲提案作为设计演进记录；其中 `tile_cache_db`、`COMPUTE_DONE`、`ALL_DONE`、`RETRY_TILE`、自动遍历全部 tile 等内容未实现，与第 0/13 章冲突时以后者为准。

## 0. 当前实现规范

### 0.1 目标数据流

```text
计算阶段:
Host UART COMPUTE_TILE
  -> mandelbrot_multicore
  -> 1024x16 output FIFO
  -> axi_ddr_writer (AXI AW/W/B)
  -> PS DDR
  -> ACK + TILE_DONE

下载阶段:
Host UART ENTER_DOWNLOAD(base, rows, cols)
  -> axi_ddr_reader (AXI AR/R)
  -> 16x64-bit beat FIFO + 64-to-16 lane serializer
  -> tx_ctrl
  -> RT / TD / TE
  -> UART
  -> Host
```

计算阶段和 UART 下载阶段互斥。Host 对 compute tile 使用 stop-and-wait：收到 `ACK` 和 `TILE_DONE` 后才提交下一 tile。当前实现不使用完整 tile BRAM cache，不支持多个 outstanding compute 命令。

### 0.2 当前控制协议

控制帧统一为：

```text
55 AA TYPE LEN PAYLOAD CHECKSUM
```

校验规则：`TYPE + LEN + PAYLOAD + CHECKSUM == 0 (mod 256)`。

| 方向 | Type | Len | Payload | 当前语义 |
|---|---:|---:|---|---|
| H->F | `0x10 COMPUTE_TILE` | 42 | `center_re(q8.55,s64) center_im(q8.55,s64) step(q8.55,s64) max_iter(u16) rows(u16) cols(u16) ddr_base(u64) tile_id(u32)` | 计算一个连续 row-major tile 并写 DDR |
| H->F | `0x11 ENTER_DOWNLOAD` | 12 | `ddr_base(u64) rows(u16) cols(u16)` | 从指定 DDR tile 读出像素并立即发送一套 `RT/TD/TE` |
| H->F | `0x02 QUERY_STATUS` | 0 | 无 | 返回调试状态 |
| F->H | `0x81 ACK` | 1 | `status(u8)` | `0=OK, 1=BUSY, 2=BAD_ALIGN, 3=BAD_SIZE` |
| F->H | `0x84 TILE_DONE` | 4 | `xor16(u16) status(u8) reserved(u8)` | AXI 写响应完成；`status=4` 表示 AXI 写错误 |
| F->H | `0x90 DEBUG_STATUS` | 13 | 调试字段 | 非稳定应用接口 |

`tile_id` 当前仅为 wire-format 保留字段，RTL 不回传该字段。Host 必须维持单 outstanding 命令，不能依赖 tile ID 做异步关联。

### 0.3 UART 像素协议

下载数据复用现有 `tx_ctrl`：

```text
RT rows(u16 LE) cols(u16 LE)

TD row(u16 LE) col(u16 LE) tile_rows(u16 LE) tile_cols(u16 LE)
   pixels(uint16 LE * tile_rows * tile_cols)
   checksum(XOR8 of pixel bytes)

TE rows(u16 LE) cols(u16 LE)
```

当前 `tx_ctrl` 只按行切分，每个 TD 必须满足 `col=0`、`tile_cols=frame_cols`，各 TD 的 row 范围连续且无重叠。Host 严格验证几何、每个 TD 的 XOR8，以及整个下载 tile 的 XOR16。

### 0.4 DDR 地址和布局合同

- `ddr_base` 是直接送到 AXI 的物理 byte address；RTL 不执行旧提案中的逻辑高地址转换。
- 默认使用 DDR low 区 `0x10000000` 起始地址。
- Host 将 DDR low 安全上限设为 `0x7FF00000`，避开 PS/PMU 保留的顶部 1 MiB。
- compute/download tile 基址必须 128-byte 对齐。
- writer 固定使用 16 beat x 8 byte = 128 byte burst；最后不足部分写零 padding。
- Host 为每个 tile 分配 `slot_bytes = align_up(rows * cols * 2, 128)`，避免 padding 覆盖下一 tile。
- 每个 AXI read burst受 4 KiB 边界限制；最后 64-bit beat 中无效的 16-bit lane 不发送到 UART。
- 像素在 DDR 中为连续 row-major `uint16`，每个 64-bit beat 的 lane 顺序为 `[15:0]`、`[31:16]`、`[47:32]`、`[63:48]`。

### 0.5 正确性检查

- 控制帧：8-bit 二补数累加 checksum。
- UART TD：像素字节 XOR8。
- `TILE_DONE`：writer 输入像素流 XOR16。
- Host 下载完整 DDR tile 后重新计算 XOR16，并与 `TILE_DONE` 对比，覆盖计算输出、DDR 写入、DDR 读取和 UART 回传的端到端路径。
- writer 检查 `BRESP`；reader 检查 `RRESP` 和 `RLAST`。AXI read error 会终止当前下载，Host 不将不完整数据作为有效图像。

### 0.6 当前模块

| 文件 | 当前职责 |
|---|---|
| `rtl/top_with_ram.v` | DDR 顶层、UART 所有权切换、compute/download 阶段控制 |
| `rtl/axi_ddr_writer.v` | output FIFO -> AXI AW/W/B，固定 128-byte burst |
| `rtl/axi_ddr_reader.v` | AXI AR/R -> beat FIFO -> uint16 像素接口 |
| `rtl/cmd_parser_v2.v` | DDR 控制帧、ACK、TILE_DONE、状态查询 |
| `rtl/tx_ctrl.v` | DDR 下载阶段生成 `RT/TD/TE` |
| `python/mandelbrot_host.py` | tile 地址规划、计算命令、UART DDR 下载、checksum 和图像拼接 |

### 0.7 当前不支持的旧提案功能

- 完整 tile 双 BRAM 乒乓缓存。
- `COMPUTE_DONE` 与 DDR 写入异步流水。
- `ALL_DONE` 自动下载清单。
- `RETRY_TILE` BRAM cache 重发。
- RTL 内逻辑低/高 DDR 地址映射。
- PS 端 Ethernet/USB 推送程序。

---

## 1. 背景与动机

> 本章至第 12 章为早期提案和历史分析，不是当前 wire protocol 或 RTL 合同。当前实现请先阅读第 0 章和第 13 章。

### 1.1 当前瓶颈

fx64 定点重设计已将 worker 数从 12 提升到 24，深场景 mini-brot @8192 加速 1.80×。但浅场景（fast escape、standard）仍被 12Mbaud UART ~600k pps 天花板限制，计算增益不可见。传输瓶颈的根本原因是 UART 串口的 ~1.2 MB/s 带宽。

### 1.2 参考项目 PL-PS-MEM-TEST

`PL-PS-MEM-TEST` 项目验证了在 VMC_RTSB ZU4EV 上通过 PL 端 AXI HP 口访问 PS DDR 的完整路径：

- **AXI 通道**：PL 端 `M_AXI`（64-bit AXI4 Master）→ SmartConnect → `S_AXI_HP0_FPD` → PS DDR 控制器 → 4 GiB DDR4
- **吞吐**：写 509 MiB/s（33.4% 理论峰值），读 454.6 MiB/s
- **空白启动**：`boot_jtag.tcl` 通过 JTAG 直接执行 `psu_init.tcl` 初始化 PS 寄存器（PLL、DDR、时钟、MIO），然后烧录 PL bitstream，无需 FSBL 或 PS 端 C 程序
- **PL 本地复位**：`pl_por.v` 仅依赖 PL 时钟产生 ~5ms 复位脉冲，不依赖 PS `pl_resetn0`（空白启动时 PS 不会释放该信号）
- **DDR 高地址**：构建脚本通过 `enable_ps_ddr_high_address` 强制启用 4 GiB 全量 DDR（低 2GiB @ 0x0–0x7FFFFFFF，高 2GiB @ 0x800000000–0x87FFFFFFF），并验证 `DDR_HIGH` 保护从属端口已打开

### 1.3 设计目标

1. **Host 发送计算指令** → FPGA 计算 tile 像素 → 通过 AXI HP 写入 PS DDR → 通知 Host 进入下一个 tile
2. **计算与 DDR 写入流水化**：使用乒乓双缓冲，tile N 计算与 tile N-1 DDR 写入并行，Host 收到 `COMPUTE_DONE` 即可发下一条命令
3. **所有 tile 计算完成后** → 通知 Host 进入回传阶段
4. **FPGA 端缓存 compute tile** → tile retry 时从缓存取对应 retry tile 部分重发
5. **自洽空白启动**：SoC 处于空白配置时，配置 PS 端 + 烧录 PL bitstream 即可直接运行

---

## 2. 系统总体架构

### 2.1 架构总览

```mermaid
flowchart TB
    subgraph HOST["Host PC"]
        direction TB
        CLI["Python CLI<br/>mandelbrot_host.py"]
        USB["FT232HL USB-UART"]
        CLI --> USB
    end

    subgraph PL["FPGA PL (xczu4ev)"]
        direction TB
        URX["uart_rx<br/>12 Mbaud"]
        CMD2["cmd_parser_v2<br/>计算命令 + DDR 地址 + tile 元数据"]
        CORE2["mandelbrot_multicore<br/>24x fx worker"]
        TCDB["tile_cache_db<br/>乒乓双缓冲 BRAM<br/>Buffer A + Buffer B"]
        AXIM["axi_ddr_writer<br/>AXI4 Master → PS DDR"]
        UTX2["uart_tx<br/>12 Mbaud<br/>ACK / COMPUTE_DONE / DDR_DONE"]
        URX --> CMD2 --> CORE2
        CORE2 --> TCDB
        TCDB --> AXIM
        CMD2 --> AXIM
        AXIM --> UTX2
        CORE2 --> UTX2
    end

    subgraph PS["FPGA PS (ZynqMP A53)"]
        direction TB
        DDR["PS DDR4 4 GiB<br/>像素缓冲区"]
    end

    USB -->|"UART 命令"| URX
    UTX2 -->|"UART 通知"| USB
    AXIM -->|"AXI HP0 64-bit<br/>写 PS DDR"| DDR
    DDR -.-"Host 回传阶段<br/>通过 UART/USB 读取"-. HOST
```

### 2.2 与现有设计的对比

| 维度 | 现有 fx64 设计 | 新 PL-PS DDR 设计 |
|---|---|---|
| 像素回传 | UART 流式 `RT/TD/TE` 分块 | AXI HP 写 PS DDR + UART 通知 |
| 回传带宽 | ~1.2 MB/s (12Mbaud) | ~500 MB/s (AXI HP 64-bit) |
| FPGA 帧缓存 | 无（流式） | 2 个 compute tile (乒乓 BRAM) |
| 计算与传输 | 串行（UART 反压阻塞计算） | **流水化（乒乓双缓冲并行）** |
| Retry 机制 | Host 重算整个 compute tile | FPGA 从 BRAM 缓存重发 retry tile |
| PS 端 | 未使用 | DDR4 作为像素缓冲 |
| Boot 流程 | 纯 PL bitstream（program.tcl） | JTAG 空白启动（psu_init + bitstream） |

### 2.3 乒乓双缓冲流水工作流程

```mermaid
flowchart TB
    CMD0["Host: COMPUTE_TILE #0"]
    ACK0["FPGA: ACK #0"]
    CALC0["FPGA: 计算 tile #0 → Buffer A"]
    CDONE0["FPGA: COMPUTE_DONE #0<br/>(tile #0 计算完，Buffer A 就绪)"]

    CMD1["Host: 收到 COMPUTE_DONE #0<br/>立即发 COMPUTE_TILE #1"]
    ACK1["FPGA: ACK #1"]
    CALC1["FPGA: 计算 tile #1 → Buffer B"]
    DDRW0["FPGA: 同时 DDR 写入 tile #0 ← Buffer A"]
    DDRDONE0["FPGA: DDR_DONE #0<br/>(tile #0 DDR 写入 + checksum)"]

    CMD2["Host: 收到 COMPUTE_DONE #1<br/>立即发 COMPUTE_TILE #2"]
    CALC2["FPGA: 计算 tile #2 → Buffer A"]
    DDRW1["FPGA: 同时 DDR 写入 tile #1 ← Buffer B"]
    DDRDONE1["FPGA: DDR_DONE #1"]

    CMD0 --> ACK0 --> CALC0 --> CDONE0
    CDONE0 --> CMD1 --> ACK1
    ACK1 --> CALC1
    ACK1 --> DDRW0
    CALC1 --> DDRDONE0
    DDRW0 --> DDRDONE0
    DDRDONE0 --> CMD2
    CMD2 --> CALC2
    CMD2 --> DDRW1
```

**时序图**：

```
时间 →
tile 0:  [==== compute → A ====]
                              [== DDR write A ==]
tile 1:                        [==== compute → B ====]
                                                    [== DDR write B ==]
tile 2:                                              [==== compute → A ====]
                                                                          [== DDR write A ==]
                   ↑ Host 发 #1                ↑ Host 发 #2
                   (COMPUTE_DONE #0)           (COMPUTE_DONE #1)
```

**关键**：Host 在收到 `COMPUTE_DONE`（计算完，尚未 DDR 写完）时即可发下一条命令。FPGA 将计算结果写入空闲 buffer，同时 DDR writer 排空另一 buffer。两条流水线并行运行。

---

## 3. 协议设计

### 3.1 命令帧格式

沿用 `55 AA TYPE LEN PAYLOAD CHECKSUM` 帧结构（two's-complement checksum），扩展新的命令类型：

| 方向 | Type | Len | Payload | 说明 |
|---|---|---|---|---|
| H→F | 0x10 COMPUTE_TILE | 42 | center_re(8) center_im(8) step(8) max_iter(2) rows(2) cols(2) ddr_base(8) tile_id(4) | 计算一个 tile 并写入 DDR |
| H→F | 0x11 ENTER_DOWNLOAD | 4 | total_tiles(2) total_pixels(4) | 通知 FPGA 所有计算完成，进入回传 |
| H→F | 0x12 RETRY_TILE | 10 | tile_id(4) retry_row(2) retry_rows(2) retry_col(2) | 请求从 BRAM 缓存重发指定 retry tile |
| H→F | 0x02 QUERY_CONFIG | 0 | — | 查询 DDR 映射配置 |
| F→H | 0x81 ACK | 1 | status(1) | 命令接收确认（0=OK, 1=BUSY, 2=BAD_ALIGN, 3=BAD_SIZE） |
| **F→H** | **0x86 COMPUTE_DONE** | **6** | **tile_id(4) buffer_id(1) pixel_count_lo(1)** | **tile 计算完成，buffer 就绪，DDR 写入即将开始。Host 可立即发下一条命令** |
| **F→H** | **0x84 DDR_DONE** | **14** | **tile_id(4) ddr_base(8) pixel_count(2) checksum(2)** | **tile DDR 写入完成，checksum 就绪** |
| F→H | 0x85 ALL_DONE | 2 | total_tiles(2) | 所有 tile 处理完毕，回传就绪 |
| F→H | 0x83 MAP_CONFIG | 18 | busy(1) map_flags(1) logical_split(8) phys_high_base(8) | DDR 地址映射配置 |

### 3.2 乒乓协议时序

```mermaid
sequenceDiagram
    participant Host
    participant FPGA

    Host->>FPGA: COMPUTE_TILE #0 (ddr_base_0)
    FPGA-->>Host: ACK #0 (OK)
    Note over FPGA: compute tile #0 → Buffer A
    FPGA-->>Host: COMPUTE_DONE #0 (buffer_id=0)
    Note over Host: 收到 COMPUTE_DONE，立即发下一条

    Host->>FPGA: COMPUTE_TILE #1 (ddr_base_1)
    FPGA-->>Host: ACK #1 (OK)
    Note over FPGA: compute tile #1 → Buffer B (并行)
    Note over FPGA: DDR write tile #0 ← Buffer A (并行)
    FPGA-->>Host: DDR_DONE #0 (ddr_base_0, checksum_0)
    FPGA-->>Host: COMPUTE_DONE #1 (buffer_id=1)
    Note over Host: 校验 checksum_0，立即发下一条

    Host->>FPGA: COMPUTE_TILE #2 (ddr_base_2)
    FPGA-->>Host: ACK #2 (OK)
    Note over FPGA: compute tile #2 → Buffer A (并行)
    Note over FPGA: DDR write tile #1 ← Buffer B (并行)
    FPGA-->>Host: DDR_DONE #1 (ddr_base_1, checksum_1)
    FPGA-->>Host: COMPUTE_DONE #2 (buffer_id=0)
    Note over Host: 循环直至所有 tile...

    Host->>FPGA: ENTER_DOWNLOAD
    Note over FPGA: flush last DDR write
    FPGA-->>Host: DDR_DONE (last tile)
    FPGA-->>Host: ALL_DONE
    Note over Host, FPGA: 进入回传阶段
```

### 3.3 协议状态机（FPGA 侧）

```mermaid
stateDiagram-v2
    [*] --> S_IDLE
    S_IDLE --> S_COMPUTE: COMPUTE_TILE received
    S_COMPUTE --> S_FLUSH: compute done, buffer full
    S_FLUSH --> S_IDLE: COMPUTE_DONE sent
    Note right of S_FLUSH: 同时触发 DDR writer
    S_IDLE --> S_COMPUTE: next COMPUTE_TILE (pipeline)
    S_IDLE --> S_DOWNLOAD: ENTER_DOWNLOAD
    S_DOWNLOAD --> S_IDLE: flush last DDR + ALL_DONE
    S_IDLE --> S_RETRY: RETRY_TILE
    S_RETRY --> S_IDLE: retry tile sent from BRAM cache
```

### 3.4 ACK BUSY 处理

当 Host 在 DDR writer 仍在排空两个 buffer 时发来 `COMPUTE_TILE`：
- FPGA 返回 `ACK (status=BUSY)`
- Host 等待 `DDR_DONE` 后重发

正常流水中不会出现 BUSY：Host 在 `COMPUTE_DONE` 后发命令时，刚完成的 buffer 正在被 DDR writer 排空，另一个 buffer 已空闲用于新计算。只有当 DDR 写入速度慢于计算（浅场景）且两个 buffer 都满时才触发 BUSY。

### 3.5 与现有 RT/TD/TE 协议的关系

- **计算阶段**：不再通过 UART 回传像素。UART 仅用于命令 + ACK + COMPUTE_DONE + DDR_DONE 通知，带宽需求极低（每 tile ~60 字节通知）。
- **回传阶段**：两种选择：
  - **方案 A（UART 回传）**：FPGA 在 ENTER_DOWNLOAD 后，逐 tile 从 BRAM 缓存或 DDR 回读，以 `RT/TD/TE` 格式通过 UART 发送像素。适用于不修改 Host USB 路径的场景。
  - **方案 B（PS 推送）**：PS 端运行一个最小程序，在收到 Host 请求后通过 GEM3 Ethernet 或 PS UART 推送 DDR 中的像素。需要 PS 端 C 程序，但可大幅提升回传带宽。
- **初始实现采用方案 A**（零 PS 端代码，自洽空白启动），后续可选升级为方案 B。

---

## 4. PL 端 RTL 架构

### 4.1 新增 RTL 模块

| 模块 | 文件 | 功能 |
|---|---|---|
| `axi_ddr_writer` | `rtl/axi_ddr_writer.v` | AXI4 Master，将 BRAM 中的 tile 像素写入 PS DDR。独立运行，与 multicore 解耦。 |
| `tile_cache_db` | `rtl/tile_cache_db.v` | 乒乓双缓冲 BRAM，存储 2 个 compute tile 的像素。交替写入/读出，实现计算与 DDR 写入并行。 |
| `cmd_parser_v2` | `rtl/cmd_parser_v2.v` | 扩展命令解析器，支持 COMPUTE_TILE / ENTER_DOWNLOAD / RETRY_TILE / QUERY_CONFIG。 |
| `top_with_ram` | `rtl/top_with_ram.v` | 新顶层，集成 multicore + tile_cache_db + axi_ddr_writer + cmd_parser_v2 + response_sender。 |
| `pl_por` | 复用 PL-PS-MEM-TEST | PL 本地复位。 |

### 4.2 tile_cache_db 乒乓双缓冲架构

```mermaid
flowchart TB
    subgraph TCDB["tile_cache_db (乒乓双缓冲 BRAM)"]
        direction TB
        subgraph BUF_A["Buffer A (BRAM)"]
            direction TB
            WA["写端口<br/>← raster collector (tile N)"]
            RA_DDR_A["读端口 A (DDR)<br/>→ axi_ddr_writer (tile N-1)"]
            RA_RTY_A["读端口 B (Retry)<br/>→ retry_tx_ctrl"]
        end
        subgraph BUF_B["Buffer B (BRAM)"]
            direction TB
            WB["写端口<br/>← raster collector (tile N+1)"]
            RB_DDR_B["读端口 A (DDR)<br/>→ axi_ddr_writer (tile N)"]
            RB_RTY_B["读端口 B (Retry)<br/>→ retry_tx_ctrl"]
        end
        MUX_W["写路由 mux<br/>wr_sel = write_buffer_id"]
        MUX_R["DDR 读路由 mux<br/>rd_sel = ddr_read_buffer_id"]
        SEL["buffer_id 管理<br/>write_buffer_id 交替 0/1<br/>ddr_read_buffer_id 跟踪"]
        SEL --> MUX_W
        SEL --> MUX_R
        MUX_W --> WA
        MUX_W --> WB
        RA_DDR_A --> MUX_R
        RB_DDR_B --> MUX_R
    end
```

**双缓冲交替逻辑**：

| 时刻 | write_buffer_id | ddr_read_buffer_id | 动作 |
|---|---|---|---|
| tile 0 | 0 (A) | — | 计算 → A |
| tile 0 完成 | 1 (B) | 0 (A) | COMPUTE_DONE #0，DDR 读 A，下一条计算 → B |
| tile 1 | 1 (B) | 0 (A) | 计算 → B，DDR 写 A（并行） |
| tile 1 完成 | 0 (A) | 1 (B) | COMPUTE_DONE #1，DDR 读 B，下一条计算 → A |
| tile 2 | 0 (A) | 1 (B) | 计算 → A，DDR 写 B（并行） |

**资源估算**：

| Tile 尺寸 | 像素数 | 单缓冲 BRAM | 双缓冲 BRAM |
|---|---|---|---|
| 1920×120 (默认) | 230,400 | 460,800 bytes ≈ 13 BRAM36 | 921,600 bytes ≈ **26 BRAM36** |
| 2048×120 (compute cap) | 245,760 | 491,520 bytes ≈ 14 BRAM36 | 983,040 bytes ≈ **28 BRAM36** |

当前 fx64 设计使用 33/128 BRAM（25.78%）。双缓冲 1920×120 需 ~26 BRAM36，总计 ~59/128（46.1%），仍充裕。

### 4.3 tile_cache_db 接口

```verilog
module tile_cache_db #(
    parameter MAX_TILE_PIXELS = 245760,  // 2048*120
    parameter DATA_WIDTH = 16
) (
    input  wire                   clk,
    input  wire                   rst,

    // 写端口：来自 raster collector
    input  wire                   wr_en,
    input  wire [DATA_WIDTH-1:0]  wr_data,
    input  wire                   wr_start,     // 新 tile 开始，复位写指针 + 翻转 buffer
    output wire                   wr_full,      // 当前写 buffer 已写满
    output wire [0:0]             wr_buffer_id, // 当前写 buffer ID (0=A, 1=B)

    // 读端口 A：DDR 写入（读非活跃 buffer）
    input  wire                   rd_ddr_start,
    input  wire [0:0]             rd_ddr_buffer_id, // 指定读哪个 buffer
    output wire                   rd_ddr_done,
    output wire [DATA_WIDTH-1:0]  rd_ddr_data,
    input  wire                   rd_ddr_en,

    // 读端口 B：retry 回传（读最近完成的 buffer）
    input  wire                   rd_retry_start,
    input  wire [0:0]             rd_retry_buffer_id,
    input  wire [15:0]            rd_retry_row_offset,
    input  wire [15:0]            rd_retry_row_count,
    input  wire [15:0]            rd_retry_cols,
    output wire [DATA_WIDTH-1:0]  rd_retry_data,
    input  wire                   rd_retry_en,
    output wire                   rd_retry_valid,
    output wire                   rd_retry_done
);
```

### 4.4 axi_ddr_writer 架构

axi_ddr_writer 独立运行，与 multicore 完全解耦。它从 tile_cache_db 的读端口 A 顺序读取像素，打包成 64-bit AXI beat，通过 AXI HP 写入 PS DDR。

```mermaid
flowchart TB
    subgraph AXIW["axi_ddr_writer (独立运行)"]
        direction TB
        CTRL["控制 FSM<br/>ST_IDLE → ST_AW → ST_W → ST_B → ST_DONE"]
        ADDR["地址生成<br/>ddr_base + pixel_index * 2<br/>128-byte burst (16 beats × 8 bytes)"]
        WDATA["数据打包<br/>4 个 uint16 像素 → 1 个 64-bit AXI beat"]
        TAGS["AXI 信号<br/>awlen=15, awsize=3, awburst=INCR<br/>awcache=0011"]
        RDCNT["读 tile_cache_db<br/>顺序读出像素 (rd_ddr_en/rd_ddr_data)"]
        CKSUM["XOR checksum<br/>16-bit, 累加所有像素"]
        CTRL --> ADDR
        CTRL --> WDATA
        ADDR --> TAGS
        WDATA --> RDCNT
        RDCNT --> CKSUM
    end
```

**关键设计参数**（沿用 PL-PS-MEM-TEST 验证过的配置）：

| 参数 | 值 | 说明 |
|---|---|---|
| AXI_DATA_WIDTH | 64 | 64-bit 数据总线 |
| AXI_ADDR_WIDTH | 64 | 64-bit 地址（支持 DDR_HIGH 映射） |
| BURST_BEATS | 16 | 16 拍突发 = 128 bytes |
| awsize/arsize | 3'd3 | 8 bytes/beat |
| awburst/arburst | 2'b01 | INCR |
| awcache/arcache | 4'b0011 | Normal, Non-cacheable |

**像素打包**：每个 64-bit AXI beat 携带 4 个 uint16 像素。tile_cache_db 顺序读出 4 个像素，拼接为一个 64-bit word 写入 DDR。

**地址映射**：沿用 PL-PS-MEM-TEST 的 `map_addr()` 函数，支持 split DDR 高地址映射。默认 `logical_split=0x80000000`, `physical_high_base=0x800000000`。

**独立运行**：axi_ddr_writer 有自己的控制 FSM，由 `top_with_ram` 在 tile 计算完成时触发 `start` 信号。它与 multicore 无直接数据依赖，可同时运行。

### 4.5 顶层集成

```mermaid
flowchart TB
    subgraph TOP["top_with_ram (BD 顶层)"]
        direction TB
        CLK["sys_clk 200MHz E12"]
        POR["pl_por<br/>PL 本地复位 ~5ms"]
        URX3["uart_rx 12Mbaud"]
        UTX3["uart_tx 12Mbaud"]
        CMD3["cmd_parser_v2"]
        CORE3["mandelbrot_multicore<br/>24x fx_worker, 4ctx"]
        TCDB2["tile_cache_db<br/>乒乓双缓冲 BRAM<br/>Buffer A + Buffer B"]
        AXIW2["axi_ddr_writer<br/>独立运行 → AXI HP0 → PS DDR"]
        RSP["response_sender_v2<br/>ACK / COMPUTE_DONE / DDR_DONE / ALL_DONE"]
        TXC3["tx_ctrl_v2<br/>回传阶段: RT/TD/TE from cache"]

        CLK --> POR
        POR --> CORE3
        POR --> AXIW2
        CLK --> CORE3
        CLK --> AXIW2
        URX3 --> CMD3 --> CORE3
        CMD3 --> RSP --> UTX3
        CORE3 --> TCDB2
        TCDB2 --> AXIW2
        TCDB2 --> TXC3
        AXIW2 --> RSP
        CORE3 --> RSP
        TXC3 --> UTX3
    end
```

### 4.6 计算与 DDR 写入并行流程

```mermaid
sequenceDiagram
    participant Host
    participant CMD as cmd_parser_v2
    participant Core as multicore (24x fx)
    participant Cache as tile_cache_db (A/B)
    participant AXI as axi_ddr_writer
    participant RSP as response_sender
    participant DDR as PS DDR

    Note over Host, DDR: === Tile 0 (初始，无并行) ===
    Host->>CMD: COMPUTE_TILE #0
    CMD-->>Host: ACK #0 (OK)
    CMD->>Core: compute_start
    Core->>Cache: pixels → Buffer A (wr_start, wr_en)
    Core->>CMD: compute_done
    CMD->>RSP: COMPUTE_DONE #0 (buffer_id=0)
    RSP-->>Host: COMPUTE_DONE #0
    CMD->>AXI: ddr_write_start (ddr_base_0, buffer_id=0)

    Note over Host, DDR: === Tile 1 (并行开始) ===
    Host->>CMD: COMPUTE_TILE #1
    CMD-->>Host: ACK #1 (OK)
    CMD->>Core: compute_start (→ Buffer B)
    Core->>Cache: pixels → Buffer B (wr_start, wr_en)
    par DDR 写入 tile #0
        AXI->>Cache: read Buffer A (rd_ddr_en)
        AXI->>DDR: AXI burst writes
        AXI->>RSP: ddr_write_done (checksum_0)
        RSP-->>Host: DDR_DONE #0
    and 计算 tile #1
        Core->>Cache: pixels → Buffer B
        Core->>CMD: compute_done
        CMD->>RSP: COMPUTE_DONE #1 (buffer_id=1)
        RSP-->>Host: COMPUTE_DONE #1
    end

    Note over Host, DDR: === Tile 2 (继续并行) ===
    Host->>CMD: COMPUTE_TILE #2
    CMD-->>Host: ACK #2 (OK)
    CMD->>AXI: ddr_write_start (ddr_base_1, buffer_id=1)
    par DDR 写入 tile #1
        AXI->>Cache: read Buffer B
        AXI->>DDR: AXI burst writes
        AXI->>RSP: ddr_write_done (checksum_1)
        RSP-->>Host: DDR_DONE #1
    and 计算 tile #2
        Core->>Cache: pixels → Buffer A
        Core->>CMD: compute_done
        CMD->>RSP: COMPUTE_DONE #2 (buffer_id=0)
        RSP-->>Host: COMPUTE_DONE #2
    end

    Note over Host, DDR: 循环至所有 tile 完成...
```

### 4.7 Retry tile 回传

当 Host 在回传阶段发现某个 retry tile 校验失败：

```mermaid
sequenceDiagram
    participant Host
    participant Cache as tile_cache_db (BRAM)
    participant TXC as tx_ctrl_v2

    Host->>Cache: RETRY_TILE (tile_id, retry_row, retry_rows, retry_col)
    Note over Cache: 从对应 buffer 按行范围读出
    Cache->>TXC: stream retry tile pixels
    TXC-->>Host: RT/TD/TE (retry tile payload + checksum)
    Note over Host: verify checksum, patch into image
```

**关键区别**：Retry 不再重算，而是从 BRAM 缓存直接重发。这消除了重算开销。

**限制**：tile_cache_db 双缓冲仅缓存 2 个 compute tile。Retry 只对最近 2 个 tile 有效。如果 Host 请求 retry 一个已被覆盖的 tile，FPGA 返回 `RETRY_MISS`（ACK status=4），Host 回退到重算该 tile。

---

## 5. PS 端配置与空白启动

### 5.1 Block Design 结构

```mermaid
flowchart TB
    subgraph BD["Block Design: system"]
        direction TB
        PS["zynq_ultra_ps_e_0<br/>DDR4 4GiB, HP0 64-bit<br/>PS UART0 (debug only)<br/>Fabric RST enabled"]
        SMPI["axi_smc_0<br/>SmartConnect 1 SI / 1 MI"]
        TOPMOD["top_with_ram<br/>(自定义 RTL)"]
        POR2["pl_por_0<br/>PL 本地复位"]
        EXTCLK["sys_clk (external 200MHz)"]
        EXTUART["uart_rx / uart_tx (external)"]
        EXTDDR["DDR (external PS DDR)"]
        EXTFIXED["FIXED_IO (external PS MIO)"]

        EXTCLK --> TOPMOD
        EXTCLK --> SMPI
        EXTCLK --> PS
        POR2 --> TOPMOD
        POR2 --> SMPI
        TOPMOD -->|"M_AXI"| SMPI
        SMPI -->|"M00_AXI → S_AXI_HP0_FPD"| PS
        TOPMOD --> EXTUART
        PS --> EXTDDR
        PS --> EXTFIXED
    end
```

### 5.2 PS 配置要点（沿用 PL-PS-MEM-TEST 验证配置）

| 配置项 | 值 | 说明 |
|---|---|---|
| DDR4 容量 | 4 GiB (8192 MBits) | 2GiB low + 2GiB high |
| DDR_HIGH | enabled | `PSU__HIGH_ADDRESS__ENABLE=1` + protection slave `;1` |
| HP0 | `S_AXI_HP0_FPD`, 64-bit | PL → PS DDR 写通道 |
| HP0 clock | 200 MHz (E12 external) | `saxihp0_fpd_aclk` connected to `sys_clk` |
| Fabric RST | enabled | `PSU__USE__FABRIC__RST=1`（但 pl_por 不依赖它） |
| PL0 clock | 不使用 | PL 时钟由外部 E12 200MHz 驱动 |
| PS UART0 | MIO 26-27, 115200 | 仅用于调试，不用于数据传输 |
| SD1 | MIO 46-51, 4-bit | 可选，用于 FSBL boot |

### 5.3 空白启动流程

```mermaid
flowchart TB
    JTAG["JTAG 连接<br/>connect -url tcp:localhost:3121"]
    RSTPS["1. System Reset APU<br/>targets 8; rst -system"]
    PSUINIT["2. psu_init.tcl via JTAG<br/>targets 4; source psu_init.tcl<br/>psu_init + psu_post_config<br/>+ psu_ps_pl_reset_config<br/>+ psu_ps_pl_isolation_removal"]
    DDRTEST["3. Verify DDR<br/>mwr 0x10000000 0xDEADBEEF<br/>mrd 0x10000000"]
    PROG["4. Program PL bitstream<br/>targets PS TAP; fpga top_with_ram.bit"]
    READY["5. Boot complete<br/>PS DDR initialized, PL running"]

    JTAG --> RSTPS --> PSUINIT --> DDRTEST --> PROG --> READY
```

**关键**：
- `psu_init.tcl` 由 Vivado 从 BD 自动生成，包含全部 PS 寄存器初始化（PLL、DDR、时钟、MIO）
- `pl_por.v` 确保 PL 逻辑在 bitstream 加载后 ~5ms 自行释放复位，不依赖 PS `pl_resetn0`
- 无需 FSBL、无需 PS 端 C 程序、无需 SD 卡
- 一个 `boot_jtag.tcl` 脚本完成全部初始化

### 5.4 构建脚本

新建 `build_mandelbrot_with_ram.tcl`，基于 PL-PS-MEM-TEST 的 `build_pl_ps_ddr_mem_test.tcl`：

1. 创建 Vivado 项目 (`xczu4ev-sfvc784-2-i`)
2. 添加全部 Mandelbrot RTL + 新增 RTL（axi_ddr_writer, tile_cache_db, cmd_parser_v2, top_with_ram）
3. 添加 PL-PS-MEM-TEST 的 `pl_por.v`、`uart_rx.v`、`uart_tx.v`、`config.vh`
4. 添加 XDC 约束（E12 200MHz, D12/C12 UART）
5. 创建 BD：`zynq_ultra_ps_e_0`（从 `reference/design_1.bd` 加载 PS 配置 + `enable_ps_ddr_high_address`）
6. 创建 BD：`top_with_ram`（自定义 RTL）、`axi_smc_0`（SmartConnect）、`pl_por_0`
7. 连接 AXI：`top_with_ram/M_AXI → axi_smc_0 → zynq_ultra_ps_e_0/S_AXI_HP0_FPD`
8. 连接时钟/复位/UART
9. `assign_bd_address` + 验证 `DDR_HIGH` 已分配
10. 综合 → 实现 → write_bitstream → write_hw_platform (XSA)

### 5.5 psu_init.tcl 生成

构建完成后，Vivado 自动生成 `psu_init.tcl`（~13000 行），包含从 BD 导出的全部 PS 寄存器初始化序列。`boot_jtag.tcl` 通过 JTAG 执行此文件，实现空白启动。

---

## 6. Host 软件架构

### 6.1 Host 工作流程（乒乓流水）

```mermaid
flowchart TB
    INIT["Host: 启动<br/>--mode fx64 --with-ram"]
    BOOT["Host: 执行 boot_jtag.tcl<br/>(或用户手动执行)"]
    QUERY["Host: QUERY_CONFIG<br/>确认 DDR 映射"]

    SEND0["Host: 发送 COMPUTE_TILE #0"]
    WAIT_C0["Host: 等待 COMPUTE_DONE #0"]

    SEND1["Host: 收到 COMPUTE_DONE #0<br/>立即发 COMPUTE_TILE #1"]
    WAIT_D0_C1["Host: 等待 DDR_DONE #0<br/>和 COMPUTE_DONE #1<br/>(可并行到达)"]

    LOOP["Host: 收到 COMPUTE_DONE<br/>立即发下一条<br/>收到 DDR_DONE 校验 checksum"]

    ALL["Host: 所有 COMPUTE_TILE 发送完毕<br/>发送 ENTER_DOWNLOAD"]
    FLUSH["Host: 等待最后一个 DDR_DONE + ALL_DONE"]
    RECV["Host: 接收回传<br/>方案A: UART RT/TD/TE<br/>方案B: PS 端推送"]

    INIT --> BOOT --> QUERY --> SEND0 --> WAIT_C0 --> SEND1 --> WAIT_D0_C1
    WAIT_D0_C1 --> LOOP
    LOOP -->|"更多 tile"| SEND1
    LOOP -->|"全部发送"| ALL --> FLUSH --> RECV
```

### 6.2 DDR 地址分配

Host 为每个 compute tile 分配 DDR 地址：

```python
tile_pixels = tile_width * tile_height
tile_bytes = tile_pixels * 2  # uint16 per pixel
ddr_base = ddr_region_base + tile_index * tile_bytes
```

DDR 区域基址建议 `0x10000000`（256MB 偏移，避开 OCM 和低地址保留区）。一个 1080p 帧（1920×1080 = 2,073,600 像素 = 4,147,200 bytes ≈ 4MB）轻松容纳在 4GB DDR 中。

### 6.3 Checksum 验证

每个 tile DDR 写入完成后，FPGA 通过 `DDR_DONE` 帧返回 XOR checksum。Host 在收到 `DDR_DONE` 后校验。如果 checksum 不匹配，Host 在回传阶段通过 `RETRY_TILE` 请求重发。

由于 `DDR_DONE` 在 `COMPUTE_DONE` 之后异步到达，Host 需要维护一个 pending DDR_DONE 队列，按 `tile_id` 匹配。

### 6.4 回传阶段（方案 A：UART）

Host 发送 ENTER_DOWNLOAD 后，FPGA 逐 tile 从 BRAM 缓存或 DDR 回读，以现有 `RT/TD/TE` 格式发送。Host 使用现有接收逻辑。

由于回传阶段无计算压力，UART 12Mbaud 的 ~600k pps 可以全速用于数据传输（无 ACK 等待开销）。一个 1920×120 tile = 460,800 bytes ≈ 0.77s @ 12Mbaud。9 个 tile ≈ 7s（与现有 baseline 相当），但计算阶段不再被 UART 阻塞。

**关键优势**：计算阶段与传输阶段解耦。24 个 worker 全速计算，不受 UART 反压。UART 仅在回传阶段使用。

---

## 7. tile_cache_db 详细设计

### 7.1 双缓冲 BRAM 组织

```mermaid
flowchart TB
    subgraph DB["tile_cache_db 内部结构"]
        direction TB
        subgraph A["Buffer A"]
            MA["BRAM A<br/>深度 MAX_TILE_PIXELS<br/>宽度 16-bit<br/>双端口"]
        end
        subgraph B["Buffer B"]
            MB["BRAM B<br/>深度 MAX_TILE_PIXELS<br/>宽度 16-bit<br/>双端口"]
        end
        WSEL["写选择<br/>wr_buffer_id: 0→A, 1→B"]
        RSEL_DDR["DDR 读选择<br/>rd_ddr_buffer_id"]
        RSEL_RTY["Retry 读选择<br/>rd_retry_buffer_id"]
        WSEL --> A
        WSEL --> B
        A --> RSEL_DDR
        B --> RSEL_DDR
        A --> RSEL_RTY
        B --> RSEL_RTY
    end
```

### 7.2 Buffer 交替时序

```mermaid
flowchart TB
    T0["tile 0<br/>wr→A<br/>DDR: idle"]
    T1["tile 1<br/>wr→B<br/>DDR: rd A"]
    T2["tile 2<br/>wr→A<br/>DDR: rd B"]
    T3["tile 3<br/>wr→B<br/>DDR: rd A"]
    T0 --> T1 --> T2 --> T3
```

每个 buffer 有独立的双端口 BRAM：
- **写端口**：raster collector 按光栅序写入当前活跃 buffer
- **读端口 A (DDR)**：axi_ddr_writer 顺序读出非活跃 buffer
- **读端口 B (Retry)**：retry_tx_ctrl 按行范围读出最近完成 buffer

使用 Verilog reg 数组 + `(* ram_style = "block" *)` 属性强制 BRAM 推断。

### 7.3 Buffer 状态管理

```verilog
// buffer 状态
reg [0:0] wr_buf_id;       // 当前写 buffer (multicore 写入)
reg [0:0] ddr_rd_buf_id;   // 当前 DDR 读 buffer (axi_ddr_writer 读出)
reg [0:0] retry_buf_id;    // 当前 retry 读 buffer (最近完成)

// 状态机
// 1. wr_start: wr_buf_id 翻转, 写指针复位
// 2. wr_full: 计算 done, 触发 COMPUTE_DONE
//    ddr_rd_buf_id = wr_buf_id (切换前), ddr_write_start
// 3. ddr_write_done: ddr_rd_buf_id 标记完成, retry_buf_id = ddr_rd_buf_id
```

### 7.4 Tile 计算与缓存时序

```mermaid
flowchart TB
    CALC["multicore 计算<br/>24x fx worker<br/>raster collector 输出像素"]
    FIFO2["output FIFO<br/>1024x16 (existing)"]
    CACHE2["tile_cache_db<br/>wr_en + wr_data → 活跃 buffer"]
    CALC -->|"fifo_wr/fifo_data"| FIFO2 -->|"rd_en/rd_data"| CACHE2
```

raster collector 的输出通过现有 output FIFO 写入 tile_cache_db 的活跃 buffer。`wr_start` 在 COMPUTE_TILE 命令接收时拉高，复位写指针并翻转 buffer。当写指针达到 `rows * cols` 时，`wr_full` 拉高，触发 COMPUTE_DONE 通知和 DDR 写入。

---

## 8. axi_ddr_writer 详细设计

### 8.1 接口

```verilog
module axi_ddr_writer #(
    parameter AXI_DATA_WIDTH = 64,
    parameter AXI_ADDR_WIDTH = 64,
    parameter BURST_BEATS = 16
) (
    input  wire                         aclk,
    input  wire                         aresetn,

    // 控制（来自 top_with_ram）
    input  wire                         start,
    input  wire [AXI_ADDR_WIDTH-1:0]    base_addr,
    input  wire [31:0]                  pixel_count,
    input  wire [0:0]                   buffer_id,   // 指定读哪个 buffer
    output reg                          done,
    output reg  [15:0]                  checksum,

    // tile_cache_db 读接口
    output wire                         cache_rd_en,
    input  wire [15:0]                  cache_rd_data,
    input  wire                         cache_rd_valid,

    // AXI4 Master (AW/W/B channels, write-only)
    output reg  [AXI_ADDR_WIDTH-1:0]    m_axi_awaddr,
    output wire [7:0]                   m_axi_awlen,
    output wire [2:0]                   m_axi_awsize,
    output wire [1:0]                   m_axi_awburst,
    output wire [3:0]                   m_axi_awcache,
    output wire [2:0]                   m_axi_awprot,
    output reg                          m_axi_awvalid,
    input  wire                         m_axi_awready,
    output reg  [AXI_DATA_WIDTH-1:0]    m_axi_wdata,
    output wire [(AXI_DATA_WIDTH/8)-1:0] m_axi_wstrb,
    output wire                         m_axi_wlast,
    output reg                          m_axi_wvalid,
    input  wire                         m_axi_wready,
    input  wire [1:0]                   m_axi_bresp,
    input  wire                         m_axi_bvalid,
    output reg                          m_axi_bready
);
```

### 8.2 状态机

```mermaid
stateDiagram-v2
    [*] --> ST_IDLE
    ST_IDLE --> ST_AW: start received
    ST_AW --> ST_W: awvalid && awready
    ST_W --> ST_W: wvalid && wready && !wlast
    ST_W --> ST_B: wlast && wready
    ST_B --> ST_AW: bvalid && more bursts
    ST_B --> ST_DONE: bvalid && last burst
    ST_DONE --> ST_IDLE: done + checksum ready
```

### 8.3 像素打包

每个 AXI beat（64-bit）打包 4 个 uint16 像素：

```verilog
reg [1:0] pix_in_word;
reg [63:0] wdata_accum;

always @(posedge aclk) begin
    if (cache_rd_valid) begin
        wdata_accum[16*pix_in_word +: 16] <= cache_rd_data;
        pix_in_word <= pix_in_word + 1;
        if (pix_in_word == 2'd3) begin
            m_axi_wdata <= {cache_rd_data, wdata_accum[47:0]};
            m_axi_wvalid <= 1'b1;
        end
    end
end
```

### 8.4 Checksum

对全部像素做 XOR checksum（16-bit），与现有 tx_ctrl 的 TD checksum 算法一致：

```verilog
always @(posedge aclk) begin
    if (cache_rd_valid)
        checksum <= checksum ^ cache_rd_data;
end
```

### 8.5 独立运行保证

axi_ddr_writer 与 multicore 无直接数据依赖：
- 多核计算写入 tile_cache_db 的活跃 buffer
- axi_ddr_writer 从非活跃 buffer 读出
- 两者操作不同 BRAM，无冲突
- `start` 信号在 COMPUTE_DONE 发送时由 `top_with_ram` 触发
- `done` 信号通过 `DDR_DONE` 帧通知 Host

---

## 9. 资源估算

| 资源 | fx64 24w/4ctx (现有) | 新增 (双缓冲 + AXI writer) | 预估总计 |
|---|---|---|---|
| CLB LUTs | 83,731 (95.32%) | ~2,500 (AXI FSM + 打包 + 地址 + buffer mux) | ~86,200 (98.1%) |
| CLB Registers | 76,116 (43.33%) | ~2,000 | ~78,100 (44.4%) |
| DSP48E2 | 483 (66.3%) | 0 | 483 (66.3%) |
| Block RAM | 33 (25.78%) | ~26 (双缓冲 1920×120) | ~59 (46.1%) |

LUT 增量 ~2.5K（98.1%，接近满但可容纳），BRAM 增量 ~26 块（46.1%，充裕）。如果 LUT 超限，可减少 worker 至 20 或优化 AXI 控制逻辑。

---

## 10. 预期性能

### 10.1 乒乓流水收益

| 场景 | 单缓冲 (计算+DDR 串行) | 双缓冲 (计算+DDR 并行) | 提速 |
|---|---|---|---|
| 浅 (compute 5ms + DDR 1ms/tile) | 6ms/tile | 5ms/tile | ~17% |
| 深 (compute 500ms + DDR 1ms/tile) | 501ms/tile | 500ms/tile | ~0.2% |

**浅场景有可见收益**：计算快时 DDR 写入占比变大，流水化隐藏了 DDR 写入延迟。深场景影响可忽略（DDR 写入远快于计算）。

### 10.2 计算阶段（与现有 UART 受限对比）

| 场景 | 现有 (UART 受限) | 新设计 (乒乓流水) | 提速来源 |
|---|---|---|---|
| fast escape @128 | 3.733s (UART bound) | ~0.5s (纯计算, DDR 隐藏) | UART 不再阻塞计算 |
| deep minibrot @8192 | 5.091s (mixed) | ~5.0s (纯计算) | 计算仍为主要耗时 |

### 10.3 回传阶段

| 回传方式 | 带宽 | 1080p 全帧时间 |
|---|---|---|
| UART 12Mbaud (方案 A) | ~600k pps | ~3.5s (无计算开销) |
| PS Ethernet 1Gbps (方案 B, 未来) | ~50 MB/s | ~0.08s |

### 10.4 总体预期

| 场景 | 现有 (计算+传输混合) | 新设计 (乒乓计算 + UART 回传) | 新设计 (乒乓计算 + PS 推送) |
|---|---|---|---|
| fast escape @128 | 3.733s | ~0.5s + 3.5s = 4.0s | ~0.5s + 0.08s = **0.58s** |
| deep minibrot @8192 | 5.091s | ~5.0s + 3.5s = 8.5s | ~5.0s + 0.08s = **5.08s** |

**方案 A**（UART 回传）总时间可能不优于现有设计，因为回传仍走 UART。**方案 B**（PS 推送）将回传从 3.5s 降到 <0.1s，浅场景从 3.7s 降到 **0.58s（6.4×）**。

**方案 A 的核心价值**：
1. 计算-传输解耦，worker 不受 UART 反压
2. 乒乓流水隐藏 DDR 写入延迟
3. tile retry 从 BRAM 缓存重发，无需重算
4. 为方案 B（PS 端推送）铺路

---

## 11. 实现计划

| 阶段 | 内容 | 产出 |
|---|---|---|
| Phase 1 | `tile_cache_db.v` (双缓冲) + `axi_ddr_writer.v` 实现 + 仿真 | RTL + testbench |
| Phase 2 | `cmd_parser_v2.v` + `top_with_ram.v` 集成 + 仿真 | RTL + testbench |
| Phase 3 | `build_mandelbrot_with_ram.tcl` 构建脚本 + BD 生成 | bitstream + XSA |
| Phase 4 | `boot_jtag.tcl` 空白启动脚本 + `psu_init.tcl` 生成 | boot 脚本 |
| Phase 5 | `mandelbrot_host.py` 扩展 `--with-ram` 模式 | host 软件更新 |
| Phase 6 | 烧板测试 + 六场景 benchmark | 性能数据 |

---

## 12. 结论

本设计将 Mandelbrot 加速器的传输路径从 UART 流式升级为 PL→PS DDR AXI 写入，采用**乒乓双缓冲**实现计算与 DDR 写入的流水化并行。参考 PL-PS-MEM-TEST 验证的 AXI HP 访问模式和空白启动流程。核心新增组件为 `tile_cache_db`（双缓冲 BRAM，存储 2 个 compute tile）和 `axi_ddr_writer`（AXI4 Master 写 PS DDR，独立运行）。Host 收到 `COMPUTE_DONE` 即可发下一条命令，FPGA 同时计算新 tile 到一个 buffer 并将旧 buffer 写入 DDR。tile retry 从 BRAM 缓存重发，无需重算。整个系统可在 SoC 空白配置下通过 JTAG `psu_init` + bitstream 烧录自洽启动，无需 FSBL 或 PS 端 C 程序。

---

## 13. 实践章节：实现、调试与当前状态

### 13.1 实现过程

#### 13.1.1 RTL 实现

新增 RTL 文件：

| 文件 | 功能 | 状态 |
|---|---|---|
| `rtl/top_with_ram.v` | PL-PS DDR 顶层，集成 multicore + output FIFO + axi_ddr_writer + cmd_parser_v2 | ✅ 已实现 |
| `rtl/axi_ddr_writer.v` | AXI4 Master，从 output FIFO 读取像素，打包成 64-bit beat，写入 PS DDR | ✅ 已实现 |
| `rtl/cmd_parser_v2.v` | 扩展命令解析器 + 响应发送器，支持 COMPUTE_TILE / ENTER_DOWNLOAD / ACK / TILE_DONE | ✅ 已实现 |
| `rtl/pl_por.v` | PL 本地复位（复用 PL-PS-MEM-TEST） | ✅ 已复用 |
| `rtl/tile_cache_db.v` | 乒乓双缓冲 BRAM | ⚠️ 已移除（见 13.2） |

修改的现有文件：无（新设计使用独立顶层 `top_with_ram`，不修改现有 RTL）。

#### 13.1.2 构建脚本

| 文件 | 功能 | 状态 |
|---|---|---|
| `build_mandelbrot_with_ram.tcl` | Vivado 构建脚本，创建 BD（PS + SmartConnect + top_with_ram + pl_por），综合，实现，生成 bitstream + XSA | ✅ 已实现 |
| `boot_jtag_with_ram.tcl` | JTAG 空白启动脚本（psu_init + bitstream 烧录） | ✅ 已实现 |
| `reference/design_1.bd` | PS 配置参考（复用 PL-PS-MEM-TEST） | ✅ 已复用 |

#### 13.1.3 Host 测试脚本

| 文件 | 功能 | 状态 |
|---|---|---|
| `python/test_ram_mode.py` | 小图 RAM 模式测试（4×4 tile） | ✅ 已实现 |
| `python/bench_ram_mode.py` | 六场景 1080p RAM 模式基准测试 | ✅ 已实现 |

### 13.2 设计调整与已修复的 Bug

实现过程中发现并修复了多个问题：

| Bug | 原因 | 修复 |
|---|---|---|
| `tile_cache_db` BRAM 超限 | 双缓冲 2×245760×16-bit = 214 BRAM36 > 128 设备上限 | **移除 tile_cache_db**，改为流式架构：multicore → output FIFO → axi_ddr_writer → DDR（与原 tx_ctrl → UART 架构对称） |
| `owner_mem` 4-bit 溢出 | >16 worker 时 core 索引截断（已在 fx64 阶段修复） | `owner_mem` 从 4-bit 扩至 8-bit |
| `core_fifo_full` 未驱动 | top_with_ram 中 `core_fifo_full` wire 悬空，multicore 无法感知 FIFO 满 | 添加 `assign core_fifo_full = !fifo_write_avail` |
| AXI writer 在 compute 完成后才启动 | 原设计等 compute_busy 变低才触发 AXI writer，但 FIFO（1024 entries）无法容纳全部像素 | 改为 compute_start 同时触发 AXI writer，计算与 DDR 写入并行流式运行 |
| cmd_parser_v2 状态机振荡 | S_RX_SYNC0 与 S_TX_IDLE 之间交替，可能错过 RX 数据 | 合并为单一 idle 状态 S_RX_SYNC0，直接检查 ack_pending / tile_done_pending |
| AXI burst 长度不匹配 | 像素数不是 BURST_BEATS×4 的整数倍时，WLAST 提前触发，SmartConnect 拒绝 | 改为始终发送完整 BURST_BEATS 拍，不足部分用零填充 |
| `ddr_write_done` 被 `compute_started` 门控 | AXI writer 可能在 multicore 声明 merge_done 前完成，导致 TILE_DONE 丢失 | 移除 `~compute_started` 门控 |
| X_INTERFACE_INFO 缺失 | BD 无法识别 top_with_ram 的 AXI 接口 | 为所有 AXI 信号添加 `(* X_INTERFACE_INFO = "..." *)` 属性 |
| PS AXI 时钟未连接 | `maxihpm0_lpd_aclk` 等时钟引脚悬空 | 构建脚本连接所有可能的 PS AXI 时钟引脚 |
| output FIFO 同步读延迟 | writer 在发出 `fifo_rd_en` 后过早采样 `fifo_rd_data`，首像素可能使用旧值 | 增加显式 `ST_READ_WAIT` 状态 |
| AXI AW 重复提交 | 等待第一个像素期间反复拉高相同 `AWVALID`，SmartConnect 接收多个重复地址事务，后续 W burst 与错误 AW 配对 | 增加独立 `ST_AW`，每个 128-byte burst 只允许一次 AW 握手；65 像素双 burst testbench 验证 |
| Host DDR 地址槽重叠 | tile 地址按有效字节紧邻分配，writer 尾部 128-byte padding 可覆盖下一 tile | Host 使用 `align_up(rows*cols*2, 128)` 分配物理槽 |
| 12 Mbaud 长流 byte slip | 大图某个 `RT/TD/TE` 下载可能失去 framing | Host 排空旧下载流后，对相同 DDR tile 重发 `ENTER_DOWNLOAD`，无需重算 |

### 13.3 当前验证状态

| 验证项 | 结果 | 详情 |
|---|---|---|
| Vivado 综合 + 实现 | ✅ PASS | 22 worker, LUT 86,450 (98.42%), registers 73,894, WNS=0.114ns, WHS=0.011ns, DSP 445, BRAM 46 |
| JTAG 空白启动 | ✅ PASS | `psu_init` 初始化 PS DDR（DEADBEEF 验证），bitstream 烧录成功 |
| UART ACK 响应 | ✅ PASS | COMPUTE_TILE 命令接收后 0.011s 内返回 ACK (type=0x81, status=0) |
| Mandelbrot 计算 | ✅ PASS | 4×4、160×120、161×121 edge-tiled 和 1920×1080 均完成 |
| AXI DDR 写入 | ✅ PASS | writer 单元测试覆盖同步 FIFO、65 像素双 burst、AW 地址唯一性、尾部 padding；板级 checksum 与下载数据一致 |
| AXI DDR 读取 | ✅ PASS | reader 单元测试覆盖 1/3/4/5/63/64/65/129 像素、16-bit lane 顺序和 4 KiB burst 边界 |
| UART DDR 回传 | ✅ PASS | 4×4 为 16/16，160×120 为 19200/19200，161×121 九 tile 为 19481/19481，1080p 为 2073600/2073600 软件匹配 |
| 1080p 时序 | ✅ PASS | fast escape：compute + DDR write 0.221s；无重试 UART download 3.779s |
| UART 重传 | ✅ PASS | 1080p 验证中注入/遇到 framing slip 后排空旧流并从 DDR 重读同一 tile，最终 100% 匹配 |

### 13.4 UART Debug 模式

为定位 TILE_DONE 通知 bug，设计了 UART QUERY_STATUS (type=0x02) 调试命令。FPGA 收到后返回 DEBUG_STATUS (type=0x90) 帧，包含 13 字节内部状态：

| Byte | 字段 | 说明 |
|---|---|---|
| 0 | cmd_state | cmd_parser_v2 状态机当前状态 (0-11) |
| 1 | flags | {compute_busy, ddr_write_busy, ddr_write_done, tile_done_pending, ack_pending, fifo_rd_avail, fifo_wr_avail, done_sticky} |
| 2 | axi_state | axi_ddr_writer 状态机 (0=IDLE,1=AW,2=GET,3=READ_WAIT,4=PACK,5=W,6=B,7=DONE) |
| 3 | cmd_state_raw | cmd_parser_v2 状态机原始值 |
| 4 | p_sent_lo | AXI writer 已发送像素数 (低 8 位) |
| 5 | p_total_lo | AXI writer 总像素数 (低 8 位) |
| 6-7 | checksum | 最后一次 TILE_DONE 的 checksum |
| 8 | ack_status | 最后一次 ACK 的状态 |
| 9 | rows | 当前 tile 行数 |
| 10 | cols | 当前 tile 列数 |
| 11 | max_iter_lo | 最大迭代数 (低 8 位) |

通过此调试通道，在发送 COMPUTE_TILE 后查询状态，发现 `axi_state=IDLE, p_sent=16, p_total=16, done_sticky=0`。这表明 AXI writer 已完成但 `done` 脉冲（1 拍）在 cmd_parser 处于 TX 状态时丢失。

**根因**：`done` 是 1 拍脉冲，但 `cmd_parser_v2` 在发送 ACK 帧时处于 TX 状态，无法捕获该脉冲。

**修复**：增加 `done_sticky`（电平信号，保持高直到 `done_ack` 清除）。`cmd_parser_v2` 在 TILE_DONE 帧 checksum 字节发送完后置 `done_ack=1`，并用 `ddr_done_seen` 防止在清除握手完成前重复排队 TILE_DONE。

### 13.5 从流式到双缓冲的架构调整

原设计使用 `tile_cache_db`（乒乓双缓冲 BRAM）缓存完整 compute tile。实现中发现双缓冲 2×245760×16-bit = 214 BRAM36 远超器件 128 BRAM 上限。因此调整为**流式架构**：

```mermaid
flowchart TB
    CORE["multicore<br/>22x fx worker"] -->|"fifo_wr"| FIFO["output FIFO<br/>1024x16"] -->|"rd_en/rd_data"| AXI["axi_ddr_writer<br/>64-bit AXI4 Master"] -->|"AXI HPC0"| DDR["PS DDR4"]
```

流式架构中，multicore 的 raster collector 将像素流式写入 output FIFO，axi_ddr_writer 同时从 FIFO 读取并写入 DDR。这实现了计算与 DDR 写入的自然并行，无需双缓冲 BRAM。AXI DDR 带宽（~500 MB/s）远超像素产出速率，FIFO 几乎不会填满。

**代价**：失去 BRAM 缓存，tile retry 需要重新计算（回退到与 UART 设计相同的重算策略）。未来可通过小型 retry cache（仅缓存最近 1-2 个 retry tile 切片，~2-4 BRAM36）恢复缓存能力。

### 13.6 done_sticky + done_ack 握手协议

```mermaid
sequenceDiagram
    participant AXI as axi_ddr_writer
    participant CMD as cmd_parser_v2
    participant UART as uart_tx

    AXI->>AXI: ST_DONE: done=1 (pulse), done_latched=1
    CMD->>CMD: ddr_write_done(=done_sticky) detected → tile_done_pending=1
    CMD->>UART: Send ACK frame (if pending)
    CMD->>UART: Send TILE_DONE frame
    UART->>CMD: checksum byte sent
    CMD->>AXI: done_ack=1 (1-cycle pulse)
    AXI->>AXI: done_latched=0 (cleared)
    CMD->>CMD: ddr_done_seen prevents re-trigger until done_sticky=0
```

### 13.7 资源利用

| 资源 | fx64 24w (UART baseline) | PL-PS DDR 22w | 变化 |
|---|---|---|---|
| CLB LUTs | 83,731 (95.32%) | 86,450 (98.42%) | +2,719 (PS + AXI read/write + UART download) |
| DSP48E2 | 483 (66.3%) | 445 (61.1%) | -38 (22 vs 24 workers; AXI infrastructure adds 3 DSP) |
| Block RAM | 33 (25.8%) | 46 (35.9%) | +13 (PS infra) |
| WNS | 0.078ns | 0.114ns | Timing met at 200 MHz |

### 13.8 六场景基准测试结果

#### 13.8.1 公平对比方法

旧 UART 设计中，计算与传输在每个 tile 内流水重叠：multicore 计算当前 tile 的同时，`tx_ctrl` 经 UART 发送前一个 tile 的像素。因此旧设计的总时间 ≈ max(计算时间, 传输时间)，传输主导浅场景。

新 DDR 设计将流程分为两个串行阶段：
1. **计算阶段**：所有 tile 依次计算并写入 DDR（无 UART 反压）
2. **下载阶段**：所有 tile 依次从 DDR 读出并经 UART 回传

因此新设计的总时间 = 计算时间 + 下载时间（不重叠）。

#### 13.8.2 六场景端到端对比

| 场景 | 旧 UART 24w (s) | DDR 计算 (s) | DDR 下载 (s) | DDR 合计 (s) | 端到端加速比 |
|---|---|---|---|---|---|
| fast escape @128 | 3.733 | 0.221 | 4.369 | 4.590 | 0.81× |
| standard @64 | 3.727 | 0.223 | 4.373 | 4.596 | 0.81× |
| Seahorse @512 | 3.882 | 1.086 | 5.009 | 6.095 | 0.64× |
| deep tendrils @8192 | 5.029 | 1.950 | 5.002 | 6.952 | 0.72× |
| deep minibrot @8192 | 5.091 | 5.104 | 4.418 | 9.522 | 0.53× |
| deep Seahorse @1024 | 4.074 | 2.254 | 4.406 | 6.660 | 0.61× |

> 下载时间含 12 Mbaud 偶发 byte slip 的重传开销。无重传时纯下载约 3.8s（9 tile × ~0.42s）。

#### 13.8.3 分析

**端到端反而变慢的原因**：

旧设计每个 tile 的计算与 UART 传输流水重叠。以 fast escape 为例：
- 旧设计：9 tile × max(计算~0.025s, 传输~0.42s) ≈ 9 × 0.42s ≈ 3.8s（传输主导）
- 新设计：计算 0.22s + 下载 4.4s = 4.6s（串行，不重叠）

新设计的计算阶段虽然 17× 更快（0.22s vs 旧设计受 UART 反压的等效计算时间），但下载阶段额外增加了 ~4.4s，而旧设计中这部分时间被计算流水隐藏了。

**DDR 模式的核心价值**：

1. **计算解耦**：计算阶段不受 UART 反压，22 个 worker 全速运行，适用于计算 profiling 和 benchmark。
2. **无损重传**：像素保存在 DDR 中，UART 下载失败可从 DDR 重读，无需重算。旧设计中 UART framing 失败需要重算整个 compute tile。
3. **未来高速通道**：一旦实现 PS 端 Ethernet/USB 推送（方案 B），下载时间从 ~4.4s 降至 <0.1s，端到端将获得完整加速。届时：
   - fast escape: 0.22s + 0.08s ≈ **0.30s**（vs 旧 3.73s，**12×**）
   - deep minibrot: 5.10s + 0.08s ≈ **5.18s**（vs 旧 5.09s，持平，计算主导）

#### 13.8.4 端到端正确性验证

| 测试 | 像素匹配 | 说明 |
|---|---|---|
| 4×4 | 16/16 (100%) | 单 burst、最小 tile |
| 160×120 | 19200/19200 (100%) | 多 burst、128-byte 对齐 |
| 161×121 (9 tile) | 19481/19481 (100%) | 边缘 tile、padding、多 DDR slot |
| 1920×1080 fast escape | 2073600/2073600 (100%) | 9 tile、含一次 DDR 重传 |
| 1920×1080 deep minibrot | 完整图像输出 | 9 tile、含一次 DDR 重传 |

### 13.9 Retry Tile 设计分析

#### 13.9.1 理想设计

理想 retry 流程：Host 请求一个 compute tile → DDR 读入 FIFO → UART 分块回传 → Host 检查每个 TD 的 XOR8 checksum → 若某个 TD 失败，FPGA 从 FIFO 中仅重传该 TD 对应的行切片。

这要求 FPGA 在下载阶段保留完整 tile 数据在 BRAM FIFO 中，支持按行范围重读。

#### 13.9.2 BRAM 可行性分析

一个 1920×120 tile = 460,800 字节。以 BRAM36（4.5 KiB）计，需要 ~100 块。器件仅有 128 块 BRAM，且已有 46 块被 PS 基础设施和 worker FIFO 占用。完整 tile BRAM 缓存不可行。

`tx_ctrl` 的 `RESPONSE_TILE_ROW_SPLITS=8` 将 tile 切成 8 个行切片（每个 1920×15 = 57,600 字节 ≈ 13 BRAM36）。缓存单个行切片需要 ~13 块 BRAM36，仍有余量，但需要额外的 retry 命令协议和 BRAM 控制器。

#### 13.9.3 当前实现

当前采用**整 tile 从 DDR 重传**策略：
- DDR 中保留了完整 tile 数据（不受 BRAM 限制）。
- 若某个 TD 的 XOR8 失败或 UART framing 失败，Host 排空旧下载流后，对相同 DDR 地址重发 `ENTER_DOWNLOAD`。
- FPGA 从 DDR 重新读取完整 tile，不重算。
- 这避免了重算开销，同时不需要额外 BRAM。

**代价**：重传整个 tile（~0.42s/tile @ 12 Mbaud），而非仅重传失败的行切片（~0.05s）。在 12 Mbaud 偶发 byte slip 场景下，这是可接受的折中。

#### 13.9.4 未来改进

若需局部 retry，可增加一个 ~13 BRAM36 的行切片缓存，配合 `RETRY_TILE` 命令按行范围重传。但这需要：
- 新增 BRAM 缓存模块
- 扩展 `ENTER_DOWNLOAD` 协议支持行范围参数
- `tx_ctrl` 支持从 BRAM 缓存而非 DDR reader 读取像素

### 13.10 当前回传验证与下一步

1. **回传阶段（已实现）**：Host 发送 `ENTER_DOWNLOAD`，payload 为 `ddr_base(u64 LE) + rows(u16 LE) + cols(u16 LE)`。PL 侧 `axi_ddr_reader` 通过 AXI AR/R 通道读取 DDR，复用 `tx_ctrl` 产生 `RT/TD/TE` 并经 UART 返回 Host。
2. **端到端校验（已实现）**：Host 校验每个 TD 的 XOR8，并将下载像素 XOR16 与计算阶段 `TILE_DONE` checksum 对比。
3. **DDR tile 布局（已实现）**：物理槽按 128 bytes 对齐，`slot_bytes = align_up(rows * cols * 2, 128)`。
4. **宽图切分（已实现）**：DDR 模式默认 tile 宽度上限 4096，避免超宽 compute tile 导致板上逻辑问题。
5. **可继续优化**：降低 12 Mbaud byte-slip 发生率、增加控制响应 tile ID、将 reader error 通过稳定控制帧返回、优化 LUT 以恢复更多 worker、局部 retry tile 缓存。
6. **未来高速方案**：实现 PS 端 Ethernet/USB 推送，绕过 UART 下载带宽上限。
