# Mandelbrot FPGA Accelerator

FPGA-based Mandelbrot renderer with a UART host interface. The PC sends one image command containing center, step, maximum iteration count, and dimensions. The FPGA computes pixels in raster order and streams back one 16-bit iteration count per pixel. The host renders the result to PNG or text and can optionally compare against a software reference.

For detailed hardware architecture, pipeline scheduling, timing constraints, software design, and validation notes, see [ARCHITECTURE.md](ARCHITECTURE.md).

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
| Core effective rate | 50 MHz (`FP_CE_DIV=2`) |
| UART baudrate | 460800 |
| Host serial port default | `COM4` |
| Pixel format | `uint16` iteration count, little-endian |
| Maximum iteration count | 65535 |
| Largest validated frame | 1920x1080 |

## Repository Layout

```text
Mandelbrot/
├── rtl/                         RTL source files
│   ├── top.v                    Top-level integration
│   ├── mandelbrot_core.v        Mandelbrot FSM and FP scheduling
│   ├── fp_add.v                 Parameterized FP adder/subtractor
│   ├── fp_mul.v                 Parameterized FP multiplier
│   ├── fp_defines.vh            FP64/FP128 parameters and CE divider
│   ├── uart_rx.v                UART receiver
│   ├── uart_tx.v                UART transmitter
│   ├── cmd_parser.v             Host command parser
│   ├── tx_ctrl.v                Response stream controller
│   └── queue.v                  Small synchronous FIFO
├── constraints/
│   └── constraint.xdc           Clock, pin, and multicycle constraints
├── sim/                         Testbenches
│   ├── tb_fp.v
│   ├── tb_core.v
│   └── tb_core_count.v
├── python/                      Host and hardware test scripts
│   ├── mandelbrot_host.py
│   ├── test_esc.py
│   ├── test_points.py
│   ├── scan_points.py
│   └── test_random_compare.py
├── build_fp64.tcl               FP64 Vivado build script
├── build_fp128.tcl              FP128 Vivado build script
├── program.tcl                  JTAG programming script
├── sim_fp.tcl                   FP unit simulation script
├── sim_core.tcl                 Core simulation script
├── ARCHITECTURE.md              Detailed architecture document
└── DESIGN.md                    Original design notes
```

## System Diagram

```mermaid
flowchart LR
    PC[Host PC<br/>Python CLI] -->|UART command<br/>center, step, size, max_iter| RX[UART RX]
    RX --> Parser[cmd_parser]
    Parser -->|image parameters| Core[mandelbrot_core]
    Core -->|uint16 pixel stream| FIFO[queue<br/>128 x 16-bit]
    FIFO --> TXC[tx_ctrl]
    TXC --> TX[UART TX]
    TX -->|response header<br/>pixels<br/>checksum| PC

    Core --> MUL[fp_mul]
    Core --> ADD[fp_add]
```

## RTL Structure

```mermaid
flowchart TB
    subgraph TOP[top.v]
        CLK[sys_clk 100 MHz] --> CE[fp_ce generator<br/>FP_CE_DIV=2]
        RST[reset counter]

        URX[uart_rx<br/>460800 baud]
        UTX[uart_tx<br/>460800 baud]
        CMD[cmd_parser]
        CORE[mandelbrot_core]
        FIFO[queue<br/>128 x 16-bit]
        TXC[tx_ctrl]

        URX --> CMD
        CMD --> CORE
        CE --> CORE
        CORE --> FIFO
        FIFO --> TXC
        TXC --> UTX
    end

    subgraph FP[FP datapath inside mandelbrot_core]
        CORE --> FPM[fp_mul]
        CORE --> FPA[fp_add]
    end
```

## Mandelbrot Core Pipeline

The core uses one multiplier and one adder. It does not instantiate one FP pipeline per mathematical operation. Instead, it time-multiplexes the FP units with an FSM and waits for registered FP results.

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

The FP/core datapath only advances on `fp_ce`. Current `FP_CE_DIV=2`, so useful core operations occur every two 100 MHz cycles. Timing is constrained with multicycle paths inside `u_core`.

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

5. Confirm baudrate. The RTL and Python host currently use `460800` baud.

Relevant files:

| File | Setting |
|---|---|
| `rtl/uart_rx.v` | `CLOCKS_PER_BIT = 217` |
| `rtl/uart_tx.v` | `CLOCKS_PER_BIT = 217` |
| `python/mandelbrot_host.py` | `BAUD = 460800` |

Do not change only one side. The RTL and host must match.

## Build

### FP64 Build

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

## Program The FPGA

After building, program the board:

```bash
vivado -mode batch -source program.tcl
```

Or with the full Vivado path:

```bash
C:\Xilinx\Vivado\2020.2\bin\vivado.bat -mode batch -source program.tcl
```

`program.tcl` auto-detects the latest FP64 bitstream first, then FP128 if FP64 is not present.

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
python python\mandelbrot_host.py --width 1920 --height 1080 --max-iter 128 --center 1.0 1.0 --step 0.002 --timeout 600 --output python\hw_1080p_fast_escape.png
```

1080p standard Mandelbrot view:

```bash
python python\mandelbrot_host.py --width 1920 --height 1080 --max-iter 64 --center -0.5 0.0 --step 0.002 --timeout 1200 --output python\hw_1080p_standard.png
```

1080p deep zoom example:

```bash
python python\mandelbrot_host.py --width 1920 --height 1080 --max-iter 1024 --center -0.743643887037151 0.13182590420533 --step 0.00000001 --timeout 2400 --output python\hw_1080p_deep_seahorse.png
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
    participant Core as mandelbrot_core
    participant FIFO as queue
    participant TXC as tx_ctrl
    participant TX as uart_tx

    Host->>RX: 0x4D command packet
    RX->>Parser: bytes + rx_avail
    Parser->>Parser: checksum and field assembly
    Parser->>Core: compute_start + parameters
    Core->>Core: raster iteration using fp_mul/fp_add
    Core->>FIFO: uint16 pixel writes
    TXC->>FIFO: read pixels
    TXC->>TX: header, pixel bytes, checksum
    TX->>Host: UART response stream
    Host->>Host: parse pixels and render PNG
```

## Performance Notes

At 460800 baud, the UART ceiling is approximately:

```text
460800 bits/s / 10 bits per UART byte / 2 bytes per pixel = 23040 pixels/s
```

Measured examples:

| Case | FPGA Time | Throughput |
|---|---:|---:|
| `160x120 @ 128`, fast escape | `0.849s` | `22623.99 pps` |
| `320x240 @ 128`, fast escape | `3.358s` | `22873.22 pps` |
| `1920x1080 @ 64`, standard | `94.546s` | `21932.26 pps` |
| `1920x1080 @ 1024`, deep Seahorse | `511.486s` | `4054.07 pps` |
| `1920x1080 @ 8192`, Mini-brot | `1198.049s` | `1730.81 pps` |

Fast scenes are UART-limited. Deep zoom/high-iteration scenes are compute-limited.

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
