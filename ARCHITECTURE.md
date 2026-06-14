# Mandelbrot FPGA Accelerator Architecture

## 1. Overview

This project implements a UART-controlled Mandelbrot accelerator on FPGA. The host sends one binary command describing a complete image, and the FPGA streams back one 16-bit iteration count per pixel. The current default configuration is FP64, four Mandelbrot workers, two pixel contexts per worker, dynamic row scheduling, `FP_CE_DIV=1`, true 100 MHz operation, and a 12 Mbaud fractional-NCO UART.

The design is intentionally streaming-oriented. It does not store a full frame on FPGA. A dynamic row dispatcher assigns one row at a time to available workers, each worker interleaves two pixel contexts over one shared FP64 multiplier and one shared FP64 adder, per-core FIFOs absorb row output, a raster-order collector restores the original host-visible pixel order, and the transmit controller streams pixels to the host as soon as they are available.

Current validated capabilities:

| Item | Value |
|---|---:|
| System clock | 100 MHz |
| FP/core effective clock enable rate | 100 MHz (`FP_CE_DIV=1`) |
| Mandelbrot workers | 4 |
| Pixel contexts per worker | 2 |
| Default scheduler | Dynamic idle-core row scheduling (`SCHED_MODE=1`) |
| UART baudrate | 12000000 baud |
| Pixel format | `uint16`, little-endian iteration count |
| Maximum iteration count | 65535 |
| Width/height fields | 16-bit each |
| Pixel count path | 32-bit, validated above 65535 pixels |
| Largest validated image | 1920x1080 |
| Stable mode used in testing | FP64 |
| Current routed timing | `WNS=0.285ns`, `TNS=0.000ns`, `WHS=0.021ns`, `THS=0.000ns` |
| Current placed utilization | `13917` LUTs, `14458` registers, `37` DSP48E1, `9.5` BRAM tiles |

## 2. Top-Level Architecture

Top-level integration is in `rtl/top.v`.

```text
Host PC
  |
  |  UART command: center, step, max_iter, rows, cols
  v
uart_rx
  |
  v
cmd_parser
  |
  |  compute_start, image parameters
  v
mandelbrot_multicore -- raster fifo_wr/fifo_data --> queue(1024 x 16-bit) --> tx_ctrl --> uart_tx
       |
       +-- work_dispatch_dynamic_rows
       +-- 4 x mandelbrot_core_worker_2ctx -- per-core FIFO --> raster_collect_dynamic_rows
              |
              +-- fp_mul
              +-- fp_add
```

The main modules are:

| Module | File | Role |
|---|---|---|
| `top` | `rtl/top.v` | Instantiates clock-enable generator, UART, command parser, 4-core wrapper, output FIFO, and TX controller. |
| `uart_rx` | `rtl/uart_rx.v` | Receives 8N1 UART bytes using a fractional baud accumulator. |
| `uart_tx` | `rtl/uart_tx.v` | Sends 8N1 UART bytes using a fractional baud accumulator. |
| `cmd_parser` | `rtl/cmd_parser.v` | Parses command packet and validates XOR checksum. |
| `mandelbrot_multicore` | `rtl/mandelbrot_multicore.v` | 4-core wrapper with scheduler, per-core FIFOs, raster merger, and `tx_start` handling. |
| `work_dispatch_static_rows` | `rtl/work_dispatch_static_rows.v` | Static regression scheduler. Assigns interleaved rows to workers. |
| `work_dispatch_dynamic_rows` | `rtl/work_dispatch_dynamic_rows.v` | Default scheduler. Assigns one full row at a time to an available worker and records row ownership. |
| `mandelbrot_core_worker_2ctx` | `rtl/mandelbrot_core_worker_2ctx.v` | Default two-context row worker. Interleaves two pixel contexts over one FP64 multiplier and one FP64 adder. |
| `mandelbrot_core_worker_kctx` | `rtl/mandelbrot_core_worker_kctx.v` | Experimental parameterized 4/8-context worker used for feasibility synthesis only; not a deployable xc7z010 default. |
| `mandelbrot_core_worker` | `rtl/mandelbrot_core_worker.v` | Stable single-context row worker used by static regression builds. |
| `raster_merge_static_rows` | `rtl/raster_merge_static_rows.v` | Static-mode merger. Restores per-worker row streams to strict row-major output order. |
| `raster_collect_dynamic_rows` | `rtl/raster_collect_dynamic_rows.v` | Default dynamic result collector. Uses the row-owner table to drain dynamically assigned rows in raster order. |
| `mandelbrot_core` | `rtl/mandelbrot_core.v` | Legacy/single-core raster-order Mandelbrot engine used by regression simulation. |
| `fp_mul` | `rtl/fp_mul.v` | Parameterized FP multiplier. |
| `fp_add` | `rtl/fp_add.v` | Parameterized FP adder/subtractor. |
| `queue` | `rtl/queue.v` | Synchronous FIFO for per-core and output buffering. |
| `tx_ctrl` | `rtl/tx_ctrl.v` | Builds response header, drains FIFO, transmits pixels and checksum. |

## 3. Command And Response Protocol

The protocol is binary, little-endian, and frame-oriented. One command produces one full image response.

### 3.1 Host To FPGA Command

FP64 command length is 33 bytes. FP128 command length is 57 bytes.

| Offset | Size | Field |
|---:|---:|---|
| 0 | 1 | Magic byte `0x4D` |
| 1 | 1 | Precision flag, bit0 `0=FP64`, `1=FP128` |
| 2 | 2 | `rows`, uint16 LE |
| 4 | 2 | `cols`, uint16 LE |
| 6 | 2 | `max_iter`, uint16 LE |
| 8 | 8 or 16 | `center_re`, FP64 or FP128 LE |
| 16 or 24 | 8 or 16 | `center_im`, FP64 or FP128 LE |
| 24 or 40 | 8 or 16 | `step`, FP64 or FP128 LE |
| Last | 1 | XOR checksum over all previous bytes |

`cmd_parser` assembles these fields with byte-wise shift registers and only starts computation if the XOR including the received checksum is zero.

### 3.2 FPGA To Host Response

Response length is `6 + 2 * rows * cols + 1` bytes.

| Offset | Size | Field |
|---:|---:|---|
| 0 | 1 | `0x52`, ASCII `R` |
| 1 | 1 | `0x4B`, ASCII `K` |
| 2 | 2 | `rows`, uint16 LE |
| 4 | 2 | `cols`, uint16 LE |
| 6 | `2*N` | Pixel data, uint16 LE per pixel |
| Last | 1 | XOR checksum over pixel bytes only |

The host currently computes the response checksum over pixel data only, matching `tx_ctrl`.

## 4. Clocking And Clock-Enable Design

The board provides a 100 MHz `sys_clk`. The design uses one actual clock domain for all logic. UART, parser, FIFO, TX controller, floating-point datapath, and Mandelbrot core all run in that clock domain. The `fp_ce` signal is retained as a compile-time throttle, but the current FP64 configuration sets `FP_CE_DIV=1`, so it is asserted every clock.

`fp_ce` is generated in `top.v`:

```verilog
reg [`FP_CE_DIV-1:0] ce_counter;
wire fp_ce;
assign fp_ce = (`FP_CE_DIV == 1) ? 1'b1 : (ce_counter == `FP_CE_DIV - 1);
```

Current `rtl/fp_defines.vh` sets:

```verilog
`define FP_CE_DIV 1
```

Therefore the core and FP units advance every system cycle, giving true 100 MHz datapath operation while preserving one physical clock domain.

### 4.1 Why Clock Enable Instead Of A Derived Clock

The design previously used derived/pseudo clocks in the UART area and later moved to a single-clock style. The current single-clock + enable approach avoids clock-domain crossing issues and simplifies timing closure.

Benefits:

| Benefit | Explanation |
|---|---|
| No generated clock tree | All registers are clocked by `sys_clk`. |
| No CDC between core and UART | FIFO and handshake signals stay in one clock domain. |
| Easier reset and debug | One synchronous timing model. |
| STA remains direct | Current FP64 timing uses normal single-cycle 100 MHz constraints. |

### 4.2 Timing Constraints

Current FP64 builds use normal single-cycle timing at 100 MHz. No `u_core` multicycle exceptions are required. Older effective-50 MHz experiments used `FP_CE_DIV=2` plus setup/hold multicycle constraints, but the current pipelined FP datapath closes timing at `FP_CE_DIV=1`.

Current routed timing after dynamic scheduling and 2-context worker integration:

| Metric | Value |
|---|---:|
| WNS | 0.285 ns |
| TNS | 0.000 ns |
| WHS | 0.021 ns |
| THS | 0.000 ns |

## 5. Floating-Point Format

The project uses parameterized binary floating-point formats selected at compile time with `fp_defines.vh`.

| Parameter | FP64 | FP128 |
|---|---:|---:|
| Total width | 64 | 128 |
| Sign bits | 1 | 1 |
| Exponent bits | 11 | 15 |
| Mantissa bits | 52 | 112 |
| Bias | 1023 | 16383 |
| Max normal exponent macro | 2046 | 32766 |

The implementation is IEEE-like but not a full IEEE-754 implementation. It is sufficient for the project workload, but it does not implement all special cases.

Important simplifications:

| Feature | Current behavior |
|---|---|
| Denormals | Not fully supported; zero-like behavior is used. |
| NaN/Inf | Not intended as input or output. |
| Rounding | Truncation/limited normalization behavior, not full IEEE rounding. |
| Exceptions | No exception flags. |

