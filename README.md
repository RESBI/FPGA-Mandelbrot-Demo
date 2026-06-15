# Mandelbrot FPGA Accelerator

FPGA-based Mandelbrot renderer with a UART host interface. The PC sends one image command containing center, step, maximum iteration count, and dimensions. The FPGA computes pixels with a 4-worker FP64 engine, dynamically assigns rows to available workers, restores raster order, and streams one 16-bit iteration count per pixel. Each worker interleaves two pixel contexts over one shared FP64 multiplier and one shared FP64 adder. The host renders the result to PNG or text and can optionally compare against a software reference.

For detailed hardware architecture, pipeline scheduling, timing constraints, software design, and validation notes, see [ARCHITECTURE.md](doc/ARCHITECTURE.md). For the project-level evolution from the initial single-core design to the current dynamic 4-worker, 2-context implementation, see [ARCHITECTURE_EVOLUTION_REPORT.md](doc/ARCHITECTURE_EVOLUTION_REPORT.md). For the worker pipeline bubble analysis and 2-context results, see [PIPELINE_BUBBLE_ANALYSIS.md](doc/PIPELINE_BUBBLE_ANALYSIS.md).

## Demo Images

| Deep Seahorse Valley | Tendrils / Needle |
|---|---|
| ![Deep Seahorse Valley 1080p](python/hw_1080p_deep_seahorse_i1024_s1e-8.png) | ![Tendrils Needle 1080p](python/hw_1080p_deep_tendrils_i8192_s1e-9.png) |
| `python/hw_1080p_deep_seahorse_i1024_s1e-8.png` | `python/hw_1080p_deep_tendrils_i8192_s1e-9.png` |

Current validated default configuration:

| Item | Value |
|---|---:|
| FPGA target | Xilinx Zynq-7010, `xc7z010clg400-1` |
| Vivado version used | 2020.2 |
| System clock | 100 MHz |
| Floating-point mode | FP64 |
| Mandelbrot workers | 4 |
| Pixel contexts per worker | 2 |
| Default scheduler | Dynamic idle-core rows (`SCHED_MODE=1`) |
| Worker context generic | `WORKER_CONTEXTS=2` |
| FP datapath effective rate | 100 MHz (`FP_CE_DIV=1`) |
| UART baudrate | 12000000 |
| Host serial port default | `COM6` |
| Pixel format | `uint16` iteration count, little-endian |
| Maximum iteration count | 65535 |
| Largest validated frame | 1920x1080 |
| Current routed timing | `WNS=0.285ns`, `TNS=0.000ns`, `WHS=0.021ns`, `THS=0.000ns` |
| Current placed utilization | `13917` LUTs, `14458` registers, `37` DSP48E1, `9.5` BRAM tiles |

## Repository Layout

```text
Mandelbrot/
├── rtl/                         RTL source files
│   ├── top.v                    Top-level integration
│   ├── mandelbrot_multicore.v   4-worker wrapper, worker FIFOs, scheduler, collector
│   ├── mandelbrot_core_worker_2ctx.v
│   │                              Default 2-context row worker
│   ├── mandelbrot_core_worker.v Single-context row worker used by regression builds
│   ├── mandelbrot_core.v        Legacy/single-core Mandelbrot FSM and FP scheduling
│   ├── work_dispatch_static_rows.v
│   ├── work_dispatch_dynamic_rows.v
│   ├── raster_merge_static_rows.v
│   ├── raster_collect_dynamic_rows.v
│   ├── fp_add.v                 Parameterized FP adder/subtractor
│   ├── fp_mul.v                 Parameterized FP multiplier
│   ├── config.vh                Central RTL configuration defaults
│   ├── fp_defines.vh            FP64/FP128 parameters and CE divider
│   ├── uart_rx.v                UART receiver
│   ├── uart_tx.v                UART transmitter
│   ├── cmd_parser.v             Host command parser
│   ├── tx_ctrl.v                Response stream controller
│   └── queue.v                  Small synchronous FIFO
├── constraints/
│   └── constraint.xdc           Clock and pin constraints
├── sim/                         Testbenches
│   ├── tb_fp.v
│   ├── tb_core.v
│   ├── tb_multicore.v
│   ├── tb_multicore_dynamic.v
│   ├── tb_multicore_dynamic_stress.v
│   ├── tb_multicore_static.v
│   └── tb_core_count.v
├── python/                      Host and hardware test scripts
│   ├── mandelbrot_host.py
│   ├── pipeline_2ctx_model.py
│   ├── test_esc.py
│   ├── test_points.py
│   ├── scan_points.py
│   ├── test_random_compare.py
│   ├── uart_raw_probe.py
│   └── uart_listen_raw.py
├── doc/                         Architecture, design, analysis, and TODO documents
│   ├── ARCHITECTURE.md
│   ├── ARCHITECTURE_CN.md
│   ├── ARCHITECTURE_EVOLUTION_REPORT.md
│   ├── ARCHITECTURE_EVOLUTION_REPORT_CN.md
│   ├── PIPELINE_BUBBLE_ANALYSIS.md
│   ├── PIPELINE_BUBBLE_ANALYSIS_CN.md
│   ├── TILE_DESIGN.md
│   ├── TILE_DESIGN_CN.md
│   ├── TODO.md
│   └── TODO_CN.md
├── build_fp64.tcl               Default FP64 build, dynamic scheduler + 2 contexts
├── build_fp64_static.tcl        Static scheduler + 1-context regression build
├── build_fp64_dynamic.tcl       Earlier dynamic-scheduler build script
├── build_fp128.tcl              FP128 Vivado build script
├── program.tcl                  JTAG programming script
├── sim_fp.tcl                   FP unit simulation script
├── sim_core.tcl                 Core simulation script
├── sim_multicore.tcl            Default dynamic 2-context simulation script
├── sim_multicore_dynamic.tcl    Dynamic scheduler simulation script
├── sim_multicore_dynamic_stress.tcl
├── sim_multicore_static.tcl
├── sim_worker_2ctx_model.tcl
└── README.md                    Project overview
```

