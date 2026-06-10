# Mandelbrot FPGA Accelerator

FPGA-based Mandelbrot renderer with a UART host interface. The PC sends one image command containing center, step, maximum iteration count, and dimensions. The FPGA computes pixels with a 4-worker FP64 engine, dynamically assigns rows to available workers, restores raster order, and streams one 16-bit iteration count per pixel. Each worker interleaves two pixel contexts over one shared FP64 multiplier and one shared FP64 adder. The host renders the result to PNG or text and can optionally compare against a software reference.

For detailed hardware architecture, pipeline scheduling, timing constraints, software design, and validation notes, see [ARCHITECTURE.md](ARCHITECTURE.md). For the project-level evolution from the initial single-core design to the current dynamic 4-worker, 2-context implementation, see [ARCHITECTURE_EVOLUTION_REPORT.md](ARCHITECTURE_EVOLUTION_REPORT.md). For the worker pipeline bubble analysis and 2-context results, see [PIPELINE_BUBBLE_ANALYSIS.md](PIPELINE_BUBBLE_ANALYSIS.md).

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
| UART baudrate | 576000 |
| Host serial port default | `COM4` |
| Pixel format | `uint16` iteration count, little-endian |
| Maximum iteration count | 65535 |
| Largest validated frame | 1920x1080 |

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
├── ARCHITECTURE.md              Detailed architecture document
├── ARCHITECTURE_EVOLUTION_REPORT.md
├── PIPELINE_BUBBLE_ANALYSIS.md
├── MULTICORE_4CORE_ARCHITECTURE.md
├── PERFORMANCE_100MHZ.md
├── UART_BAUDRATE_BENCHMARK.md
├── UART_BAUDRATE_INVESTIGATION.md
├── UART_TIMING_ANALYSIS.md
├── FP64_BOUNDARY_DIFFERENCE_ANALYSIS.md
├── MULTICORE_FEASIBILITY.md
└── DESIGN.md                    Original design notes
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

        URX[uart_rx<br/>576000 baud]
        UTX[uart_tx<br/>576000 baud]
        CMD[cmd_parser]
        CORE[mandelbrot_multicore<br/>CORE_COUNT=4<br/>WORKER_CONTEXTS=2]
        FIFO[queue<br/>1024 x 16-bit]
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

4. Confirm the UART port. The host defaults to `COM4`.

You can override it on every command:

```bash
python python\mandelbrot_host.py --port COM5
```

5. Confirm baudrate. The RTL and Python host currently use `576000` baud.

Relevant files:

| File | Setting |
|---|---|
| `rtl/uart_rx.v` | `CLOCKS_PER_BIT = 174` |
| `rtl/uart_tx.v` | `CLOCKS_PER_BIT = 174` |
| `python/mandelbrot_host.py` | `BAUD = 576000` |

Do not change only one side. The RTL and host must match.

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
--port COMx          Serial port. Default: COM4
--timeout SEC        Serial timeout. Default: 180.0
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

At 576000 baud, the UART ceiling is approximately:

```text
576000 bits/s / 10 bits per UART byte / 2 bytes per pixel = 28800 pixels/s
```

Measured default dynamic + 2-context 1080p examples, all using FP64, four workers, `WORKER_CONTEXTS=2`, and 576000 baud:

| Case | Center | Step | Max Iter | FPGA Time | Throughput |
|---|---|---:|---:|---:|---:|
| `1920x1080`, fast escape | `(1.0, 1.0)` | `0.002` | `128` | `72.720s` | `28514.74 pps` |
| `1920x1080`, standard | `(-0.5, 0.0)` | `0.002` | `64` | `72.721s` | `28514.28 pps` |
| `1920x1080`, Seahorse zoom | `(-0.743643887037151, 0.13182590420533)` | `5e-6` | `512` | `72.790s` | `28487.54 pps` |
| `1920x1080`, deep tendrils | `(-0.77568377, 0.13646737)` | `1e-9` | `8192` | `72.781s` | `28491.11 pps` |
| `1920x1080`, Mini-brot | `(-1.25066, 0.02012)` | `1e-9` | `8192` | `83.708s` | `24771.84 pps` |
| `1920x1080`, deep Seahorse | `(-0.743643887037151, 0.13182590420533)` | `1e-8` | `1024` | `72.776s` | `28493.04 pps` |