The FPGA and software reference are compared against the implemented RTL behavior, not a full IEEE-754 formal model. A detailed analysis of boundary pixel differences (truncation vs IEEE round-to-nearest-even) is available in [FP64_BOUNDARY_DIFFERENCE_ANALYSIS.md](FP64_BOUNDARY_DIFFERENCE_ANALYSIS.md).

## 6. Floating-Point Multiplier Pipeline

`fp_mul.v` implements multiplication for FP64/FP128 using parameterized exponent and mantissa widths.

Algorithm summary:

1. Register inputs when `ce` is asserted.
2. Detect zero operands.
3. Compute result sign as `a.sign ^ b.sign`.
4. Add exponents and subtract bias.
5. Multiply hidden-bit mantissas: `{1'b1, a.man} * {1'b1, b.man}`.
6. Register DSP product and metadata.
7. Normalize based on the product MSB.
8. Register final output.

Detailed multiplier pipeline:

```mermaid
flowchart TB
    IN["Input a,b"] --> R0[["Stage M0<br/>input registers<br/>a_r,b_r"]]
    R0 --> D0("Stage M1 comb<br/>decode sign/exp/man<br/>zero detect")
    D0 --> R1[["Stage M1 reg<br/>full_man_a_r/full_man_b_r<br/>result_sign_man_r<br/>exp_sum_man_r<br/>zero flags"]]
    R1 --> DSP("Stage M2 comb<br/>FP64 53x53 mantissa multiply<br/>DSP48E1 cascade")
    DSP --> R2[["Stage M2 reg<br/>man_product_dsp_r<br/>metadata delay"]]
    R2 --> R3[["Stage M3 reg<br/>product + sign/exp/zero aligned"]]
    R3 --> NORM("Stage M4 comb<br/>normalize product<br/>adjust exponent<br/>zero/overflow handling")
    NORM --> OUT[["Stage M4 reg<br/>product output"]]
```

Shape convention: rounded boxes are combinational logic; double-sided boxes are register stages.

Pipeline intent:

| Stage | Main registers | Purpose |
|---|---|---|
| M0 | `a_r`, `b_r` | Isolate caller routing from FP decode. |
| M1 | decoded mantissas and metadata | Remove zero mux and sign/exponent decode from DSP input path. |
| M2 | `man_product_dsp_r` | Register DSP cascade output. |
| M3 | product/metadata alignment registers | Align delayed sign/exponent/zero flags with product. |
| M4 | `product` | Normalize and publish final FP value. |

The multiplier includes input, decoded-mantissa, DSP-product, and metadata registers to improve timing. The decoded-mantissa stage removes zero mux and exponent/sign decode logic from the DSP input path. The multiplication is annotated with:

```verilog
(* mult_style = "pipe_block" *)
```

This encourages DSP-based implementation. The Zynq-7010 implementation uses multiple DSP48E1s for FP64 mantissa multiplication.

### 6.1 Multiplier Pipeline Behavior

The core does not assume a single-cycle FP unit. Instead, it issues an operation and waits `PIPE_WAIT` CE cycles before capturing the result. Current worker and legacy single-core RTL use:

```verilog
localparam PIPE_WAIT = 10;
```

This wait value is conservative relative to the internal FP pipeline and has been validated in simulation and hardware at true 100 MHz. It increased from 9 to 10 when the 4-core build added one more adder output-side pipeline stage to close timing.

## 7. Floating-Point Adder Pipeline

`fp_add.v` implements both addition and subtraction. Subtraction is performed by flipping the sign of operand B before entering the adder:

```verilog
wire [`FP_WIDTH-1:0] add_b_eff = add_neg ? {~add_b[`FP_SIGN_IDX], add_b[`FP_EXP_HI:0]} : add_b;
```

Algorithm summary:

1. Register inputs on `ce`.
2. Decode signs, exponents, and mantissas.
3. Compare magnitudes and register the selected large/small operands.
4. Align the smaller mantissa by exponent difference.
5. Add or subtract aligned mantissas depending on signs.
6. Register intermediate mantissa/sign/exponent information.
7. Normalize the mantissa.
8. Adjust exponent.
9. Register output.

Detailed adder/subtractor pipeline:

```mermaid
flowchart TB
    IN["Input a,b"] --> R0[["Stage A0<br/>input registers<br/>a_r,b_r"]]
    R0 --> D0("Stage A1 comb<br/>decode sign/exp/man<br/>zero detect<br/>compare magnitude")
    D0 --> R1[["Stage A1 reg<br/>large/small mantissas<br/>exp_large,diff<br/>signs,zero flags"]]
    R1 --> ALIGN("Stage A2 comb<br/>right shift small mantissa<br/>add/sub aligned mantissas")
    ALIGN --> R2[["Stage A2 reg<br/>man_result_r<br/>exp/sign/zero/input bypass"]]
    R2 --> LZ("Stage A3 comb<br/>leading-zero scan<br/>normalize mantissa<br/>adjust exponent")
    LZ --> R3[["Stage A3 reg<br/>man_final_r<br/>exp_final_r<br/>sign_final_r<br/>zero/bypass flags"]]
    R3 --> OF("Stage A4 comb<br/>overflow test<br/>final mux")
    OF --> OUT[["Stage A4 reg<br/>sum output"]]
```

Shape convention: rounded boxes are combinational logic; double-sided boxes are register stages.

Pipeline intent:

| Stage | Main registers | Purpose |
|---|---|---|
| A0 | `a_r`, `b_r` | Isolate caller routing and provide stable decode inputs. |
| A1 | `man_large_s1`, `man_small_s1`, `exp_large_s1`, `diff_s1` | Cut decode/compare/select away from alignment and add/sub. |
| A2 | `man_result_r`, `exp_large_r`, `sign_large_r` | Register add/sub result before normalization. |
| A3 | `man_final_r`, `exp_final_r`, `sign_final_r` | Register normalized result before overflow/final mux. |
| A4 | `sum` | Publish zero bypass, overflow-zero, or normal FP result. |

Important fixes already made in this design:

| Issue | Fix |
|---|---|
| Wrong same-sign normalization slice | Corrected carry/no-carry mantissa extraction. |
| Negative add/sub mismatch | Added tests and fixed sign/magnitude handling. |
| Input timing pressure | Added input registers. |
| 100 MHz adder critical path | Split decode/compare/select from align/add-sub. |
| Output normalization timing | Added output-side normalization/output registers. |

## 8. Mandelbrot Core Architecture

`mandelbrot_core_worker.v` computes one interleaved subset of rows. The legacy `mandelbrot_core.v` computes pixels in raster order and remains useful for focused single-core regression. For each pixel, both engines iterate:

```text
z_{n+1} = z_n^2 + c

z_re_next = z_re^2 - z_im^2 + c_re
z_im_next = 2 * z_re * z_im + c_im
escape if z_re^2 + z_im^2 > 4
```

Each worker uses one FP multiplier and one FP adder. It time-multiplexes those units across each iteration through a finite-state machine. The 4-core wrapper instantiates four independent workers.

### 8.1 Coordinate Generation

The host provides image center and pixel step. The RTL uses integer-truncated half dimensions:

```text
half_w = (cols - 1) >> 1
half_h = (rows - 1) >> 1

c_re_start = center_re - half_w * step
c_im_start = center_im + half_h * step
```

For each row in the single-core engine:

```text
c_re = c_re_start
for each column: c_re += step
after row: c_im -= step
```

The software reference intentionally mirrors this integer-center behavior. This avoids false mismatches versus a conventional floating-centered renderer.

Worker coordinate initialization pipeline:

```mermaid
flowchart TB
    START["compute_start + image parameters"] --> HW("Compute half_w<br/>(cols - 1) >> 1")
    HW --> MW("Issue half_w * step<br/>fp_mul")
    MW --> RE0("Issue center_re - half_w_step<br/>fp_add")
    RE0 --> CRE[["c_re_start ready"]]
    CRE --> HH("Compute half_h<br/>(rows - 1) >> 1")
    HH --> MH("Issue half_h * step<br/>fp_mul")
    MH --> IMTOP("Issue center_im + half_h_step<br/>fp_add")
    IMTOP --> CIMTOP[["c_im_top ready"]]
    CIMTOP --> RS("Issue row_stride * step<br/>fp_mul")
    RS --> ROWSTEP[["row_step ready"]]
    ROWSTEP --> RSOFF("Issue row_start * step<br/>fp_mul")
    RSOFF --> RSUB("Issue c_im_top - row_start_step<br/>fp_add")
    RSUB --> FIRSTROW[["first worker row c_im ready"]]
```

Shape convention: rounded boxes are issued combinational computations or FP operations; double-sided boxes are registered ready values captured after `PIPE_WAIT`.

For the current 4-core static scheduler, `row_stride=4` for every worker and `row_start` is the worker ID. This lets each worker advance from row `y` to row `y+4` with one precomputed FP decrement.

### 8.2 4-Core Row Scheduling

`mandelbrot_multicore` supports a compile-time scheduling parameter:

| Parameter | Value | Meaning |
|---|---:|---|
| `SCHED_MODE` | `0` | Static interleaved rows, default board mode. |
| `SCHED_MODE` | `1` | Dynamic idle-core row scheduling. |
| `DYNAMIC_OWNER_DEPTH` | `4096` default | Owner-table rows available in dynamic mode. |

The default multi-core scheduler uses static interleaved rows:

| Core | First row | Stride | Rows |
|---:|---:|---:|---|
| 0 | 0 | 4 | `0, 4, 8, ...` |
| 1 | 1 | 4 | `1, 5, 9, ...` |
| 2 | 2 | 4 | `2, 6, 10, ...` |
| 3 | 3 | 4 | `3, 7, 11, ...` |

This is implemented by `work_dispatch_static_rows.v`. The worker receives `row_start_in` and `row_stride_in`, computes `row_stride * step` once during initialization, and then jumps directly from one assigned row to the next.

The scheduler is intentionally modular. Dynamic row scheduling is now the default build mode, while static interleaved rows remain as a regression path. Future dynamic tile scheduling or out-of-order row dispatch can still replace the scheduler/collector pair without changing the UART command parser or the worker arithmetic datapath.

Static dispatch structure:

```mermaid
flowchart LR
    PARAM["Image parameters<br/>center, step, rows, cols, max_iter"] --> DISP["work_dispatch_static_rows"]
    DISP -->|"start,row_start=0,row_stride=4"| C0["worker 0"]
    DISP -->|"start,row_start=1,row_stride=4"| C1["worker 1"]
    DISP -->|"start,row_start=2,row_stride=4"| C2["worker 2"]
    DISP -->|"start,row_start=3,row_stride=4"| C3["worker 3"]

    subgraph ReplaceableBoundary[Replaceable scheduling boundary]
        DISP
    end
