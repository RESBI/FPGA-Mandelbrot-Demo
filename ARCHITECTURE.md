# Mandelbrot FPGA Accelerator Architecture

## 1. Overview

This project implements a UART-controlled Mandelbrot accelerator on FPGA. The host sends one binary command describing a complete image, and the FPGA streams back one 16-bit iteration count per pixel. The current stable configuration is FP64, `FP_CE_DIV=2`, 100 MHz system clock, and 460800 baud UART.

The design is intentionally streaming-oriented. It does not store a full frame on FPGA. The compute core produces pixels in raster order, a small FIFO absorbs rate mismatch, and the transmit controller streams pixels to the host as soon as they are available.

Current validated capabilities:

| Item | Value |
|---|---:|
| System clock | 100 MHz |
| FP/core effective clock enable rate | 50 MHz (`FP_CE_DIV=2`) |
| UART baudrate | 460800 baud |
| Pixel format | `uint16`, little-endian iteration count |
| Maximum iteration count | 65535 |
| Width/height fields | 16-bit each |
| Pixel count path | 32-bit, validated above 65535 pixels |
| Largest validated image | 1920x1080 |
| Stable mode used in testing | FP64 |

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
mandelbrot_core -- fifo_wr/fifo_data --> queue(128 x 16-bit) --> tx_ctrl --> uart_tx
       |
       +-- fp_mul
       +-- fp_add
```

The main modules are:

| Module | File | Role |
|---|---|---|
| `top` | `rtl/top.v` | Instantiates clock-enable generator, UART, command parser, core, FIFO, and TX controller. |
| `uart_rx` | `rtl/uart_rx.v` | Receives 8N1 UART bytes at 460800 baud. |
| `uart_tx` | `rtl/uart_tx.v` | Sends 8N1 UART bytes at 460800 baud. |
| `cmd_parser` | `rtl/cmd_parser.v` | Parses command packet and validates XOR checksum. |
| `mandelbrot_core` | `rtl/mandelbrot_core.v` | Raster-order Mandelbrot iteration engine. |
| `fp_mul` | `rtl/fp_mul.v` | Parameterized FP multiplier. |
| `fp_add` | `rtl/fp_add.v` | Parameterized FP adder/subtractor. |
| `queue` | `rtl/queue.v` | Small synchronous FIFO for pixel buffering. |
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

The board provides a 100 MHz `sys_clk`. The design uses one actual clock domain for all logic. UART, parser, FIFO, and TX controller run every 100 MHz clock. The floating-point datapath and Mandelbrot core advance only when `fp_ce` is asserted.

`fp_ce` is generated in `top.v`:

```verilog
reg [`FP_CE_DIV-1:0] ce_counter;
wire fp_ce;
assign fp_ce = (`FP_CE_DIV == 1) ? 1'b1 : (ce_counter == `FP_CE_DIV - 1);
```

Current `rtl/fp_defines.vh` sets:

```verilog
`define FP_CE_DIV 2
```

Therefore the core and FP units see a meaningful enable every 2 system cycles, giving a 50 MHz effective datapath rate while preserving one physical 100 MHz clock domain.

### 4.1 Why Clock Enable Instead Of A Derived Clock

The design previously used derived/pseudo clocks in the UART area and later moved to a single-clock style. The current single-clock + enable approach avoids clock-domain crossing issues and simplifies timing closure.

Benefits:

| Benefit | Explanation |
|---|---|
| No generated clock tree | All registers are clocked by `sys_clk`. |
| No CDC between core and UART | FIFO and handshake signals stay in one clock domain. |
| Easier reset and debug | One synchronous timing model. |
| STA remains explicit | Multicycle constraints describe CE-gated core paths. |

### 4.2 Multicycle Constraints

Vivado timing analysis does not automatically infer that core registers only launch/capture useful data every `FP_CE_DIV` cycles. The constraints explicitly apply multicycle timing to sequential cells under `u_core`:

```tcl
set fp_ce_regs [get_cells -hier -filter {NAME =~ *u_core/* && IS_SEQUENTIAL}]
set_multicycle_path 2 -setup -from $fp_ce_regs -to $fp_ce_regs
set_multicycle_path 1 -hold  -from $fp_ce_regs -to $fp_ce_regs
```

The UART and top-level control logic are not relaxed and still meet normal 100 MHz timing.

Current routed timing after large-frame fix:

| Metric | Value |
|---|---:|
| WNS | 2.619 ns |
| TNS | 0.000 ns |
| WHS | 0.023 ns |
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

The FPGA and software reference are compared against the implemented RTL behavior, not a full IEEE-754 formal model.

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

The multiplier includes input and DSP-product registers to improve timing. The multiplication is annotated with:

```verilog
(* mult_style = "pipe_block" *)
```

This encourages DSP-based implementation. The Zynq-7010 implementation uses multiple DSP48E1s for FP64 mantissa multiplication.

### 6.1 Multiplier Pipeline Behavior

The core does not assume a single-cycle FP unit. Instead, it issues an operation and waits `PIPE_WAIT` CE cycles before capturing the result. Current `mandelbrot_core.v` uses:

```verilog
localparam PIPE_WAIT = 6;
```

This wait value is conservative relative to the internal FP pipeline and has been validated in simulation and hardware.

## 7. Floating-Point Adder Pipeline

`fp_add.v` implements both addition and subtraction. Subtraction is performed by flipping the sign of operand B before entering the adder:

```verilog
wire [`FP_WIDTH-1:0] add_b_eff = add_neg ? {~add_b[`FP_SIGN_IDX], add_b[`FP_EXP_HI:0]} : add_b;
```

Algorithm summary:

1. Register inputs on `ce`.
2. Decode signs, exponents, and mantissas.
3. Compare magnitudes and align the smaller mantissa by exponent difference.
4. Add or subtract aligned mantissas depending on signs.
5. Register intermediate mantissa/sign/exponent information.
6. Normalize the mantissa.
7. Adjust exponent.
8. Register output.

Important fixes already made in this design:

| Issue | Fix |
|---|---|
| Wrong same-sign normalization slice | Corrected carry/no-carry mantissa extraction. |
| Negative add/sub mismatch | Added tests and fixed sign/magnitude handling. |
| Input timing pressure | Added input registers. |
| Output normalization timing | Added output-side normalization register. |

## 8. Mandelbrot Core Architecture

`mandelbrot_core.v` computes pixels in raster order. For each pixel, it iterates:

```text
z_{n+1} = z_n^2 + c

z_re_next = z_re^2 - z_im^2 + c_re
z_im_next = 2 * z_re * z_im + c_im
escape if z_re^2 + z_im^2 > 4
```

The core uses one FP multiplier and one FP adder. It time-multiplexes those units across each iteration through a finite-state machine.

### 8.1 Coordinate Generation

The host provides image center and pixel step. The RTL uses integer-truncated half dimensions:

```text
half_w = (cols - 1) >> 1
half_h = (rows - 1) >> 1