Comparison against the previous 4-worker, single-context, 576000 baud baseline:

| Case | Previous 1ctx FPGA Time | Current 2ctx FPGA Time | Current Throughput | Speedup |
|---|---:|---:|---:|---:|
| Fast escape @128 | `72.736s` | `72.720s` | `28514.74 pps` | `1.000x` |
| Standard @64 | `72.735s` | `72.721s` | `28514.28 pps` | `1.000x` |
| Seahorse zoom @512 | `74.265s` | `72.790s` | `28487.54 pps` | `1.020x` |
| Deep tendrils @8192 | `93.916s` | `72.781s` | `28491.11 pps` | `1.290x` |
| Deep mini-brot @8192 | `234.231s` | `83.708s` | `24771.84 pps` | `2.798x` |
| Deep seahorse @1024 | `100.658s` | `72.776s` | `28493.04 pps` | `1.383x` |

Fast escape, standard, Seahorse zoom, deep tendrils, and deep Seahorse are now essentially UART-bound. Deep mini-brot remains compute-bound and therefore shows the largest visible improvement from the two-context worker.

### Baudrate Investigation

Higher baudrates were tested with a 100 MHz integer divider and a TX-only isolation experiment. The failure boundary above 520000 baud is primarily caused by the single-sample UART RX lacking oversampling, combined with CP2102 baud-rate quantisation error at non-standard rates. 576000 baud (a common PC standard rate) works stably and provides a ~15% throughput improvement over 500000 baud.

Detailed reports: [UART_BAUDRATE_INVESTIGATION.md](UART_BAUDRATE_INVESTIGATION.md), [UART_TIMING_ANALYSIS.md](UART_TIMING_ANALYSIS.md).

### HW/SW Boundary Differences

The FPGA FP64 engine uses truncation-rounding (round-toward-zero) while the Python software reference uses IEEE 754 round-to-nearest-even. This causes small pixel-level differences near the Mandelbrot set boundary where chaotic dynamics amplify sub-ULP errors across iterations. These differences are not a bug and do not affect visual image quality.

Detailed report: [FP64_BOUNDARY_DIFFERENCE_ANALYSIS.md](FP64_BOUNDARY_DIFFERENCE_ANALYSIS.md).

Current default 100 MHz FP64 routed timing is signed off with no core multicycle exceptions:

| Build | Scheduler | Worker contexts | WNS | TNS | WHS | THS |
|---|---|---:|---:|---:|---:|---:|
| `build_fp64.tcl` | Dynamic idle-core rows | 2 | `0.091ns` | `0.000ns` | `0.011ns` | `0.000ns` |

Latest placed utilization for the default build:

| Resource | Used | Device | Utilization |
|---|---:|---:|---:|
| Slice LUTs | 13630 | 17600 | 77.44% |
| Slice Registers | 14391 | 35200 | 40.88% |
| DSP48E1 | 38 | 80 | 47.50% |
| Block RAM Tile | 9.5 | 60 | 15.83% |

## Troubleshooting

### Serial Port Access Denied

Only one process can open `COM4` at a time. Close serial terminals and avoid running multiple host scripts concurrently.

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

### Software Verification Is Slow

`--verify` computes a Python reference image. Use it for small or medium frames. Avoid it for 1080p high-iteration renders unless you intentionally want a long software comparison.

## More Documentation

For detailed hardware architecture, pipeline scheduling, timing constraints, and validation notes, see:

```text
ARCHITECTURE.md
ARCHITECTURE_EVOLUTION_REPORT.md
PIPELINE_BUBBLE_ANALYSIS.md
PERFORMANCE_100MHZ.md
UART_BAUDRATE_BENCHMARK.md
UART_BAUDRATE_INVESTIGATION.md
UART_TIMING_ANALYSIS.md
FP64_BOUNDARY_DIFFERENCE_ANALYSIS.md
MULTICORE_FEASIBILITY.md
MULTICORE_4CORE_ARCHITECTURE.md
DYNAMIC_IDLE_CORE_SCHEDULING.md
DYNAMIC_IDLE_CORE_SCHEDULING_CN.md
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