```

Dispatch is combinational for the current policy: every worker receives the same render parameters and a different row-start value. This keeps scheduler timing shallow and makes the future replacement point explicit.

Dynamic idle-core scheduling uses `work_dispatch_dynamic_rows.v`. It reuses the existing row-start/stride worker interface by making each job one full row:

```text
row_start = assigned row
row_stride = rows
```

Because `row + row_stride >= rows` after one row, the existing worker finishes after that row and returns `done`. The dynamic dispatcher tracks which cores are active, waits for `done` to return low before reusing a core, and assigns the next unissued row to the first available core. It also emits `owner_row` and `owner_core` so the collector can later restore raster order.

The dispatcher also waits until the selected core FIFO is empty before assigning another row to that core. This is a deliberate backpressure rule. A 1080p fast-escape workload can compute rows faster than UART can transmit them; without this guard, future rows can fill a per-core FIFO while the raster collector is waiting for an earlier row from that same core, creating a strict-raster deadlock. Requiring an empty per-core FIFO before row reuse keeps at most one completed row queued per core and preserves forward progress under UART backpressure.

Dynamic dispatch structure:

```mermaid
flowchart LR
    PARAM["Image parameters<br/>center, step, rows, cols, max_iter"] --> DYN["work_dispatch_dynamic_rows"]
    DONE["worker done pulses"] --> DYN
    DYN -->|"next row job"| C0["worker 0"]
    DYN -->|"next row job"| C1["worker 1"]
    DYN -->|"next row job"| C2["worker 2"]
    DYN -->|"next row job"| C3["worker 3"]
    DYN --> OWNER[["row owner table update<br/>row -> core"]]
```

Dynamic mode preserves the existing host-visible raster stream. It is useful for row-level load-balance experiments and is now the default scheduling layer, but it does not by itself remove worker-internal FP pipeline bubbles and cannot improve scenes already capped by UART bandwidth.

### 8.3 Raster Merge

The unchanged host protocol expects pixels in row-major order with no row or tile IDs. Static mode uses `raster_merge_static_rows.v`; dynamic mode uses `raster_collect_dynamic_rows.v`. Both preserve that contract in hardware.

For output row `y`:

```text
source_core = y % 4
```

The merger waits until the selected core FIFO has data, reads one pixel, waits one synchronous FIFO read cycle, and writes the pixel into the shared output FIFO. This keeps the host protocol unchanged while allowing workers to run independently behind per-core FIFOs.

In dynamic mode, `raster_collect_dynamic_rows.v` first waits until the owner table has an entry for the current raster row. The source core is then `owner_mem[row]`, not `row % CORE_COUNT`. After source selection, FIFO read/write sequencing is the same as the static merger. `DYNAMIC_OWNER_DEPTH` bounds the owner table; the default `4096` rows covers the validated 1080p use case.

Raster merge pipeline:

```mermaid
flowchart TB
    POS["Current output position<br/>row,col,pixels_written"] --> SEL["Select source_core = row % 4"]
    SEL --> WAIT{"Selected core FIFO has data<br/>and output FIFO not full?"}
    WAIT -->|no| SEL
    WAIT -->|yes| RD[Assert selected core_fifo_rd]
    RD --> RWAIT["Wait one cycle<br/>synchronous FIFO data valid"]
    RWAIT --> WR["Write fifo_data to shared output FIFO"]
    WR --> ADV["Advance col; wrap to next row"]
    ADV --> DONE{"all pixels emitted?"}
    DONE -->|no| POS
    DONE -->|yes| FRAME_DONE[merge done]
```

Merger state machine:

```mermaid
stateDiagram-v2
    [*] --> S_IDLE
    S_IDLE --> S_WAIT: start
    S_WAIT --> S_READ_WAIT: selected FIFO ready and output FIFO not full
    S_READ_WAIT --> S_WRITE: read data valid
    S_WRITE --> S_WAIT: more pixels
    S_WRITE --> S_DONE: last pixel
    S_DONE --> S_IDLE
```

Dynamic collector behavior:

```mermaid
flowchart TB
    POS["Current output row,col"] --> OWN{"Owner entry exists<br/>for current row?"}
    OWN -->|no| POS
    OWN -->|yes| SRC["source_core = owner[row]"]
    SRC --> WAIT{"Selected FIFO has data<br/>and output FIFO not full?"}
    WAIT -->|no| SRC
    WAIT -->|yes| RD["Assert selected core_fifo_rd"]
    RD --> RWAIT["Wait one cycle"]
    RWAIT --> WR["Write pixel to shared FIFO"]
    WR --> ADV["Advance raster position"]
```

### 8.4 Per-Pixel FSM Pipeline

The core advances one FSM state per asserted `ce`, except when `pipe_wait` is nonzero. Each FP operation is issued, then the FSM waits `PIPE_WAIT` CE pulses before consuming the registered result.

Per-iteration sequence:

```text
S_ITER_START
  z_re = 0, z_im = 0, iter = 0
  issue z_re * z_re

S_MUL_ZRSQ_CAPT
  capture z_re_sq
  issue z_im * z_im

S_MUL_ZISQ_CAPT
  capture z_im_sq
  issue z_re * z_im
  issue z_re_sq + z_im_sq for escape check

S_MUL_ZRZI_CAPT
  capture z_re_z_im
  check quick escape against z_re_sq, z_im_sq, and add_result
  if escaped: output current iter
  else issue z_re_sq - z_im_sq

S_SUB_RE_CAPT
  capture difference
  issue difference + c_re

S_ADD_NEXTRE_CAPT
  capture z_re_next
  issue z_re_z_im + z_re_z_im

S_ADD_2X_CAPT
  capture 2*z_re*z_im
  issue 2*z_re*z_im + c_im

S_ADD_NEXTIM_CAPT
  capture z_im_next
  iter++

S_ITER_INC
  if iter >= max_iter: output
  else issue next z_re * z_re
```

Per-iteration issue/capture pipeline view:

```mermaid
flowchart TB
    I0["S_ITER_START<br/>issue z_re*z_re"]
    I0 --> W0["wait PIPE_WAIT"]
    W0 --> I1["S_MUL_ZRSQ_CAPT<br/>capture z_re_sq<br/>issue z_im*z_im"]
    I1 --> W1["wait PIPE_WAIT"]
    W1 --> I2["S_MUL_ZISQ_CAPT<br/>capture z_im_sq<br/>issue z_re*z_im<br/>issue z_re_sq+z_im_sq"]
    I2 --> W2["wait PIPE_WAIT"]
    W2 --> I3["S_MUL_ZRZI_CAPT<br/>capture z_re_z_im<br/>check escape"]
    I3 -->|not escaped| I4["issue z_re_sq-z_im_sq"]
    I3 -->|escaped| OUT["output iter"]
    I4 --> W3["wait PIPE_WAIT"]
    W3 --> I5["S_SUB_RE_CAPT<br/>issue diff+c_re"]
    I5 --> W4["wait PIPE_WAIT"]
    W4 --> I6["S_ADD_NEXTRE_CAPT<br/>capture z_re_next<br/>issue z_re_z_im+z_re_z_im"]
    I6 --> W5["wait PIPE_WAIT"]
    W5 --> I7["S_ADD_2X_CAPT<br/>issue 2*z_re*z_im+c_im"]
    I7 --> W6["wait PIPE_WAIT"]
    W6 --> I8["S_ADD_NEXTIM_CAPT<br/>capture z_im_next<br/>iter++"]
    I8 --> I9["S_ITER_INC"]
    I9 -->|iter < max_iter| I0
    I9 -->|iter >= max_iter| OUT