c_re_start = center_re - half_w * step
c_im_start = center_im + half_h * step
```

For each row:

```text
c_re = c_re_start
for each column: c_re += step
after row: c_im -= step
```

The software reference intentionally mirrors this integer-center behavior. This avoids false mismatches versus a conventional floating-centered renderer.

### 8.2 Per-Pixel FSM Pipeline

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

### 8.3 Escape Check

Escape is detected with:

```text
z_re^2 + z_im^2 > 4.0
```

The implementation includes quick checks on each squared term and on their sum:

```verilog
quick_esc(z_re_sq) || quick_esc(z_im_sq) || quick_esc(add_result)
```

`quick_esc` compares the floating-point exponent against `bias + 2` and handles the exact `4.0` boundary by checking mantissa bits. Values greater than 4.0 escape. Exact 4.0 does not escape.

### 8.4 Output And Backpressure

When a pixel is complete, the core waits until the FIFO is not full, writes the 16-bit iteration count, and then advances to the next pixel.

The FIFO has 128 entries of 16-bit data. This is enough to absorb short mismatch between compute bursts and UART TX, but the system is fundamentally streaming and will backpressure the core when UART is the bottleneck.

## 9. UART Design

UART is 8N1, no parity, no flow control.

Current baudrate is 460800. With a 100 MHz clock:

```text
CLOCKS_PER_BIT = 217
actual baud ~= 100e6 / 217 = 460829.49 baud
error ~= +0.0064%
```

`uart_rx.v` synchronizes the asynchronous RX input with two flip-flops, detects the falling start edge, waits half a bit, then samples each data bit every `CLOCKS_PER_BIT` clocks. The current implementation uses `CLOCKS_PER_BIT - 1` comparisons to avoid off-by-one bit timing drift.

`uart_tx.v` serializes one start bit, eight data bits, and one stop bit. `transmit_avail` acts as a ready signal for `tx_ctrl`.

### 9.1 Baudrate Experiment Summary

The design was tested at higher baudrates:

| Baudrate | Result |
|---:|---|
| 115200 | Stable, original baseline. |
| 460800 | Stable, current default. |
| 921600 | Built and met timing, but board-level UART communication timed out. |

921600 likely needs a more robust UART RX design, such as oversampling or a fractional baud generator.

## 10. TX Controller And Large-Frame Support

`tx_ctrl.v` sends response header, drains pixels from the FIFO, sends each pixel little-endian, computes checksum, and sends one checksum byte.

The response size is based on:

```verilog
wire [31:0] total_pixels = {16'd0, rows} * {16'd0, cols};
wire [31:0] total_bytes  = total_pixels * 2;
```

The explicit 32-bit cast is important. Without it, Verilog computes `rows * cols` using the operand widths, producing a 16-bit product before extension. That caused images larger than 65535 pixels to fail. The fix was validated with `320x240` and `1920x1080` frames.

`queue.v` has synchronous read behavior. `tx_ctrl` therefore includes `S_READ_WAIT` between asserting `fifo_rd` and using `fifo_data`. This prevents pixel misalignment.

## 11. Host Software Architecture

Host code is in `python/mandelbrot_host.py`.

Responsibilities:

| Component | Responsibility |
|---|---|
| CLI parser | Accept center, step, max iteration, dimensions, output, mode, port, timeout, verify flag. |
| FP encoding | Pack FP64 with Python `struct.pack('<d')`; pack FP128 manually for experimental mode. |
| Command builder | Build little-endian command packet and XOR checksum. |
| Serial transport | Open `COM4` by default at 460800 baud. |
| Response receiver | Read header, expected pixel bytes, checksum, and convert to uint16 pixels. |
| Renderer | Convert iteration counts to PNG or text output. |
| Software reference | Optional `--verify` computes a Python Mandelbrot image matching RTL coordinate rules. |
| Timing | Print FPGA elapsed, pixels/s, render elapsed, software elapsed, and total elapsed. |

Typical command:

```bash
python python\mandelbrot_host.py --width 1920 --height 1080 --max-iter 512 --center -0.743643887037151 0.13182590420533 --step 0.000005 --timeout 1800 --output python\hw_1080p_zoom.png
```

### 11.1 Software Reference Matching RTL

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

### 12.3 Host-Side Random Reference Testing

`python/test_random_compare.py` compares host/software reference conventions across randomized cases. This catches coordinate convention errors, checksum assumptions, and corner cases in command construction.

Example validated command:

```bash
python python/test_random_compare.py --cases 300 --seed 20260608
```

### 12.4 Hardware Smoke Tests

`python/test_esc.py` sends 1x1-like commands for obvious escape points. It verifies UART RX, command parsing, core start, escape logic, FIFO/TX, and host parsing.

Validated points include:

```text
c=(2.5,0) -> iter=1
c=(2.6,0) -> iter=1
c=(3.0,0) -> iter=1
c=(4.1,0) -> iter=1
```

### 12.5 Hardware Image Verification

For moderate images, the host can run software verification:

```bash
python python\mandelbrot_host.py --verify --width 160 --height 120 --max-iter 256 --output python\verify.png
```

Many tested cases reached `100.00%` match.

For large 1080p or very high iteration tests, `--verify` is normally skipped because Python software rendering becomes slow.

### 12.6 Large-Frame Verification

The 32-bit pixel-count fix was validated with:

```text
320x240 @ 128, center=(1.0,1.0): 76800/76800 match, 22873.22 pixels/s
1920x1080 frames: successful transfer and rendering
```

## 13. Performance Characteristics

The system has two main bottlenecks:

1. UART bandwidth for fast-escaping or low-iteration scenes.
2. FP/core compute for high-iteration zooms.

At 460800 baud, the practical upper bound is roughly:

```text
460800 bits/s / 10 UART bits/byte / 2 bytes/pixel ~= 23040 pixels/s
```

Measured fast-escape throughput is close to this limit:

```text
160x120 fast escape: 22623.99 pixels/s
320x240 fast escape: 22873.22 pixels/s
```

High-iteration examples:

| Case | Throughput |
|---|---:|
| `160x120 @ 512`, standard view | 2162.71 pixels/s |
| `640x360 @ 1024`, Seahorse zoom | 13209.46 pixels/s |
| `320x180 @ 4096`, deep Seahorse `step=1e-8` | 366.16 pixels/s |
| `160x90 @ 16384`, deep Seahorse `step=1e-8` | 80.89 pixels/s |
| `80x45 @ 65535`, deep Seahorse `step=1e-8` | 20.43 pixels/s |

Validated 1080p examples:

| Case | FPGA Time | Throughput |
|---|---:|---:|
| 1080p fast escape @128 | 104.666 s | 19811.65 pixels/s |
| 1080p standard @64 | 94.546 s | 21932.26 pixels/s |
| 1080p Seahorse @512, step `5e-6` | 235.503 s | 8804.97 pixels/s |
| 1080p Mini-brot @8192, step `1e-9` | 1198.049 s | 1730.81 pixels/s |

## 14. Resource Use

Latest representative FP64 placed utilization after timing fixes:

| Resource | Usage |
|---|---:|
| Slice LUTs | 1993 / 17600, 11.32% |
| Slice Registers | 2659 / 35200, 7.55% |
| DSP48E1 | 10 / 80, 12.50% |
| Block RAM Tile | 0.5 / 60, 0.83% |
| RAMB18 | 1 / 120, 0.83% |

The design is not resource-limited. It is primarily limited by FP iteration latency and UART bandwidth.

## 15. Known Limitations

| Limitation | Details |
|---|---|
| One compute core | Pixels are computed serially. High-iteration images can take minutes to hours. |
| UART output | Fast scenes are capped near 23000 pixels/s at 460800 baud. |
| FP64 precision | Very deep zooms below approximately `1e-12` to `1e-14` pixel step become precision-sensitive. |
| FP units are IEEE-like, not full IEEE-754 | No full NaN/Inf/denormal/rounding support. |
| FP128 mode exists structurally | Most validation and performance work has focused on FP64. |
| Max iteration field is 16-bit | Maximum supported `max_iter` is 65535. |

## 16. Future Improvement Directions

Most valuable next steps:

1. Add multiple Mandelbrot cores sharing one UART/TX stream or using a wider output path.
2. Improve UART to 921600 or higher with oversampling/fractional baud generation.
3. Add an optional faster transport, such as USB FIFO, SPI, Ethernet, or memory-mapped PS interface on Zynq.
4. Add cardioid and period-2 bulb classification to skip interior pixels quickly.
5. Evaluate fixed-point arithmetic for Mandelbrot-specific deep zoom windows.
6. Validate and optimize FP128 mode for deeper zooms beyond FP64 precision comfort.
7. Replace the simple FIFO with deeper buffering if future transports create burstier output patterns.

## 17. Build And Run Commands

Simulation:

```bash
vivado -mode batch -source sim_fp.tcl
vivado -mode batch -source sim_core.tcl
```

Build and program:

```bash
vivado -mode batch -source build_fp64.tcl
vivado -mode batch -source program.tcl
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