## System Diagram

```mermaid
flowchart LR
    PC[Host PC<br/>Python CLI] -->|UART command<br/>center, step, size, max_iter| RX[UART RX]
    RX --> Parser[cmd_parser]
    Parser -->|image parameters| Core[mandelbrot_multicore<br/>4 FP64 workers<br/>2 contexts each]
    Core -->|raster-order uint16 stream| FIFO[queue<br/>1024 x 16-bit]
    FIFO --> TXC[tx_ctrl]
    TXC --> TX[UART TX]
    TX -->|response header<br/>pixels<br/>checksum| PC

    Core --> SCHED[dynamic row dispatcher]
    SCHED --> W0[worker 0<br/>2 pixel contexts]
    SCHED --> W1[worker 1<br/>2 pixel contexts]
    SCHED --> W2[worker 2<br/>2 pixel contexts]
    SCHED --> W3[worker 3<br/>2 pixel contexts]
```

## RTL Structure

```mermaid
flowchart TB
    subgraph TOP[top.v]
        CLK[sys_clk 100 MHz] --> CE[fp_ce generator<br/>FP_CE_DIV=1]
        RST[reset counter]

        URX[uart_rx<br/>12 Mbaud fractional NCO]
        UTX[uart_tx<br/>12 Mbaud fractional NCO]
        CMD[cmd_parser]
        CORE[mandelbrot_multicore<br/>CFG_CORE_COUNT=4<br/>CFG_WORKER_CONTEXTS=2]
        FIFO[queue<br/>CFG_OUTPUT_FIFO_DEPTH x 16-bit]
        TXC[tx_ctrl]

        URX --> CMD
        CMD --> CORE
        CE --> CORE
        CORE --> FIFO
        FIFO --> TXC
        TXC --> UTX
    end

    subgraph MC[Inside mandelbrot_multicore]
        CORE --> DISP[work_dispatch_dynamic_rows<br/>default SCHED_MODE=1]
        CORE --> MERGE[raster_collect_dynamic_rows]
        DISP --> WORKERS[4 x mandelbrot_core_worker_2ctx]
        WORKERS --> CFIFO[per-core FIFOs]
        CFIFO --> MERGE
    end
```

## Scheduler Modes

`mandelbrot_multicore` supports a compile-time `SCHED_MODE` generic:

| `SCHED_MODE` | Dispatcher | Result collector | Status |
|---:|---|---|---|
| `0` | `work_dispatch_static_rows` | `raster_merge_static_rows` | Static regression mode. |
| `1` | `work_dispatch_dynamic_rows` | `raster_collect_dynamic_rows` | Default board mode. |

Static mode assigns interleaved row streams once at frame start. Dynamic mode assigns one full row at a time to the first available core, records the row owner, and drains each row in raster order from the recorded core FIFO. Both modes keep the existing host protocol unchanged.

The dynamic dispatcher also waits until the selected per-core FIFO is empty before assigning another row to that core. This guard prevents a UART-backpressure deadlock where future rows fill a core FIFO while the raster collector waits for an earlier row from the same core.

Worker implementation is selected by the `WORKER_CONTEXTS` generic:

| `WORKER_CONTEXTS` | Worker module | Status |
|---:|---|---|
| `1` | `mandelbrot_core_worker` | Single-context regression worker. |
| `2` | `mandelbrot_core_worker_2ctx` | Default worker. Interleaves two pixels over one shared multiplier and one shared adder. |
| `4` or `8` | `mandelbrot_core_worker_kctx` | Experimental simulation/synthesis path only. Behavioral simulation passes, but the generic implementation exceeds xc7z010 LUT capacity and does not produce a deployable bitstream. |