```

Operation schedule per non-escaping iteration:

| FSM point | Multiplier action | Adder action | Captured value |
|---|---|---|---|
| `S_ITER_START` | `z_re * z_re` | none | none |
| `S_MUL_ZRSQ_CAPT` | `z_im * z_im` | none | `z_re_sq` |
| `S_MUL_ZISQ_CAPT` | `z_re * z_im` | `z_re_sq + z_im_sq` | `z_im_sq` |
| `S_MUL_ZRZI_CAPT` | none | conditional escape decision | `z_re_z_im` |
| `S_SUB_RE_CAPT` | none | `(z_re_sq - z_im_sq) + c_re` is prepared over two add waits | difference path |
| `S_ADD_NEXTRE_CAPT` | none | `z_re_z_im + z_re_z_im` | `z_re_next` |
| `S_ADD_2X_CAPT` | none | `2*z_re*z_im + c_im` | doubled product path |
| `S_ADD_NEXTIM_CAPT` | none | none | `z_im_next` |

The single-context worker is latency-tolerant rather than throughput-pipelined across pixels: a worker completes one pixel iteration sequence before advancing that worker's pixel. It remains in the tree as the `WORKER_CONTEXTS=1` regression path.

### 8.5 Two-Context Worker

The default worker is `mandelbrot_core_worker_2ctx.v`. It keeps the same external row-worker contract but maintains two active pixel contexts internally. Each worker still has exactly one FP64 multiplier and one FP64 adder, so the optimization does not increase worker count or FP unit count. It recovers idle FP issue slots by letting one pixel make progress while the other is waiting for an FP result.

Per-context state includes:

| State | Purpose |
|---|---|
| `c_c_re`, `c_c_im` | Pixel coordinate. |
| `c_z_re`, `c_z_im` | Current complex value. |
| `c_z_re_sq`, `c_z_im_sq`, `c_z_re_z_im` | Delayed FP intermediates. |
| `c_iter` | Iteration count. |
| `c_col` | Worker-local ordered commit column. |
| `c_state` | Per-context micro-state. |
| `c_result_valid`, `c_result_iter` | Completed pixel result waiting for ordered commit. |

The shared FP units use operation and context tag delay lines:

| Tag path | Latency | Purpose |
|---|---:|---|
| `mul_op_pipe`, `mul_ctx_pipe` | 6 cycles | Route `fp_mul` output back to the correct context and destination. |
| `add_op_pipe`, `add_ctx_pipe` | 7 cycles | Route `fp_add` output back to the correct context and destination. |

The tag latency is not the old single-context `PIPE_WAIT=10`. It is the actual back-to-back FP latency plus the worker-side operand register handoff. Using the old guard latency caused adjacent context results to be captured under the wrong tag during continuous issue; the board symptom was a repeatable 32x24 mismatch concentrated on odd columns. The fixed latencies are `MUL_LAT=6` and `ADD_LAT=7`.

Conceptually, the two-context worker keeps two pixels, written here as `z1` and `z2`, moving through the same shared FP pipeline. The table below is illustrative rather than a cycle-exact trace; real issue depends on each context's ready state and on whether the shared multiplier or adder is free.

| Step | Shared multiplier issue | Shared adder issue | `z1` context stage | `z2` context stage |
|---:|---|---|---|---|
| 1 | `z1_re * z1_re` | none | Issue real square. | Waiting or just launched. |
| 2 | `z2_re * z2_re` | none | Waiting for `z1_re_sq`. | Issue real square. |
| 3 | `z1_im * z1_im` | none | Issue imaginary square after `z1_re_sq` returns. | Waiting for `z2_re_sq`. |
| 4 | `z2_im * z2_im` | none | Waiting for `z1_im_sq`. | Issue imaginary square after `z2_re_sq` returns. |
| 5 | `z1_re * z1_im` | `z1_re_sq + z1_im_sq` | Issue cross product and magnitude sum. | Waiting for `z2_im_sq`. |
| 6 | `z2_re * z2_im` | `z2_re_sq + z2_im_sq` | Waiting for `z1_zrzi` and `z1_mag`. | Issue cross product and magnitude sum. |
| 7 | none or next ready multiply | `z1_re_sq - z1_im_sq` | If not escaped, issue real difference. | Waiting for `z2_zrzi` and `z2_mag`. |
| 8 | none or next ready multiply | `z2_re_sq - z2_im_sq` | Waiting for `z1_tmp_re`. | If not escaped, issue real difference. |
| 9 | none or next ready multiply | `z1_tmp_re + z1_c_re` | Issue next real part. | Waiting for `z2_tmp_re`. |
| 10 | none or next ready multiply | `z2_tmp_re + z2_c_re` | Waiting for `z1_next_re`. | Issue next real part. |
| 11 | none or next ready multiply | `z1_zrzi + z1_zrzi` | Issue doubled cross product. | Waiting for `z2_next_re`. |
| 12 | none or next ready multiply | `z2_zrzi + z2_zrzi` | Waiting for `z1_2x`. | Issue doubled cross product. |
| 13 | none or next ready multiply | `z1_2x + z1_c_im` | Issue next imaginary part and later increment `z1_iter`. | Waiting for `z2_2x`. |
| 14 | none or next ready multiply | `z2_2x + z2_c_im` | Either starts next iteration or waits to commit. | Issue next imaginary part and later increment `z2_iter`. |

The important property is not strict alternation. The arbiter can issue whichever context is ready, but every issued operation carries a context tag. When the delayed FP result returns, the tag writes it back to either the `z1` or `z2` context state.

Two contexts can finish out of order, so the worker commits in column order. `commit_col` selects the next pixel that may be written to the per-core FIFO. If context 1 finishes before context 0, its result stays valid inside the worker until `commit_col` reaches its column. This preserves the existing per-core FIFO contract and keeps downstream raster collection unchanged.

The 2-context worker was validated with:

| Check | Result |
|---|---|
| Dynamic 32x24 value simulation | `768/768` pixels matched software reference. |
| Dynamic 64x48 stress simulation | `3072` pixels completed. |
| Board 32x24 verify | `768/768` matched. |
| Board 160x120 verify | `19200/19200` matched. |

### 8.6 Escape Check

Escape is detected with:

```text
z_re^2 + z_im^2 > 4.0
```

The implementation includes quick checks on each squared term and on their sum:

```verilog
quick_esc(z_re_sq) || quick_esc(z_im_sq) || quick_esc(add_result)
```

`quick_esc` compares the floating-point exponent against `bias + 2` and handles the exact `4.0` boundary by checking mantissa bits. Values greater than 4.0 escape. Exact 4.0 does not escape.

### 8.7 Output And Backpressure

When a pixel is complete, a worker waits until its per-core FIFO is not full, writes the 16-bit iteration count, and then advances to the next pixel. The raster merger drains per-core FIFOs into the shared output FIFO. `tx_ctrl` then drains the shared output FIFO to UART.

The top-level output FIFO has 1024 entries of 16-bit data. Each worker also has a per-core FIFO. The system is still fundamentally streaming and will backpressure workers when UART is the bottleneck or when strict raster ordering waits for an earlier row.

Output buffering and backpressure path:

```mermaid
flowchart TB
    W["worker pixel complete"] --> CFULL{"per-core FIFO full?"}
    CFULL -->|yes| WSTALL["stall worker output state"]
    CFULL -->|no| CWR["write per-core FIFO"]
    CWR --> MERGE["raster merger"]
    MERGE --> OFULL{"shared output FIFO full?"}
    OFULL -->|yes| MSTALL["stall merger"]
    OFULL -->|no| OWR["write shared output FIFO"]
    OWR --> TXC["tx_ctrl reads FIFO"]
    TXC --> UART["UART TX"]

    MSTALL -. backpressure .-> MERGE
    WSTALL -. backpressure .-> W
```

Because `queue.v` has synchronous read data, both the raster merger and `tx_ctrl` use a read-wait style: assert read enable, wait one clock for `data_out` to become valid, then consume the value.

## 9. UART Design

UART is 8N1, no parity, no hardware flow control. The current source default is `BAUD=12000000` for both `rtl/uart_rx.v`, `rtl/uart_tx.v`, and `python/mandelbrot_host.py`.

The original UART used an integer `CLOCKS_PER_BIT` divider. That worked at conservative rates but quantized every baudrate to an integer number of 100 MHz system clocks. The current design keeps `CLOCKS_PER_BIT = CLK_HZ / BAUD` as a compatibility parameter, but actual bit timing is generated by a 32-bit fractional phase accumulator:

```text
CLK_HZ = 100000000
BAUD = 12000000
ACC_WIDTH = 32
BAUD_INC = round(BAUD * 2^ACC_WIDTH / CLK_HZ)
baud_sum = baud_acc + BAUD_INC
baud_tick = carry_out(baud_sum)
```

For 12 Mbaud, one UART bit is `100 MHz / 12 MHz = 8.333...` system clocks. The fractional accumulator emits a tick pattern that alternates 8- and 9-cycle bit intervals so the long-term average baudrate is close to the requested value. This removes the large baud error that an integer divider would introduce at rates that are not exact divisors of 100 MHz.

Fractional baud generator structure:

```mermaid
flowchart LR
    CLK["100 MHz sys_clk"] --> ACC[["baud_acc register"]]
    INC["BAUD_INC<br/>round(BAUD * 2^ACC_WIDTH / CLK_HZ)"] --> ADD("33-bit add")
    ACC --> ADD
    ADD --> CARRY{"carry out?"}
    CARRY -->|yes| TICK["baud_tick"]
    CARRY -->|no| WAIT["no tick"]
    ADD --> NEXT[["baud_acc <= low ACC_WIDTH bits"]]
    NEXT --> ACC
```

`uart_rx.v` synchronizes the asynchronous RX input with two flip-flops, detects the falling start edge, preloads the accumulator to `HALF_BIT`, validates that the start bit is still low at the center of the start bit, and then samples each data bit on subsequent fractional baud ticks. A continuous-frame off-by-one bug was fixed so RX enters stop-bit checking immediately after sampling data bit 7 instead of waiting one extra bit period.

`uart_tx.v` serializes one start bit, eight data bits, and one stop bit. The same accumulator style advances the TX state machine; `transmit_avail` acts as a ready signal for `tx_ctrl`.

UART receive pipeline:

```mermaid
stateDiagram-v2
    [*] --> IDLE
    IDLE --> START_CENTER: falling edge on synchronized rx
    START_CENTER --> DATA_BITS: fractional half-bit wait confirms start bit center
    DATA_BITS --> DATA_BITS: sample bit0..bit7 on baud_tick
    DATA_BITS --> STOP_BIT: 8 data bits captured
    STOP_BIT --> BYTE_READY: stop bit interval complete
    BYTE_READY --> IDLE: rx_avail pulse
