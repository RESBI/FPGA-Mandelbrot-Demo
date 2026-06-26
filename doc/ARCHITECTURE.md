# Mandelbrot FPGA Accelerator Architecture

## Current Target

The current validated target is the VMC_RTSB ZU4EV board using a single-ended `24.576 MHz` system clock. The accelerator is a UART-controlled FP64 Mandelbrot renderer. The host sends one image or tile command, the FPGA computes pixels with dynamically scheduled row workers, and the FPGA streams back 16-bit iteration counts in raster order.

Current accepted deployment point:

| Item | Value |
|---|---:|
| FPGA part | `xczu4ev-sfvc784-1-i` |
| Board | VMC_RTSB ZU4EV |
| Input clock | Single-ended `sys_clk`, `24.576 MHz` |
| Constraint file | `constraints_vmc_rtsb_zu4ev/led.xdc` |
| UART pins | FPGA RX `D12`, FPGA TX `C12` |
| UART baud | `6,144,000` baud |
| Host command pacing | `--tx-byte-gap 0.00005` |
| Host serial default | `COM6` |
| Floating-point mode | FP64 |
| Workers | `12` |
| Contexts per worker | `8` |
| Scheduler | Dynamic idle-core row scheduling |
| Owner table depth | `4096` rows |
| FPU tag latency | `MUL_LAT=6`, `ADD_LAT=9` |
| Largest validated frame | `1920x1080` |
| Final six-scene transport result | `6/6 PASS`, `0` retries |

The accepted bitstream path is:

```text
fp64_zu4ev_proj/mandelbrot_fp64.runs/impl_1/top.bit
```

## Top-Level Flow

```text
Host PC
  |
  | UART command: rows, cols, center, step, max_iter, checksum
  v
uart_rx
  |
  v
cmd_parser
  |
  v
mandelbrot_multicore
  |        |
  |        +-- work_dispatch_dynamic_rows
  |        +-- 12 x mandelbrot_core_worker_kctx
  |        +-- per-worker output FIFOs
  |        +-- raster_collect_dynamic_rows
  v
output queue
  |
  v
tx_ctrl
  |
  v
uart_tx
  |
  v
Host PC
```

`top.v` uses the board `sys_clk` through a `BUFG`. There is no MMCM in the accepted ZU4EV build. All UART, parser, compute, FIFO, and TX control logic run in one synchronous `24.576 MHz` clock domain.

## Main RTL Modules

| Module | File | Role |
|---|---|---|
| `top` | `rtl/top.v` | ZU4EV top-level integration, clock buffer, reset, UART, parser, compute core, output queue, TX controller, LEDs. |
| `uart_rx` | `rtl/uart_rx.v` | 8N1 UART receiver. Uses integer clocks-per-bit and three-point majority sampling. |
| `uart_tx` | `rtl/uart_tx.v` | 8N1 UART transmitter using fractional accumulator timing. |
| `cmd_parser` | `rtl/cmd_parser.v` | Parses host commands and validates XOR checksum before asserting `compute_start`. |
| `mandelbrot_multicore` | `rtl/mandelbrot_multicore.v` | Parameterized worker wrapper, scheduler, per-core FIFOs, raster collector, and `tx_start` generation. |
| `work_dispatch_dynamic_rows` | `rtl/work_dispatch_dynamic_rows.v` | Assigns rows to idle workers and records row ownership. |
| `raster_collect_dynamic_rows` | `rtl/raster_collect_dynamic_rows.v` | Restores raster order from dynamically assigned worker rows. |
| `mandelbrot_core_worker_kctx` | `rtl/mandelbrot_core_worker_kctx.v` | Accepted multi-context worker. Interleaves 8 pixel contexts over one FP64 multiplier and one FP64 adder. |
| `fp_mul` | `rtl/fp_mul.v` | FP64-oriented multiplier pipeline used by each worker. |
| `fp_add` | `rtl/fp_add.v` | FP64-oriented adder/subtractor pipeline used by each worker. |
| `queue` | `rtl/queue.v` | Synchronous FIFO used for worker and output buffering. |
| `tx_ctrl` | `rtl/tx_ctrl.v` | Emits tiled response packets and frame terminator. |
| `debug_leds` | `rtl/debug_leds.v` | LED/status mapping. |