## Mandelbrot Core Pipeline

Each worker uses one multiplier and one adder. A worker does not instantiate one FP pipeline per mathematical operation. Instead, it time-multiplexes the FP units with a Mandelbrot iteration scheduler. The default worker keeps two pixel contexts live, so while one pixel is waiting for a delayed FP result, another pixel can issue useful work into the same FP pipelines.

```mermaid
stateDiagram-v2
    [*] --> S_ITER_START
    S_ITER_START --> S_MUL_ZRSQ_CAPT: issue z_re*z_re
    S_MUL_ZRSQ_CAPT --> S_MUL_ZISQ_CAPT: capture z_re_sq<br/>issue z_im*z_im
    S_MUL_ZISQ_CAPT --> S_MUL_ZRZI_CAPT: capture z_im_sq<br/>issue z_re*z_im<br/>issue z_re_sq+z_im_sq
    S_MUL_ZRZI_CAPT --> S_OUTPUT_WAIT: escaped
    S_MUL_ZRZI_CAPT --> S_SUB_RE_CAPT: issue z_re_sq-z_im_sq
    S_SUB_RE_CAPT --> S_ADD_NEXTRE_CAPT: issue diff+c_re
    S_ADD_NEXTRE_CAPT --> S_ADD_2X_CAPT: capture z_re_next<br/>issue z_re_z_im+z_re_z_im
    S_ADD_2X_CAPT --> S_ADD_NEXTIM_CAPT: issue 2*z_re*z_im+c_im
    S_ADD_NEXTIM_CAPT --> S_ITER_INC: capture z_im_next<br/>iter++
    S_ITER_INC --> S_OUTPUT_WAIT: iter >= max_iter
    S_ITER_INC --> S_MUL_ZRSQ_CAPT: next iteration
    S_OUTPUT_WAIT --> [*]
```

The FP/core datapath advances on `fp_ce`. Current FP64 builds use `FP_CE_DIV=1`, so `fp_ce` is constantly asserted and useful worker operations occur every 100 MHz cycle. The FP adder and multiplier are pipelined deeply enough that no core multicycle timing exceptions are required.

The 2-context worker uses delayed operation/context tags to route FP results back to the correct pixel context. The validated tag latencies are `MUL_LAT=6` and `ADD_LAT=7`. Results are committed in worker-local column order so the downstream per-core FIFO and raster collector still see ordered row pixels.

## Requirements

### Hardware

- Xilinx Zynq-7010 board matching the pins in `constraints/constraint.xdc`.
- JTAG connection supported by Vivado Hardware Manager.
- UART connection to the FPGA UART pins.
- 100 MHz input clock on `sys_clk`.

Current pin constraints:

| Port | Package pin | I/O standard |
|---|---|---|
| `sys_clk` | `N18` | `LVCMOS33` |
| `uart_rx` | `U20` | `LVCMOS33` |
| `uart_tx` | `V20` | `LVCMOS33` |

If your board uses different pins, edit `constraints/constraint.xdc` before building.

### Software

- Windows PowerShell or terminal.
- Xilinx Vivado 2020.2 or compatible version.
- Python 3.
- Python packages:
  - `pyserial`
  - `pillow`

Install Python dependencies:

```bash
python -m pip install pyserial pillow
```

## Initial Configuration

1. Clone or copy the repository.

2. Open a terminal in the project root:

```bash
cd C:\path\to\Mandelbrot
```

3. Confirm Vivado is installed. For example:

```text
C:\Xilinx\Vivado\2020.2\bin\vivado.bat
```

If Vivado is on your PATH, you can use `vivado`. Otherwise, call `vivado.bat` with its full path.

4. Confirm the UART port. The host defaults to `COM6`.

You can override it on every command:

```bash
python python\mandelbrot_host.py --port COM5
```

5. Confirm baudrate. The RTL and Python host currently use `12000000` baud.

Relevant files:

| File | Setting |
|---|---|
| `rtl/uart_rx.v` | `BAUD = 12000000` |
| `rtl/uart_tx.v` | `BAUD = 12000000` |
| `python/mandelbrot_host.py` | `BAUD = 12000000` |

Do not change only one side. The RTL and host must match.

## Configuration

Most RTL defaults are centralized in `rtl/config.vh`. The file uses `ifndef` guards so values can be overridden by Verilog defines in future scripts, and top-level module parameters can still be overridden by Vivado generics.

Current defaults:

| Macro | Default | Used by | Purpose |
|---|---:|---|---|
| `CFG_CLK_HZ` | `100000000` | `uart_rx`, `uart_tx` | System clock used for fractional UART timing. |
| `CFG_UART_BAUD` | `12000000` | `uart_rx`, `uart_tx` | UART baudrate. Must match `python/mandelbrot_host.py` `BAUD`. |
| `CFG_UART_ACC_WIDTH` | `32` | `uart_rx`, `uart_tx` | Fractional baud accumulator width. |
| `CFG_CORE_COUNT` | `4` | `top`, `mandelbrot_multicore` | Number of Mandelbrot workers. |
| `CFG_CORE_FIFO_DEPTH` | `4096` | `top`, `mandelbrot_multicore` | Per-core result FIFO depth. |
| `CFG_OUTPUT_FIFO_DEPTH` | `1024` | `top` | Shared output FIFO depth before `tx_ctrl`. |
| `CFG_SCHED_MODE` | `1` | `top`, `mandelbrot_multicore` | `0` static rows, `1` dynamic idle-core rows. |
| `CFG_DYNAMIC_OWNER_DEPTH` | `4096` | `top`, `mandelbrot_multicore` | Dynamic row-owner table depth. |
| `CFG_WORKER_CONTEXTS` | `2` | `top`, `mandelbrot_multicore` | `1` single-context worker, `2` default 2-context worker. |

For the default source build, edit `rtl/config.vh` and keep the Python host in sync when changing UART baud:

```verilog
`define CFG_UART_BAUD 12000000
```

```python
BAUD = 12000000
```

The existing Vivado build scripts intentionally override some top-level parameters for known build modes:

| Script | Overrides | Purpose |
|---|---|---|
| `build_fp64.tcl` | `SCHED_MODE=1 DYNAMIC_OWNER_DEPTH=4096 WORKER_CONTEXTS=2` | Default FP64 dynamic 2-context build. |
| `build_fp64_static.tcl` | `SCHED_MODE=0 DYNAMIC_OWNER_DEPTH=4096 WORKER_CONTEXTS=1` | Static scheduler, single-context regression build. |
| `build_fp64_dynamic.tcl` | `SCHED_MODE=1 DYNAMIC_OWNER_DEPTH=4096` | Earlier dynamic scheduler build. |

Those Vivado generics take precedence over the corresponding `CFG_*` defaults for `top` parameters. UART defaults currently come from `config.vh` unless a build script is extended to override them.

## Build

### FP64 Build

`build_fp64.tcl` is the default validated build. It sets:

```text
SCHED_MODE=1
DYNAMIC_OWNER_DEPTH=4096
WORKER_CONTEXTS=2
```

Using Vivado on PATH:

```bash
vivado -mode batch -source build_fp64.tcl
```

Using the known installed path:

```bash
C:\Xilinx\Vivado\2020.2\bin\vivado.bat -mode batch -source build_fp64.tcl
```

Expected output includes:

```text
BUILD SUCCESSFUL
Bitstream: ./fp64_proj/mandelbrot_fp64.runs/impl_1/top.bit
```

### FP128 Build

FP128 is structurally supported, but most validation has focused on FP64.

```bash
vivado -mode batch -source build_fp128.tcl
```

### Static Regression Build

Use this only when you intentionally want the older static scheduler and single-context worker regression path:

```bash
vivado -mode batch -source build_fp64_static.tcl
```

Expected output includes:

```text
BUILD SUCCESSFUL
Bitstream: ./fp64_static_proj/mandelbrot_fp64_static.runs/impl_1/top.bit
```

## Program The FPGA

After building, program the board:

```bash
vivado -mode batch -source program.tcl
```

Or with the full Vivado path:

```bash
C:\Xilinx\Vivado\2020.2\bin\vivado.bat -mode batch -source program.tcl
```

`program.tcl` auto-detects the default FP64 bitstream first, then FP128 if FP64 is not present. To program the static regression build, pass its bitstream explicitly:

```bash
vivado -mode batch -source program.tcl -tclargs ./fp64_static_proj/mandelbrot_fp64_static.runs/impl_1/top.bit
```

Expected output includes:

```text
Programming complete
Done
```

## Smoke Test

Run a quick escape test after programming:

```bash
python python\test_esc.py
```

Expected output:

```text
OK c=(2.5,0) -> iter=1
OK c=(2.6,0) -> iter=1
OK c=(3.0,0) -> iter=1
OK c=(4.1,0) -> iter=1
```

If this times out:

- Confirm the FPGA was programmed after the latest build.
- Confirm the correct COM port is used.
- Confirm no other process is using the serial port.
- Confirm RTL and Python baudrate match.
- Power-cycle or reprogram the board if a previous failed large transfer left the host/board out of sync.

## Render Images

Basic render:

```bash
python python\mandelbrot_host.py --width 160 --height 120 --max-iter 256 --output python\mandelbrot_160x120.png
```

Render with software verification:

```bash
python python\mandelbrot_host.py --verify --width 160 --height 120 --max-iter 256 --output python\verify_160x120.png
```

Fast 1080p transfer-heavy render:

```bash
python python\mandelbrot_host.py --width 1920 --height 1080 --max-iter 128 --center 1.0 1.0 --step 0.002 --timeout 240 --output python\hw_1080p_2ctx_fast_escape_i128_s0p002.png
```

1080p standard Mandelbrot view:

```bash
python python\mandelbrot_host.py --width 1920 --height 1080 --max-iter 64 --center -0.5 0.0 --step 0.002 --timeout 240 --output python\hw_1080p_2ctx_standard_i64_s0p002.png
```

1080p deep zoom example:

```bash
python python\mandelbrot_host.py --width 1920 --height 1080 --max-iter 1024 --center -0.743643887037151 0.13182590420533 --step 1e-8 --timeout 300 --output python\hw_1080p_deep_seahorse_i1024_s1e-8.png
```

## Host CLI Options

```text
--center RE IM       Complex center point. Default: -0.5 0.0
--step S             Pixel step size. Default: 0.005
--max-iter N         Maximum iterations, <= 65535. Default: 256
--width W            Image width. Default: 160
--height H           Image height. Default: 120
--output PATH        Output image/text path. Default: mandelbrot.png
--format FORMAT      png, bmp, or txt. Default: png
--mode MODE          fp64 or fp128. Default: fp64
--verify             Also compute software reference and compare
--port COMx          Serial port. Default: COM6
--timeout SEC        Serial timeout. Default: 180.0
--force-large-frame  Bypass host-side large-frame guards only for matching bitstreams
```

## Useful Test Commands

FP unit simulation:

```bash
vivado -mode batch -source sim_fp.tcl
```

Core simulation:

```bash
vivado -mode batch -source sim_core.tcl
```

Default dynamic 2-context multicore simulation:

```bash
vivado -mode batch -source sim_multicore.tcl
```

Dynamic scheduler simulation:

```bash
vivado -mode batch -source sim_multicore_dynamic.tcl
```

Dynamic 2-context stress simulation:

```bash
vivado -mode batch -source sim_multicore_dynamic_stress.tcl
```

Static 1-context regression simulation:

```bash
vivado -mode batch -source sim_multicore_static.tcl
```

Two-context cycle model:

```bash
vivado -mode batch -source sim_worker_2ctx_model.tcl
```

Random host/reference comparison:

```bash
python python\test_random_compare.py --cases 300 --seed 20260608
```

Single-point hardware query:

```bash
python python\test_points.py --center -0.743643887037151 0.13182590420533 --max-iter 1024
```

## Data Flow Details

```mermaid
sequenceDiagram
    participant Host as Python Host
    participant RX as uart_rx
    participant Parser as cmd_parser
    participant Core as mandelbrot_multicore
    participant FIFO as queue
    participant TXC as tx_ctrl
    participant TX as uart_tx

    Host->>RX: 0x4D command packet
    RX->>Parser: bytes + rx_avail
    Parser->>Parser: checksum and field assembly
    Parser->>Core: compute_start + parameters
    Core->>Core: dynamic dispatcher assigns one row to an available worker
    Core->>Core: each worker interleaves two pixel contexts over shared FP units
    Core->>Core: dynamic collector restores raster order
    Core->>FIFO: uint16 pixel writes
    TXC->>FIFO: read pixels
    TXC->>TX: header, pixel bytes, checksum
    TX->>Host: UART response stream
    Host->>Host: parse pixels and render PNG