```

UART transmit pipeline:

```mermaid
stateDiagram-v2
    [*] --> IDLE
    IDLE --> START_BIT: transmit asserted and byte accepted
    START_BIT --> DATA_BITS: send 0 start bit
    DATA_BITS --> DATA_BITS: send bit0..bit7 LSB first
    DATA_BITS --> STOP_BIT: all data bits sent
    STOP_BIT --> IDLE: send 1 stop bit, transmit_avail high
```

UART integration in the response path:

```mermaid
flowchart TB
    HOST["Python host<br/>12 Mbaud"] --> RX("uart_rx<br/>fractional NCO")
    RX --> CMD["cmd_parser"]
    CMD --> CORE["4-worker FP64 core"]
    CORE --> OFIFO[["1024 x 16 output FIFO"]]
    OFIFO --> TXC["tx_ctrl<br/>legacy or tiled response"]
    TXC --> TX("uart_tx<br/>fractional NCO")
    TX --> HOST
```

The UART remains in the same 100 MHz clock domain as the parser, core, FIFOs, and TX controller. There is no UART/core CDC; the asynchronous external RX pin is handled only by the two-flop synchronizer inside `uart_rx`.

### 9.1 Baudrate Experiment Summary

The UART baudrate was systematically investigated first with the old integer divider, then with the fractional accumulator. Key findings:

| Design | Baudrate | Gate | Result | Notes |
|---|---:|---|---|---|
| Integer divider | 576000 requested, CPB `174` | 1080p six-scene baseline | Pass | Historical stable default, about `28.8k pps` UART ceiling |
| Fractional NCO | 4000000 | `160x120 --verify` and six 1080p scenes | Pass | Fast scenes near `189k pps` |
| Fractional NCO | 6000000 | `160x120 --verify` and six 1080p scenes | Pass | Fast scenes near `276k pps` |
| Fractional NCO | 8000000 | `160x120 --verify` and six 1080p scenes | Pass | Highest fully clean six-scene sweep point |
| Fractional NCO | 12000000 | `160x120 --verify` and six 1080p scenes plus reprobes | Experimental pass | First sweep had two late-frame timeouts; direct reprobes filled both cells |

The fractional-NCO design moved the practical bottleneck from UART timing precision to long-burst reliability. At 12 Mbaud, all small-frame gates passed, and 1080p reprobes completed the originally missing fast escape and Seahorse zoom cells. However, the first six-scene 12 Mbaud sweep showed late-frame timeouts within the final few hundred bytes of a 4.1 MiB payload. This points to occasional host/FT232HL/driver receive starvation or byte loss under very long bursts, not a deterministic FPGA pixel-count bug.

Detailed reports: [UART_BAUDRATE_INVESTIGATION.md](UART_BAUDRATE_INVESTIGATION.md), [UART_TIMING_ANALYSIS.md](UART_TIMING_ANALYSIS.md).

## 10. TX Controller And Large-Frame Support

`tx_ctrl.v` drains pixels from the output FIFO and serializes the host response. The original design emitted one monolithic `RK` frame per command. That was simple and efficient at lower baudrates, but at 12 Mbaud a full `1920x1080` frame is about `4.15 MiB` of uninterrupted UART payload. Early 12 Mbaud testing showed that such long bursts can occasionally lose bytes near the tail of the transfer. With only one final checksum, a single dropped byte invalidates the entire frame and leaves the host waiting for the declared payload length until timeout.

The current design keeps the same compute command format and raster-ordered pixel stream, but wraps the response in a lightweight tile protocol. The protocol has two layers:

| Layer | Implemented In | Function |
|---|---|---|
| RTL response tiling | `rtl/tx_ctrl.v` | Splits the response stream into framed `TD` packets with coordinates and per-packet checksums. |
| Host-driven display tiling | `python/mandelbrot_host.py` | Splits a large image into host-visible stripes and stitches returned subframes. |
| Hardware compute sub-tiling | `python/mandelbrot_host.py` | Splits each host tile into smaller retryable hardware commands. |

The RTL layer detects and localizes byte slips. The host-driven layer provides recovery by recomputing only the failed hardware compute tile inside the host tile.

Tile design goals:

| Goal | Design Choice |
|---|---|
| Preserve the existing compute command | A host tile is just a normal Mandelbrot command with adjusted center and smaller dimensions. |
| Preserve old host compatibility | The Python receiver accepts both legacy `RK` responses and current `RT`/`TD`/`TE` responses. |
| Keep RTL small | `tx_ctrl` packetizes the existing raster stream; it does not buffer a full frame or implement retransmission. |
| Add resynchronization points | Each `TD` packet has magic bytes, coordinates, dimensions, a bounded payload length, and a payload checksum. |
| Make failures recoverable | The host retries a compute subtile rather than losing the entire 1080p frame or a full host stripe. |
| Keep throughput close to single burst | Recommended host tiles are large horizontal stripes, not tiny rectangles. |

The architecture intentionally separates detection from recovery. The FPGA detects packet boundaries and supplies enough metadata for the host to validate each packet, but it does not participate in a bidirectional ACK/retry protocol during response streaming. This keeps the UART path simple and avoids buffering old packets in FPGA memory.

### 10.1 Response Formats

Supported response formats:

| Format | Magic | Purpose | Checksum |
|---|---|---|---|
| Legacy full frame | `RK` | Original single payload response. | One final XOR byte over all payload bytes. |
| Tiled frame header | `RT` | Announces frame dimensions before tile packets. | Magic/dimensions checked by host. |
| Tiled data packet | `TD` | Carries one rectangular pixel tile with row/column coordinates. | One XOR byte over the tile payload. |
| Tiled frame end | `TE` | Marks completion of the frame dimensions. | Magic/dimensions checked by host. |

Legacy response layout:

```text
RK rows(u16) cols(u16) payload checksum
```

Tiled response frame layout:

```text
RT rows(u16) cols(u16)
TD row(u16) col(u16) tile_rows(u16) tile_cols(u16) payload checksum
TD ...
TE rows(u16) cols(u16)
```

All multi-byte fields are little-endian. `row` and `col` in a `TD` packet are relative to the current response frame, not the original full image when host-driven tiling is active. For a host tile request of `1920x120`, the response frame dimensions are `1920x120`, and packet coordinates range inside that tile response.

Tiled data packet layout:

```text
TD row_lo row_hi col_lo col_hi tile_rows_lo tile_rows_hi tile_cols_lo tile_cols_hi payload checksum
```

The `TD` checksum is payload-only. Header fields are protected by semantic checks on the host side: magic bytes, frame dimensions, row/column bounds, expected payload length, and final frame completion. This keeps the RTL packetizer small and avoids a full bidirectional transport protocol in the FPGA.

The host parser accepts packets only when the following invariants hold:

| Check | Purpose |
|---|---|
| `RT` dimensions equal the requested response dimensions | Reject stale or corrupt frame headers. |
| `TD` rectangle is inside the response frame | Prevent out-of-bounds writes into the host image buffer. |
| `TD` payload length equals `tile_rows * tile_cols * 2` | Detect truncated or shifted packet payloads. |
| `TD` payload checksum matches | Detect byte corruption or byte slip inside the packet payload. |
| Every expected pixel is filled before `TE` | Detect missing packets or premature frame end. |
| `TE` dimensions match `RT` | Reject stale or corrupt end markers. |

The current host does not require `TD` packets to arrive out of order because the RTL emits them in raster order. The bounds and filled-pixel checks are still useful because they make future coordinate-tagged output easier to validate.

### 10.2 RTL Tile Generation

The current source defaults are:

| Parameter | Default | Meaning |
|---|---:|---|
| `CFG_RESPONSE_TILE_COLS` | `64` | Maximum RTL response packet width. |
| `CFG_RESPONSE_TILE_GAP_CYCLES` | `1000` | Inter-packet idle gap at 100 MHz, about 10 us. |

`CFG_RESPONSE_TILE_COLS` controls the width of each RTL `TD` packet. The packet height is determined by the stream position and remaining pixels; in the current implementation packets advance through the response in raster order and do not reorder pixels. The output FIFO still supplies one 16-bit pixel at a time, so the packetizer is a wrapper around the same low-byte/high-byte UART serialization used by the legacy response.

The RTL response tile is not the same thing as a host compute tile:

| Concept | Controlled By | Example | Purpose |
|---|---|---|---|
| RTL response tile | `CFG_RESPONSE_TILE_COLS` in `rtl/config.vh` | `64` columns | Adds packet boundaries and checksums inside one FPGA response. |
| Host tile | `--tile-width`, `--tile-height` | full width x 120 rows | Defines the display/logging stripe and final image copy region. |
| Hardware compute tile | `--compute-tile-width`, `--compute-tile-height` | `512x120` | Creates retryable hardware commands inside each host tile. |

A single hardware compute tile can therefore produce many RTL `TD` packets. For example, a `512x120` compute tile with `CFG_RESPONSE_TILE_COLS=64` produces 960 64-column response packets inside one response frame. A `1920x120` host tile is assembled from four such compute commands by default.

Host-driven tiling is now the default behavior in `python/mandelbrot_host.py`. If the user does not pass `--tile-width` or `--tile-height`, the host selects a full-width stripe with a default height of 120 rows. If the user does not pass `--compute-tile-width` or `--compute-tile-height`, each host stripe is split into `512x120` hardware compute tiles. Tile receive uses a shorter per-read timeout, `--tile-read-timeout 30`, so a byte slip can fail and retry a compute subtile without waiting for the global serial timeout. The old single-command path is still available through `--full-frame` for regression and controlled experiments.

`CFG_RESPONSE_TILE_GAP_CYCLES` inserts a small idle gap between response packets. This gives the host/USB serial stack short scheduling windows without adding a large throughput penalty. The current default of `1000` cycles is about 10 us at 100 MHz.

For a response frame with `rows` and `cols`, the approximate packet count is:

```text
td_packets = rows * ceil(cols / CFG_RESPONSE_TILE_COLS)
```

With the current `CFG_RESPONSE_TILE_COLS=64`, one default `512x120` hardware compute tile produces:

```text
120 * ceil(512 / 64) = 120 * 8 = 960 TD packets
```

A `1920x120` host stripe is assembled from four `512x120` compute responses by default, so the host stripe aggregate is 3840 `TD` packets. The payload size is unchanged at two bytes per pixel. The framing overhead for each `TD` packet is 2 magic bytes, 8 header bytes, and 1 checksum byte, so `11` bytes per packet. One default `512x120` compute response therefore has:

```text
payload_bytes = 512 * 120 * 2 = 122880
td_overhead   = 960 * 11 = 10560
gap_time      = 960 * 1000 / 100 MHz = 9.6 ms
```

This overhead is small compared with the payload time at 12 Mbaud, but it is not zero. Increasing `CFG_RESPONSE_TILE_COLS` would reduce packet count and host parsing overhead, at the cost of larger corruption windows and possibly different timing/resource behavior in `tx_ctrl`.

### 10.3 Reliability Boundary

Packetized response framing by itself detects checksum errors earlier, but it does not let the FPGA retransmit one packet. During response streaming the protocol is still effectively one-way: the host is receiving and the FPGA is transmitting. If a `TD` packet checksum fails, the host cannot ask the current `tx_ctrl` instance to resend only that packet.

Recovery therefore happens at the hardware compute-tile boundary. The host records the failed compute-tile coordinates, discards that subframe, drains stale serial bytes until the link is quiet, resets the input buffer, sends the soft reset command, and sends the same compute tile command again. This recovers from byte slips while keeping RTL retransmission complexity out of the FPGA.

The soft reset command is the eight-byte UART sequence `RST!RST!`. `cmd_parser` recognizes it in any parser state and pulses a system reset long enough to clear the command parser, compute engine, per-core FIFOs, output FIFO, and `tx_ctrl`. The host sends it automatically after a failed compute tile attempt unless `--no-soft-reset-on-retry` is used. It can also be sent manually with `python python\mandelbrot_host.py --port COM6 --soft-reset`.

Host retry sequence:

```mermaid
flowchart TB
    CMD["Send tile command"] --> RX["Receive RT/TD/TE response"]
    RX --> CHECK{"Frame complete<br/>and checks pass?"}
    CHECK -->|yes| COPY["Copy tile pixels<br/>into full-frame buffer"]
    CHECK -->|no| DRAIN["Drain serial until quiet"]
    DRAIN --> RESET["Soft reset FPGA<br/>reset input buffer<br/>increment retry count"]
    RESET --> RETRY{"Retries left?"}
    RETRY -->|yes| CMD
    RETRY -->|no| FAIL["Fail frame"]