## Protocol

The protocol is binary, little-endian, and frame-oriented.

FP64 command packet:

| Offset | Size | Field |
|---:|---:|---|
| 0 | 1 | Magic `0x4d` |
| 1 | 1 | Precision flag, bit0 `0=FP64`, `1=FP128` |
| 2 | 2 | `rows`, uint16 LE |
| 4 | 2 | `cols`, uint16 LE |
| 6 | 2 | `max_iter`, uint16 LE |
| 8 | 8 | `center_re`, FP64 LE |
| 16 | 8 | `center_im`, FP64 LE |
| 24 | 8 | `step`, FP64 LE |
| 32 | 1 | XOR checksum over previous bytes |

The accepted host mode sends this short command with `50 us` between bytes at `6.144 Mbaud`. This pacing is only for the command direction. The large FPGA-to-host image payload still returns at the full baud rate.

The FPGA returns a tiled response:

```text
RT rows cols
  repeated: TD tile_row tile_col tile_rows tile_cols pixel_payload checksum
TE rows cols
```

Pixels are `uint16` iteration counts, little-endian. The host treats full-frame receipt as transport success. Exact SW match can be below 100% in deep zooms because small FP64 rounding/boundary differences are documented and expected.

## Compute Architecture

Each worker owns one multiplier pipeline and one adder pipeline. The worker does not duplicate arithmetic for every Mandelbrot operation; instead it keeps multiple pixel contexts in flight and schedules ready operations into the shared FP units.

Accepted worker configuration:

| Parameter | Value |
|---|---:|
| `CFG_CORE_COUNT` | `12` |
| `CFG_WORKER_CONTEXTS` | `8` |
| `CFG_WORKER_MUL_LAT` | `6` |
| `CFG_WORKER_ADD_LAT` | `9` |

An attempted `14 workers / 4 contexts` candidate routed with lower LUT usage and higher slack, but board benchmarks showed it was slower in all six 1080p scenes. The final decision is therefore to keep `12/8`: more contexts per worker provide better occupancy than using the freed LUTs for two additional under-occupied workers.

## UART Architecture

The FT232HL side has a `120 MHz` clock and supports fractional division. The FPGA clock is `24.576 MHz`, so useful baud candidates were chosen around simple FPGA clocks-per-bit values and practical FT232HL divisors.

Validated baud points:

| Baud | FPGA clocks/bit | Result |
|---:|---:|---|
| `1,536,000` | 16 | Echo bring-up passed. |
| `3,072,000` | 8 | Full project body passed small-frame and six-scene 1080p. |
| `4,096,000` | 6 | Echo-only passed, full project body without pacing did not respond. |
| `6,144,000` | 4 | Accepted for project body with `50 us` host TX byte gap. |
| `8,192,000` | 3 | Echo failed. |

The high-baud issue was host-to-FPGA command burst reception. Echo-only tests sent one byte and waited for the echo, which inserted a large implicit inter-byte gap. The real Mandelbrot command is a 33-byte burst. A burst-capture diagnostic showed dropped/corrupted bytes at `6.144 Mbaud` without pacing. Adding a `50 us` byte gap made 33-byte command capture stable while retaining high-speed image return.

## Build And Programming

Default accepted build:

```powershell
& "Z:\Softwares\Xilinx\Vivado\2024.2\bin\vivado.bat" -mode batch -source build_fp64.tcl -nolog -nojournal
```

Worker/context sweep build:

```powershell
& "Z:\Softwares\Xilinx\Vivado\2024.2\bin\vivado.bat" -mode batch -source build_fp64_zu4ev_24576_sweep.tcl -tclargs 4 14 -nolog -nojournal
```

Program accepted bitstream:

```powershell
& "Z:\Softwares\Xilinx\Vivado\2024.2\bin\vivado.bat" -mode batch -source program.tcl -tclargs "./fp64_zu4ev_proj/mandelbrot_fp64.runs/impl_1/top.bit" -nolog -nojournal
```

`program.tcl` uses Vivado hardware auto-connect and selects the `xczu4` JTAG device. XVC is not required for the current board flow.

## Verification

Representative RTL simulation:

```powershell
& "Z:\Softwares\Xilinx\Vivado\2024.2\bin\vivado.bat" -mode batch -source sim_multicore_dynamic_contexts.tcl -tclargs WORKER_CONTEXTS=8 CORE_COUNT=12 ROWS=120 COLS=160 MAX_ITER=128 CORE_FIFO_DEPTH=4096 DYNAMIC_OWNER_DEPTH=4096 TIMEOUT_CYCLES=60000000 -nolog -nojournal
```

Small board verification:

```powershell
python python\mandelbrot_host.py --port COM6 --baud 6144000 --tx-byte-gap 0.00005 --width 160 --height 120 --max-iter 128 --center -0.5 0.0 --step 0.005 --timeout 180 --verify --tile-width 160 --tile-height 120 --tile-retries 1 --output python\hw_24576_160x120_6144k.png
```

Six-scene 1080p benchmark:

```powershell
python python\host_tile_stability_benchmark.py --port COM6 --baud 6144000 --tx-byte-gap 0.00005 --runs 1 --tile-width 1920 --tile-height 120 --tile-retries 3 --run-tag zu4ev24576_6144k_c12ctx8 --summary-name zu4ev24576_6144k_c12ctx8_6scene.md
```

## Final Timing, Utilization, Performance

Accepted `12/8 @ 6.144 Mbaud` routed metrics:

| Metric | Value |
|---|---:|
| WNS | `25.024 ns` |
| TNS | `0.000 ns` |
| WHS | `0.010 ns` |
| CLB LUTs | `84,949 / 87,840 = 96.71%` |
| LUT as Logic | `81,937 / 87,840 = 93.28%` |
| CLB Registers | `71,408 / 175,680 = 40.65%` |
| Block RAM Tile | `25.5 / 128 = 19.92%` |
| DSPs | `121 / 728 = 16.62%` |

Final six-scene 1080p board benchmark:

| Scene | Transport | Retries | FPGA s | Pixels/s | SW match |
|---|---:|---:|---:|---:|---:|
| fast escape @128 | PASS | 0 | `9.587` | `216,288.01` | `2,073,588 / 2,073,600` |
| standard @64 | PASS | 0 | `9.622` | `215,498.75` | `2,073,600 / 2,073,600` |
| Seahorse zoom @512 | PASS | 0 | `15.192` | `136,492.42` | `2,072,760 / 2,073,600` |
| deep tendrils @8192 | PASS | 0 | `27.377` | `75,742.33` | `2,072,027 / 2,073,600` |
| deep mini-brot @8192 | PASS | 0 | `71.977` | `28,809.10` | `2,058,166 / 2,073,600` |
| deep Seahorse @1024 | PASS | 0 | `31.128` | `66,614.27` | `2,049,714 / 2,073,600` |

Detailed optimization log: `doc/VMC_RTSB_ZU4EV_24576_OPT_REPORT.md`.

## Historical Context

The previous XC7K70T direct-200MHz architecture remains useful as a historical performance reference, but it is no longer the current board target. Its reports are retained in `doc/200MHZ_ATTEMPT_REPORT.md`, `doc/WORKER_COUNT_SCALING.md`, and earlier sections of `doc/ARCHITECTURE_EVOLUTION_REPORT.md`.