```

## Performance Notes

### Current Recommended Mode: Host-Tiled 12 Mbaud

The current reliable high-baud operating mode is host-driven tiling at 12000000 baud, and the host now enables it by default. If no tile arguments are supplied, the host selects full-width host stripes with a default height of 120 rows, `--tile-retries 3`, and a per-read tile receive timeout of 30 seconds. Each host stripe is internally split into smaller hardware compute tiles; the default compute tile is `512x120`. A bad packet therefore retries only the affected compute tile instead of the whole host stripe. The recommended 1080p setting is automatic for a 1920-wide image: `--tile-width 1920 --tile-height 120 --compute-tile-width 512 --compute-tile-height 120 --tile-retries 3 --quiet`.

Example:

```bash
python python\mandelbrot_host.py --port COM6 --width 1920 --height 1080 --max-iter 128 --center 1.0 1.0 --step 0.002 --timeout 600 --verify --tile-width 1920 --tile-height 120 --compute-tile-width 512 --compute-tile-height 120 --tile-retries 3 --quiet --output python\hw_1080p_hosttile_fast_escape.png
```

Use `--full-frame` only when you intentionally want the older single-command full-frame response path for regression or controlled single-burst experiments.

If a high-baud tile loses bytes, the host may appear idle until the current serial read times out. The default tiled path uses `--tile-read-timeout 30`; lower it for faster retry detection or raise it for very slow/deep tiles.

With `--quiet`, the host now keeps a single-line progress display instead of printing every tile. The format is:

```text
[progress] (n / total compute tile) (m / total host tile) current task
```

On each failed compute tile attempt, the host drains stale UART bytes and sends a soft reset command (`RST!RST!`) unless `--no-soft-reset-on-retry` is set. The reset clears the FPGA command parser, compute engine, output FIFOs, and transmit controller, then the host recomputes only the failed compute tile. You can also issue a reset manually:

```powershell
python python\mandelbrot_host.py --port COM6 --soft-reset
```

Repeated 1080p host-tiled stability results at 12 Mbaud:

| Scene | Transport pass | Retry events | Mean FPGA Time | Min | Max | Stddev | CV | Mean Throughput | Change vs single-burst 12M |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| Fast escape @128 | `5/5` | `0` | `4.844s` | `4.843s` | `4.845s` | `0.001s` | `0.02%` | `428068.64 pps` | `0.966x` |
| Standard @64 | `5/5` | `0` | `4.450s` | `4.449s` | `4.451s` | `0.001s` | `0.02%` | `466030.04 pps` | `0.944x` |
| Seahorse zoom @512 | `5/5` | `1` | `17.598s` | `17.081s` | `19.657s` | `1.151s` | `6.54%` | `118207.86 pps` | `0.982x` |
| Deep tendrils @8192 | `5/5` | `1` | `34.026s` | `33.186s` | `37.377s` | `1.873s` | `5.51%` | `61080.26 pps` | `0.981x` |
| Deep mini-brot @8192 | `5/5` | `0` | `83.281s` | `83.280s` | `83.282s` | `0.001s` | `0.00%` | `24898.89 pps` | `1.002x` |
| Deep Seahorse @1024 | `5/5` | `0` | `36.343s` | `36.341s` | `36.345s` | `0.002s` | `0.00%` | `57056.36 pps` | `1.004x` |

`Transport pass` means the host process completed and received a full 1920x1080 frame. Exact HW/SW pixel equality is reported separately in `python/host_tile_stability_bench/host_tile_stability_results.md` because deep zoom scenes have known FP64 boundary differences. The first test pass lost the USB serial device after 23 completed frame runs; after reconnecting `COM6`, the failed/open-port logs were rerun with `--resume`, completing the full 30-run sweep.

The two retry events above were recovered by recomputing the affected 1920x120 host tile in the earlier host-tile-only flow. The current host further splits host tiles into smaller compute tiles, so a checksum mismatch typically recomputes only one compute subtile such as `512x120`. The tradeoff is more commands per frame, while compute-bound scenes remain essentially unchanged. Without retry events, measured FPGA-time variation was effectively zero across five runs.

The 4096x4096 default host-tiled path was also checked at RTL packetizer level. The simulation splits the logical image into 35 hardware responses, verifies 262144 `TD` packets and 16777216 pixels, and passes checksum and frame-boundary checks. This validates packet/count/tail behavior for the current host tiling geometry; it does not replace board-level USB-UART soak testing.

### Host Tile Size Comparison

The current tile design was also benchmarked with several host tile sizes across the same six 1080p scenes. This matrix uses one run per scene/tile-size and disables software verification so it measures FPGA/transport elapsed time. Detailed design notes and logs are in [TILE_DESIGN.md](doc/TILE_DESIGN.md), [TILE_DESIGN_CN.md](doc/TILE_DESIGN_CN.md), and `python/host_tile_size_matrix/`.

| Scene | `80x60` | `320x120` | `960x120` | `1920x120` | `1920x240` |
|---|---:|---:|---:|---:|---:|
| Fast escape @128 | `13.433s` | `6.992s` | `5.597s` | `4.845s` | `4.759s` |
| Standard @64 | `12.977s` | `6.491s` | `4.641s` | `5.450s` | `4.355s` |
| Seahorse zoom @512 | `24.975s` | `18.605s` | `17.231s` | `17.085s` | `16.951s` |
| Deep tendrils @8192 | `40.828s` | `33.966s` | `33.355s` | `37.524s` | `33.077s` |
| Deep mini-brot @8192 | `91.297s` | `84.214s` | `83.505s` | `83.280s` | `83.179s` |
| Deep Seahorse @1024 | `44.215s` | `37.236s` | `36.534s` | `36.340s` | `36.243s` |

Host tiles per 1080p frame are 432 for `80x60`, 54 for `320x120`, 18 for `960x120`, 9 for `1920x120`, and 5 for `1920x240`. `80x60` is reliable but slow because the command count exposes fixed host/protocol overhead. `960x120` and `1920x120` are the practical high-throughput range. `1920x240` was fastest in the one-run matrix, but it has a larger retry unit and less repeat data than `1920x120`, so `1920x120` remains the recommended default.

### 12 Mbaud Single-Burst Reference

At 12000000 baud, the UART payload ceiling is approximately:

```text
12000000 bits/s / 10 bits per UART byte / 2 bytes per pixel = 600000 pixels/s
```

Before host-driven tiling, the full frame was sent as one long response burst. The results below are useful as a performance reference, but long single-burst 1080p transfers at 12 Mbaud can occasionally lose bytes near the tail of the multi-megabyte UART stream.

Measured default dynamic + 2-context 1080p single-burst examples, all using FP64, four workers, `WORKER_CONTEXTS=2`, and 12000000 baud:

| Case | Center | Step | Max Iter | FPGA Time | Throughput |
|---|---|---:|---:|---:|---:|
| `1920x1080`, fast escape | `(1.0, 1.0)` | `0.002` | `128` | `4.678s` | `443288.08 pps` |
| `1920x1080`, standard | `(-0.5, 0.0)` | `0.002` | `64` | `4.202s` | `493434.63 pps` |
| `1920x1080`, Seahorse zoom | `(-0.743643887037151, 0.13182590420533)` | `5e-6` | `512` | `17.280s` | `120003.12 pps` |
| `1920x1080`, deep tendrils | `(-0.77568377, 0.13646737)` | `1e-9` | `8192` | `33.393s` | `62096.41 pps` |
| `1920x1080`, Mini-brot | `(-1.25066, 0.02012)` | `1e-9` | `8192` | `83.428s` | `24854.93 pps` |
| `1920x1080`, deep Seahorse | `(-0.743643887037151, 0.13182590420533)` | `1e-8` | `1024` | `36.480s` | `56842.30 pps` |

At 12 Mbaud, fast escape and standard views are still largely transport-bound, but their ceiling is much higher than the old 576000 baud path. Deep tendrils, deep Seahorse, and especially deep mini-brot expose compute-side limits once UART is no longer the dominant term.

### Historical 576000 Baud Baseline

Comparison against the previous 4-worker, single-context, 576000 baud baseline:

| Case | Previous 1ctx FPGA Time | Current 2ctx FPGA Time | Current Throughput | Speedup |
|---|---:|---:|---:|---:|
| Fast escape @128 | `72.736s` | `72.720s` | `28514.74 pps` | `1.000x` |
| Standard @64 | `72.735s` | `72.721s` | `28514.28 pps` | `1.000x` |
| Seahorse zoom @512 | `74.265s` | `72.790s` | `28487.54 pps` | `1.020x` |
| Deep tendrils @8192 | `93.916s` | `72.781s` | `28491.11 pps` | `1.290x` |
| Deep mini-brot @8192 | `234.231s` | `83.708s` | `24771.84 pps` | `2.798x` |
| Deep seahorse @1024 | `100.658s` | `72.776s` | `28493.04 pps` | `1.383x` |

### Baudrate Investigation

The UART now uses a 32-bit fractional baud accumulator in both RX and TX. `BAUD=12000000` is the experimental source default and has completed the six 1080p scenes after targeted reprobes. `8000000` remains the safer high-baud fallback from the first full six-scene sweep, while `576000` remains the conservative historical baseline. At 12 Mbaud, occasional byte loss was observed during multi-megabyte bursts. Host-driven tiling provides a practical retry boundary today, but long soak tests are still recommended before relying on 12 Mbaud unattended.

Detailed reports: [UART_BAUDRATE_INVESTIGATION.md](doc/UART_BAUDRATE_INVESTIGATION.md), [UART_TIMING_ANALYSIS.md](doc/UART_TIMING_ANALYSIS.md).

### HW/SW Boundary Differences

The FPGA FP64 engine uses truncation-rounding (round-toward-zero) while the Python software reference uses IEEE 754 round-to-nearest-even. This causes small pixel-level differences near the Mandelbrot set boundary where chaotic dynamics amplify sub-ULP errors across iterations. These differences are not a bug and do not affect visual image quality.

Detailed report: [FP64_BOUNDARY_DIFFERENCE_ANALYSIS.md](doc/FP64_BOUNDARY_DIFFERENCE_ANALYSIS.md).

Current default 100 MHz FP64 routed timing is signed off with no core multicycle exceptions:

| Build | Scheduler | Worker contexts | WNS | TNS | WHS | THS |
|---|---|---:|---:|---:|---:|---:|
| `build_fp64.tcl` | Dynamic idle-core rows + tiled response | 2 | `0.285ns` | `0.000ns` | `0.021ns` | `0.000ns` |

Latest placed utilization for the default build:

| Resource | Used | Device | Utilization |
|---|---:|---:|---:|
| Slice LUTs | 13917 | 17600 | 79.07% |
| LUT as Logic | 13641 | 17600 | 77.51% |
| LUT as Memory | 276 | 6000 | 4.60% |
| Slice Registers | 14458 | 35200 | 41.07% |
| DSP48E1 | 37 | 80 | 46.25% |
| Block RAM Tile | 9.5 | 60 | 15.83% |

Historical resource/timing points from earlier architecture stages are tracked in [ARCHITECTURE_EVOLUTION_REPORT.md](doc/ARCHITECTURE_EVOLUTION_REPORT.md); this table is reserved for the current default bitstream.

## Troubleshooting

### Serial Port Access Denied

Only one process can open the selected serial port at a time. Close serial terminals and avoid running multiple host scripts concurrently.

### Timeout With No Header

Common causes:

- FPGA is not programmed with the matching bitstream.
- Host baudrate differs from RTL baudrate.
- Wrong serial port.
- Board needs reprogramming after a failed test.
- `test_esc.py` or another process still owns the port.

### Bad Or Incomplete Image

Check that you are using the current `tx_ctrl.v` with explicit 32-bit pixel count:

```verilog
wire [31:0] total_pixels = {16'd0, rows} * {16'd0, cols};
```

Without this fix, frames larger than 65535 pixels can fail.

### Very Large Frames Stop Around 536862720 Bytes

The default bitstream uses dynamic row scheduling with `DYNAMIC_OWNER_DEPTH=4096`. Frames taller than 4096 rows are not supported by that default dynamic collector, because row ownership is only recorded for the first 4096 rows. A `65535x65535` command will therefore receive exactly about:

```text
4096 rows * 65535 cols * 2 bytes/pixel = 536862720 bytes
```

and then stall when raster collection reaches an unrecorded row. That frame is also impractical over UART: `65535 * 65535 * 2` pixel bytes takes roughly 2 hours at 12 Mbaud, before rendering or software verification.

Use host tiling, a smaller frame, rebuild with a larger dynamic owner table, or use a compatible static/streaming design. The host now uses tiled requests by default, so the 4096-row owner-depth limit applies to each hardware tile command rather than the logical full image. `--full-frame` restores the older single-command path, where a frame taller than 4096 rows can still stall unless the bitstream is rebuilt. `--force-large-frame` only bypasses host-side guards and should be used only when the programmed bitstream and host memory can support the request.

### Software Verification Is Slow

`--verify` computes a Python reference image. Use it for small or medium frames. Avoid it for 1080p high-iteration renders unless you intentionally want a long software comparison.

## More Documentation

For detailed hardware architecture, pipeline scheduling, timing constraints, and validation notes, see:

```text
doc/ARCHITECTURE.md
doc/ARCHITECTURE_CN.md
doc/ARCHITECTURE_EVOLUTION_REPORT.md
doc/ARCHITECTURE_EVOLUTION_REPORT_CN.md
doc/TILE_DESIGN.md
doc/TILE_DESIGN_CN.md
doc/PIPELINE_BUBBLE_ANALYSIS.md
doc/PIPELINE_BUBBLE_ANALYSIS_CN.md
doc/PERFORMANCE_100MHZ.md
doc/PERFORMANCE_100MHZ_CN.md
doc/UART_BAUDRATE_BENCHMARK.md
doc/UART_BAUDRATE_BENCHMARK_CN.md
doc/UART_BAUDRATE_INVESTIGATION.md
doc/UART_BAUDRATE_INVESTIGATION_CN.md
doc/UART_TIMING_ANALYSIS.md
doc/UART_TIMING_ANALYSIS_CN.md
doc/FP64_BOUNDARY_DIFFERENCE_ANALYSIS.md
doc/FP64_BOUNDARY_DIFFERENCE_ANALYSIS_CN.md
doc/MULTICORE_FEASIBILITY.md
doc/MULTICORE_FEASIBILITY_CN.md
doc/MULTICORE_4CORE_ARCHITECTURE.md
doc/MULTICORE_4CORE_ARCHITECTURE_CN.md
doc/DYNAMIC_IDLE_CORE_SCHEDULING.md
doc/DYNAMIC_IDLE_CORE_SCHEDULING_CN.md
doc/DESIGN.md
doc/DESIGN_CN.md
doc/TODO.md
doc/TODO_CN.md
```

## License

This project is released under the MIT License unless otherwise stated. You may use, modify, and distribute the RTL, scripts, and documentation under the terms of the MIT License.

If you redistribute this project, keep the license notice and clearly mark any substantial modifications.

## Software And LLM Assistance Disclosure

This project was developed with software and AI-assisted engineering tools, including:

- OpenCode for code editing, repository operations, and project automation.
- DeepSeek v4 Pro for AI-assisted reasoning and implementation support.
- GPT 5.5 for AI-assisted reasoning, documentation, debugging, and implementation support.

All generated code, documentation, hardware behavior, timing closure, and board-level validation remain the responsibility of the project maintainer. The included RTL and scripts should be reviewed and tested for any target board or deployment environment.