```

The retry is still coarser than one `TD` packet. A bad `TD` packet causes the current hardware compute tile to be recomputed, because the FPGA has already streamed past the failed packet and has no retained copy to resend. With the default `1920x120` host stripe and `512x120` compute tile, one retry recomputes one quarter of the host stripe rather than the whole stripe or the entire 1080p frame.

If bytes stop arriving in the middle of a `TD` payload, the receiver cannot know the packet is incomplete until the serial read returns short. The tiled path therefore overrides the serial timeout during each tile request with `--tile-read-timeout`, currently 30 seconds by default. This turns the apparent hang into a bounded wait followed by drain and retry.

Current limitations:

| Missing Feature | Effect |
|---|---|
| No packet sequence ID | The host detects bad framing/checksum but cannot explicitly report missing packet numbers. |
| No request ID | Late bytes from an old failed request are handled by drain/quiet timing, not by an explicit ID check. |
| No FPGA-side retransmission | A failed packet requires recomputing the current hardware compute tile. |
| Payload-only checksum | Header corruption is caught by semantic checks, not by a header CRC. |

These are deliberate tradeoffs for the current UART implementation. The design gives practical recovery at 12 Mbaud without converting the FPGA UART path into a full reliable transport stack.

Important reliability boundaries:

| Boundary | Current Behavior |
|---|---|
| Packet corruption inside one `TD` | Detected by payload checksum; host retries the compute tile. |
| Header corruption | Detected by magic/dimension/bounds/length checks; host retries the compute tile. |
| Lost packet | Detected by missing filled pixels or unexpected `TE`; host retries the compute tile. |
| Late bytes after a failed tile | Mitigated by drain-until-quiet, soft reset, and input-buffer reset. |
| Duplicate or stale valid-looking tile | Not explicitly protected without request IDs; currently mitigated by serial drain and strict command sequencing. |
| FPGA compute error with valid transport | Not corrected by the tile protocol; use `--verify` or targeted simulation for numerical validation. |

### 10.4 Host-Driven Tile Geometry

Host-driven tiling builds reliability above this packetized response format. Instead of requesting a full 1920x1080 frame in one command, the host builds large host-visible stripes and then sends smaller hardware compute commands inside each stripe. If a compute response fails checksum or framing, the host drains the serial stream, sends soft reset, and retries that compute tile. The recommended 1080p host stripe is `1920x120`, producing nine host stripes per frame; with the default `512x120` compute tile, this becomes 36 hardware compute requests per frame.

Tile center calculation preserves the same integer-center coordinate convention as the full-frame renderer. For a full image with center `(center_re, center_im)`, pixel step `step`, full dimensions `width x height`, and a compute tile at `(cx0, cy0)` with dimensions `cw x ch`, the host computes:

```python
full_half_w = (width - 1) >> 1
full_half_h = (height - 1) >> 1
subtile_half_w = (cw - 1) >> 1
subtile_half_h = (ch - 1) >> 1
subtile_center_re = center_re + (cx0 + subtile_half_w - full_half_w) * step
subtile_center_im = center_im + (full_half_h - (cy0 + subtile_half_h)) * step
```

This makes each compute command generate exactly the same pixel coordinates as the corresponding rectangle in a monolithic full-frame command. After receiving a compute response, the host copies each returned row into the final image buffer:

```python
dst = (cy0 + dy) * width + cx0
pixels[dst:dst + cw] = subtile_pixels[src:src + cw]
```

The FPGA is intentionally unaware of the full-frame assembly. It only receives ordinary Mandelbrot commands for smaller rectangles.

This choice has an important consequence: all full-frame coordinate logic remains in software. The FPGA only sees a tile-local frame with its own `rows`, `cols`, `center`, and `step`. That is why `TD` coordinates are relative to the tile response and why the host copy step applies `(x0, y0)` when writing into the final image buffer.

The geometry formula preserves the RTL integer-center convention for both odd and even compute-tile dimensions. It uses truncated half dimensions, matching RTL expressions such as:

```verilog
half_w = (cols - 1) >> 1;
```

This avoids off-by-one seams between adjacent compute tiles.

### 10.5 Tile Size Tradeoffs

Tile size is a tradeoff between recovery granularity and fixed overhead. The historical measurements below vary host tile size with one hardware command per host tile; the current host keeps the same host-tile concept but adds a smaller compute-tile retry unit inside each host tile.

| Tile Shape | Host Tiles Per 1080p Frame | Behavior |
|---:|---:|---|
| `80x60` | 432 | Fine retry granularity, but Python/serial/protocol overhead dominates. |
| `320x120` | 54 | Much lower overhead, but still many commands; useful as a recovery stress point. |
| `960x120` | 18 | High-throughput range with moderate retry unit. |
| `1920x120` | 9 | Current recommended default; strong 30-run stability data. |
| `1920x240` | 5 | Fastest one-run matrix result, but larger retry unit and less repeat data. |

The one-run tile-size matrix across the six standard 1080p scenes produced:

| Scene | `80x60` | `320x120` | `960x120` | `1920x120` | `1920x240` |
|---|---:|---:|---:|---:|---:|
| Fast escape @128 | `13.433s` | `6.992s` | `5.597s` | `4.845s` | `4.759s` |
| Standard @64 | `12.977s` | `6.491s` | `4.641s` | `5.450s` | `4.355s` |
| Seahorse zoom @512 | `24.975s` | `18.605s` | `17.231s` | `17.085s` | `16.951s` |
| Deep tendrils @8192 | `40.828s` | `33.966s` | `33.355s` | `37.524s` | `33.077s` |
| Deep mini-brot @8192 | `91.297s` | `84.214s` | `83.505s` | `83.280s` | `83.179s` |
| Deep Seahorse @1024 | `44.215s` | `37.236s` | `36.534s` | `36.340s` | `36.243s` |

The matrix confirms the expected regimes. Small tiles are dominated by command count and host overhead. Large horizontal stripes approach single-burst performance while preserving a retry boundary. Compute-bound scenes are less sensitive to tile size because worker latency dominates; UART-bound scenes benefit most from larger tiles.

Tile-size selection can be estimated with two competing terms:

```text
frame_time ~= compute_time(tile_shape)
           + uart_payload_time(full_frame_pixels)
           + td_packet_overhead_time(tile_shape)
           + host_command_overhead * host_tile_count
           + retry_cost
```

The UART payload term is nearly constant for a fixed full-frame size. Small tiles increase command/serial overhead. Larger tiles reduce fixed overhead but increase `retry_cost` because more pixels must be recomputed after one checksum failure. The recommended current split keeps a large `1920x120` host stripe for simple image assembly and progress reporting, but uses `512x120` compute tiles so a retry recomputes about one quarter of the stripe.

### 10.6 Large Logical Images Above 4096 Rows

The default dynamic scheduler records row ownership for `DYNAMIC_OWNER_DEPTH=4096` rows per hardware command. A single full-frame command taller than 4096 rows can therefore stall when the raster collector reaches an unrecorded row. Default host tiling changes the practical limit: each compute tile is a separate hardware command with its own local `rows` field, so the owner-depth limit applies to `compute_tile_height`, not to the logical full-frame height.

Examples:

| Logical image | Default host tile behavior | Owner-depth status |
|---|---|---|
| `4096x4096` | 35 host stripes of up to 120 rows, each split into compute tiles | Safe; each hardware command is 120 rows except the tail. |
| `16384x16384` | Full-width stripes if width fits one hardware command | Safe for row ownership; very large host memory and runtime. |
| `65536x65536` | Cannot use one full-width tile because hardware `cols` is 16-bit | Must use both horizontal and vertical tiling, and host memory becomes impractical. |

The hardware command format uses 16-bit `rows` and `cols`, so each individual hardware request must have `tile_width <= 65535` and `tile_height <= 65535`; the current default bitstream further constrains practical `tile_height <= 4096` unless rebuilt. Logical full images larger than 65535 in width or height can be represented by host tiling only if the host splits them so every hardware command stays inside those per-command limits.

The current Python host still assembles the complete final image in memory before rendering. Very large logical frames therefore hit host RAM, PNG rendering time, and optional software verification time long before they become comfortable workflows. For example, a `16384x16384` final pixel buffer contains 268435456 iteration values; as a Python list this is far larger than the raw 512 MiB `uint16` payload. A `65536x65536` frame is about 8 GiB even as raw `uint16`, and much larger as Python objects, so it requires a streaming/tiled image writer rather than the current full-buffer renderer.

Use `--full-frame` only to test the older monolithic path. In that mode, images taller than 4096 rows still require a larger `DYNAMIC_OWNER_DEPTH` bitstream or a compatible static/streaming design.

The response size is based on:

```verilog
wire [31:0] total_pixels = {16'd0, rows} * {16'd0, cols};
wire [31:0] total_bytes  = total_pixels * 2;
```

The explicit 32-bit cast is important. Without it, Verilog computes `rows * cols` using the operand widths, producing a 16-bit product before extension. That caused images larger than 65535 pixels to fail. The fix was validated with `320x240` and `1920x1080` frames.

`queue.v` has synchronous read behavior. `tx_ctrl` therefore includes `S_READ_WAIT` between asserting `fifo_rd` and using `fifo_data`. This prevents pixel misalignment.

TX controller response pipeline:

```mermaid
flowchart TB
    START["tx_start rows/cols"] --> H0["Send header byte 0<br/>0x52"]
    H0 --> H1["Send header byte 1<br/>0x4B"]
    H1 --> HR["Send rows LE"]
    HR --> HC["Send cols LE"]
    HC --> PIXWAIT{"pixels_sent < rows*cols?"}
    PIXWAIT -->|yes| RD[Assert fifo_rd]
    RD --> RWAIT["S_READ_WAIT<br/>synchronous FIFO data valid"]
    RWAIT --> LO["Send pixel low byte<br/>checksum xor"]
    LO --> HI["Send pixel high byte<br/>checksum xor"]
    HI --> PIXWAIT
    PIXWAIT -->|no| CS[Send checksum]
    CS --> DONE[Return idle]
```

The legacy pipeline above is still the conceptual data path: read pixels, serialize low/high bytes, and compute an XOR checksum. The current tiled implementation wraps the same pixel stream in repeated `TD` packets and emits `RT`/`TE` frame markers.

Tiled response pipeline:

```mermaid
flowchart TB
    START["tx_start rows/cols"] --> RT["Send RT frame header"]
    RT --> NEXT{"More pixels?"}
    NEXT -->|yes| TDH["Send TD tile header<br/>row/col/tile size"]
    TDH --> RD["Read FIFO pixels"]
    RD --> PAYLOAD["Send tile payload<br/>update XOR checksum"]
    PAYLOAD --> TCS["Send tile checksum"]
    TCS --> GAP["Optional inter-packet gap"]
    GAP --> NEXT
    NEXT -->|no| TE["Send TE frame end"]
    TE --> DONE["Return idle"]
```

## 11. Host Software Architecture

Host code is in `python/mandelbrot_host.py`.

Responsibilities:

| Component | Responsibility |
|---|---|
| CLI parser | Accept center, step, max iteration, dimensions, output, mode, port, timeout, verify flag, tiling, soft reset, and quiet progress options. |
| FP encoding | Pack FP64 with Python `struct.pack('<d')`; pack FP128 manually for experimental mode. |
| Command builder | Build little-endian command packet and XOR checksum. |
| Serial transport | Open `COM6` by default at 12000000 baud. |
| Response receiver | Read legacy `RK` or tiled `RT`/`TD`/`TE` responses, validate checksums, and convert to uint16 pixels. |
| Host-driven tiling | Default host stripes plus `--compute-tile-width`, `--compute-tile-height`, and `--tile-retries` split a frame into retryable hardware compute tiles. |
| Soft reset | `--soft-reset` sends `RST!RST!`; failed compute-tile attempts send it automatically unless disabled. |
| Quiet progress | `--quiet` shows a single-line progress bar: `(n / total compute tile)` and `(m / total host tile)`. |
| Renderer | Convert iteration counts to PNG or text output. |
| Software reference | Optional `--verify` computes a Python Mandelbrot image matching RTL coordinate rules. |
| Timing | Print FPGA elapsed, pixels/s, render elapsed, software elapsed, and total elapsed. |

Typical command:

```bash
python python\mandelbrot_host.py --width 1920 --height 1080 --max-iter 512 --center -0.743643887037151 0.13182590420533 --step 0.000005 --timeout 1800 --output python\hw_1080p_zoom.png
```

Recommended high-baud 1080p host-tiled command:

```bash
python python\mandelbrot_host.py --port COM6 --width 1920 --height 1080 --max-iter 128 --center 1.0 1.0 --step 0.002 --timeout 600 --verify --tile-width 1920 --tile-height 120 --compute-tile-width 512 --compute-tile-height 120 --tile-retries 3 --quiet --output python\hw_1080p_hosttile_fast_escape.png
```

The tile arguments are optional because the host now enables stripe tiling and compute sub-tiling by default. Use `--full-frame` to disable host tiling for regression tests or controlled single-burst experiments.

### 11.1 Host-Tiled 12 Mbaud Stability

The host-tiled mode was stress-tested with the six standard 1080p scenes, five repeated runs per scene. The first pass lost the USB serial device after 23 completed frame runs; after reconnecting `COM6`, the stale failed/open-port logs were rerun with `--resume`, completing the full 30-run sweep:

| Scene | Completed runs | Tile retries | Mean FPGA s | Min s | Max s | Stddev s | CV | Mean pps |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| Fast escape @128 | `5/5` | `0` | `4.844` | `4.843` | `4.845` | `0.001` | `0.02%` | `428068.64` |
| Standard @64 | `5/5` | `0` | `4.450` | `4.449` | `4.451` | `0.001` | `0.02%` | `466030.04` |
| Seahorse zoom @512 | `5/5` | `1` | `17.598` | `17.081` | `19.657` | `1.151` | `6.54%` | `118207.86` |
| Deep tendrils @8192 | `5/5` | `1` | `34.026` | `33.186` | `37.377` | `1.873` | `5.51%` | `61080.26` |
| Deep mini-brot @8192 | `5/5` | `0` | `83.281` | `83.280` | `83.282` | `0.001` | `0.00%` | `24898.89` |
| Deep Seahorse @1024 | `5/5` | `0` | `36.343` | `36.341` | `36.345` | `0.002` | `0.00%` | `57056.36` |

The two retry events were recovered by recomputing one 1920x120 host tile in the earlier host-tile-only implementation. The current host reduces this retry unit further by splitting each host tile into smaller compute tiles, defaulting to `512x120`. Without host-driven tiling, an equivalent byte slip in a monolithic 4 MiB response would normally invalidate the entire frame. Exact HW/SW match is not used as the transport pass criterion for deep scenes because FP64 boundary differences are already documented separately.

### 11.2 Software Reference Matching RTL

The reference model uses the same coordinate convention as the RTL:

```python
half_w = (width - 1) >> 1
half_h = (height - 1) >> 1
re_start = center_re - half_w * step
im_start = center_im + half_h * step
```

This is different from a renderer that centers exactly at `width / 2.0` and `height / 2.0`. The integer-center convention is required for bit-for-bit comparison with the RTL pixel grid.

## 12. Verification Strategy

Verification uses several layers.

### 12.1 Unit Simulation

`sim/tb_fp.v` tests FP add/multiply cases. Coverage includes:

| Category | Examples |
|---|---|
| Zero handling | `0 + x`, `0 * x` |
| Positive multiplication | `2 * 3`, `2.5 * 2.5`, coordinate offset cases |
| Same-sign addition | `1.5 + 3.5` |
| Opposite-sign addition | `-0.75 + 0.1`, `0.5625 + -0.01` |
| Negative same-sign addition | `-0.075 + -0.075` |

Run:

```bash
vivado -mode batch -source sim_fp.tcl
```

### 12.2 Core Simulation

`sim/tb_core.v` runs the Mandelbrot core against a software reference embedded in the testbench. It covers individual points, a small grid, and a full-size first-pixel regression.

Run:

```bash
vivado -mode batch -source sim_core.tcl
```

Expected pass marker:

```text
=== CORE TEST PASS ===
```

### 12.3 Multicore Simulation

`sim/tb_multicore.v` instantiates `mandelbrot_multicore` with four workers and checks that the default static merged output stream matches row-major software reference order. `sim/tb_multicore_dynamic.v` runs the same raster-order check with `SCHED_MODE=1` dynamic idle-core row scheduling.

Run:

```bash
vivado -mode batch -source sim_multicore.tcl
vivado -mode batch -source sim_multicore_dynamic.tcl
```

Expected pass marker:

```text
=== MULTICORE TEST PASS: 192 pixels ===
=== DYNAMIC MULTICORE TEST PASS: 192 pixels ===
```

### 12.4 Response Packetizer And Soft Reset Simulation

Focused response simulations validate tiled response framing independent of the full compute pipeline:

```bash
vivado -mode batch -source sim_tx_ctrl_tiled.tcl
vivado -mode batch -source sim_tx_ctrl_host_tiled_4096.tcl
vivado -mode batch -source sim_cmd_parser_soft_reset.tcl
```

Expected pass markers:

```text
=== TX CTRL TILED TEST PASS: td=7680 pixels=491520 bytes=1067532 ===
=== HOST-TILED 4096 TEST PASS: frames=35 td=262144 pixels=16777216 bytes=36438436 ===
=== CMD PARSER SOFT RESET TEST PASS ===
```

The 4096x4096 test follows the host default geometry: 34 responses of `4096x120` and one tail response of `4096x16`. It checks `RT/TD/TE` framing, per-packet checksum, total packet count, total pixel count, and tail handling.

### 12.5 Host-Side Random Reference Testing

`python/test_random_compare.py` compares host/software reference conventions across randomized cases. This catches coordinate convention errors, checksum assumptions, and corner cases in command construction.

Example validated command:

```bash
python python/test_random_compare.py --cases 300 --seed 20260608
```

### 12.6 Hardware Smoke Tests

`python/test_esc.py` sends 1x1-like commands for obvious escape points. It verifies UART RX, command parsing, core start, escape logic, FIFO/TX, and host parsing.

Validated points include:

```text
c=(2.5,0) -> iter=1
c=(2.6,0) -> iter=1
c=(3.0,0) -> iter=1
c=(4.1,0) -> iter=1
```

### 12.7 Hardware Image Verification

For moderate images, the host can run software verification:

```bash
python python\mandelbrot_host.py --verify --width 160 --height 120 --max-iter 256 --output python\verify.png
```

Many tested cases reached `100.00%` match.

For large 1080p or very high iteration tests, `--verify` is normally skipped because Python software rendering becomes slow.

### 12.8 Large-Frame Verification

The 32-bit pixel-count fix was validated with:

```text
320x240 @ 128, center=(1.0,1.0): 76800/76800 match, 22873.22 pixels/s
1920x1080 frames: successful transfer and rendering
```

## 13. Performance Characteristics

The system has two main bottlenecks:

1. UART bandwidth for fast-escaping or low-iteration scenes.
2. FP/core compute for high-iteration zooms.

At 12 Mbaud, the practical UART payload upper bound is roughly:

```text
12000000 bits/s / 10 UART bits/byte / 2 bytes/pixel ~= 600000 pixels/s
```

Measured current fast-scene throughput is below that theoretical serial payload limit because host/driver overhead, response framing, FIFO pacing, and compute start/finish overhead still matter:

```text
1080p fast escape @128: 443288.08 pixels/s
1080p standard @64:    493434.63 pixels/s
```

Current default dynamic + 2-context high-iteration examples at 12 Mbaud:

| Case | FPGA Time | Throughput | Main limiter |
|---|---:|---:|---|
| `1080p deep tendrils @8192` | `33.393s` | `62096.41 pps` | Compute/strict raster mix |
| `1080p deep minibrot @8192` | `83.428s` | `24854.93 pps` | Compute-bound |
| `1080p deep seahorse @1024` | `36.480s` | `56842.30 pps` | Compute/strict raster mix |

Validated 1080p examples, default dynamic + 2-context worker, 12 Mbaud:

| Case | FPGA Time | Throughput |
|---|---:|---:|
| 1080p fast escape @128 | 4.678 s | 443288.08 pixels/s |
| 1080p standard @64 | 4.202 s | 493434.63 pixels/s |
| 1080p Seahorse @512, step `5e-6` | 17.280 s | 120003.12 pixels/s |
| 1080p deep tendrils @8192, step `1e-9` | 33.393 s | 62096.41 pixels/s |
| 1080p Mini-brot @8192, step `1e-9` | 83.428 s | 24854.93 pixels/s |
| 1080p deep Seahorse @1024, step `1e-8` | 36.480 s | 56842.30 pixels/s |

The higher UART rate changes which subsystem is visible. Fast escape and standard views still benefit strongly from transport bandwidth. Deep mini-brot remains compute-bound and barely changes from the old 576000 baud result. The other deep scenes now expose a mixed compute/raster-order bottleneck instead of the old UART ceiling.

## 14. Resource Use

Latest representative default dynamic + 2-context FP64 placed utilization for the current 12 Mbaud tiled-response build:

| Resource | Used | Device | Utilization |
|---|---:|---:|---:|
| Slice LUTs | 13917 | 17600 | 79.07% |
| LUT as Logic | 13641 | 17600 | 77.51% |
| LUT as Memory | 276 | 6000 | 4.60% |
| Slice Registers | 14458 | 35200 | 41.07% |
| DSP48E1 | 37 | 80 | 46.25% |
| Block RAM Tile | 9.5 | 60 | 15.83% |

Latest routed timing for the current default build:

| Build | Scheduler | Worker contexts | WNS | TNS | WHS | THS |
|---|---|---:|---:|---:|---:|---:|
| `build_fp64.tcl` | Dynamic idle-core rows + tiled response | 2 | 0.285 ns | 0.000 ns | 0.021 ns | 0.000 ns |

The design is now LUT-dense but still has DSP headroom. Historical resource and timing points are kept in `ARCHITECTURE_EVOLUTION_REPORT.md`; this section is reserved for the current default bitstream. Many practical scenes are limited by UART bandwidth or host/protocol overhead. More worker contexts or more FP units only help the most compute-bound views unless the output path also improves.

## 15. Known Limitations

| Limitation | Details |
|---|---|
| Static 4-core scheduler | Regression mode. Interleaved rows balance many views, but strict raster ordering can still wait on a slower row. |
| Dynamic row scheduler | Default mode. Reclaims row-level tail imbalance while preserving strict raster output. It gates row reuse on an empty per-core FIFO to avoid UART-backpressure deadlock. |
| Two-context worker | Hides only part of FP latency. More contexts are needed to approach full `1M+1A` issue saturation. |
| Generic 4/8-context worker experiment | Behavioral simulation passes, but the generic context-array implementation overuses LUTs on xc7z010 and is not a deployable bitstream. See `PIPELINE_BUBBLE_ANALYSIS.md`. |
| UART output | 12 Mbaud raises the payload ceiling to about 600000 pixels/s, but long multi-megabyte bursts can still show occasional host/FT232HL receive instability without packet-level retransmission. |
| FP64 precision | Very deep zooms below approximately `1e-12` to `1e-14` pixel step become precision-sensitive. |
| FP units are IEEE-like, not full IEEE-754 | No full NaN/Inf/denormal/rounding support. |
| FP128 mode exists structurally | Most validation and performance work has focused on FP64. |
| Max iteration field is 16-bit | Maximum supported `max_iter` is 65535. |

## 16. Future Improvement Directions

Most valuable next steps:

1. Add a higher-bandwidth transport, such as USB FIFO, SPI, Ethernet, or memory-mapped PS interface on Zynq.
2. Add row/tile IDs to the response protocol so the host can accept out-of-order rows or tiles.
3. Extend the current dynamic row scheduler toward dynamic tiles once the protocol can carry coordinates.
4. Add packet-level framing, sequence numbers, and retransmission or a higher-bandwidth transport if UART must remain near 12 Mbaud.
5. Add cardioid and period-2 bulb classification to skip interior pixels quickly.
6. Evaluate fixed-point arithmetic for Mandelbrot-specific deep zoom windows.
7. Validate and optimize FP128 mode for deeper zooms beyond FP64 precision comfort.

## 17. Build And Run Commands

Simulation:

```bash
vivado -mode batch -source sim_fp.tcl
vivado -mode batch -source sim_core.tcl
vivado -mode batch -source sim_multicore.tcl
vivado -mode batch -source sim_multicore_dynamic.tcl
```

Build and program:

```bash
vivado -mode batch -source build_fp64.tcl
vivado -mode batch -source program.tcl
```

Optional dynamic scheduler build:

```bash
vivado -mode batch -source build_fp64_dynamic.tcl
```

Small hardware verification:

```bash
python python\test_esc.py
python python\mandelbrot_host.py --verify --width 160 --height 120 --max-iter 256 --output python\verify_160x120.png
```

1080p render example:

```bash
python python\mandelbrot_host.py --width 1920 --height 1080 --max-iter 512 --center -0.743643887037151 0.13182590420533 --step 0.000005 --timeout 1800 --output python\hw_1080p_zoom.png
```
