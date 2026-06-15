# TODO - Mandelbrot FPGA Accelerator

This file tracks current work after the default FP64, 4-worker, dynamic-row, 12 Mbaud, tiled-response design. Historical single-core, 460800/576000 baud, and large-frame bring-up work is documented in `ARCHITECTURE_EVOLUTION_REPORT.md` and related reports.

## Current Default Configuration

| Item | Current Value |
|---|---:|
| Precision | FP64 |
| System clock | 100 MHz |
| Worker count | 4 |
| Worker contexts | 4 per worker |
| Scheduler | Dynamic idle-core row scheduler |
| Dynamic owner depth | 4096 rows per hardware command |
| UART baudrate | 12000000 |
| Response protocol | `RT` / `TD` / `TE` tiled response |
| RTL response tile width | 64 columns |
| Host tiling | Enabled by default |
| Default host tile | full width, up to 120 rows |
| Default compute tile | host tile itself, width capped at 4096 |
| Retry unit | One hardware compute tile |
| Soft reset command | `RST!RST!` |
| Default serial port | `COM9` |

Current default routed timing/resource snapshot:

| Metric | Value |
|---|---:|
| WNS | 0.583 ns |
| TNS | 0.000 ns |
| WHS | 0.039 ns |
| THS | 0.000 ns |
| Slice LUTs | 36367 / 41000, 88.70% |
| Slice Registers | 19149 / 82000, 23.35% |
| DSP48E1 | 37 / 240, 15.42% |
| Block RAM Tile | 9.5 / 135, 7.04% |

## Completed Recently

- Centralized RTL defaults in `../rtl/config.vh`.
- Switched UART RX/TX to a 32-bit fractional-NCO baud generator.
- Set current default host/RTL baudrate to 12 Mbaud.
- Added `RT` / `TD` / `TE` tiled response framing in `../rtl/tx_ctrl.v`.
- Added host parser support for both legacy `RK` and tiled response protocols.
- Made host-driven tiling the default and kept `--full-frame` for the old single-command path.
- Added `--tile-read-timeout` so a byte slip fails a tile read promptly instead of waiting for the global timeout.
- Added compute-tile controls; current default uses the host tile as the compute tile, with compute width capped at 4096.
- Added failed compute-tile coordinate logging and per-compute-tile retry.
- Added UART soft reset command `RST!RST!` and automatic soft reset after failed compute tile attempts.
- Added `--soft-reset` and `--no-soft-reset-on-retry` host options.
- Added `--quiet` single-line progress display with compute-tile and host-tile counters.
- Added synchronous reset to `queue.v` so soft reset clears output and per-core FIFOs.
- Added `tx_ctrl` tiled response simulations for `4096x120` and host-tiled `4096x4096` behavior.
- Added `cmd_parser` soft reset simulation.
- Validated dynamic multicore simulation after reset changes.
- Made the validated XC7K70T 4-context worker the default: timing clean at `WNS=0.583ns`, `160x120` verify PASS, and six 1080p scenes PASS.
- Documented current resource/timing, 4/8-context experiments, pipeline-bubble analysis, and Chinese documentation mirrors.

## P0 - Reliability And Correctness

### Board-Level Soak For Current Compute-Tile Defaults

The previous 30-run 1080p stability data used host-tile retry with older defaults. The current host uses the host tile as the compute tile by default and automatic soft reset on retry, so it needs fresh multi-run board-level soak data beyond the one-run six-scene pass.

Tasks:

- Re-run the six-scene 1080p stability benchmark with current default host/compute tiling.
- Record retry count, recovered compute tile coordinates, elapsed time, and whether soft reset was used.
- Include at least one long `4096x4096` run without `--verify`.
- Keep failed cases in the log; do not shrink or bisect the requested image when recording failures.

### Add Request IDs And Packet Sequence IDs

Current recovery relies on drain-until-quiet and strict command sequencing. A valid-looking stale packet could still be accepted if it survives drain and matches dimensions.

Tasks:

- Add a host-generated request ID to the command and response header.
- Add a monotonically increasing `TD` sequence number inside each response frame.
- Include request ID and sequence ID in checksum or CRC coverage.
- Reject stale, duplicate, skipped, or reordered packets explicitly in the host parser.

### Strengthen Checksums

`TD` currently has a payload-only XOR checksum. Header corruption is caught by semantic checks, but XOR is weak for multi-byte corruption.

Tasks:

- Evaluate CRC-8 or CRC-16 over `TD` header plus payload.
- Keep RTL cost low enough for xc7z010 timing/resource headroom.
- Preserve legacy `RK` parsing unless intentionally removed.

### Add Host Transport Unit Tests

The host parser is now more complex and should have tests that do not require a board.

Tasks:

- Add tests for command packet construction and checksum.
- Add tests for `RT` / `TD` / `TE` parsing with good packets.
- Add tests for bad magic, short payload, bad checksum, out-of-bounds tile, stale dimensions, and retry bookkeeping.
- Add tests for host/compute tile coordinate calculations and seam-free assembly.
- Add tests for quiet progress formatting.

## P1 - Architecture Evolution

### Move From Recompute Retry To Packet Retransmission

Current retry granularity is one hardware compute tile. A dropped byte in one `TD` packet recomputes the entire compute tile because the FPGA does not retain streamed packets.

Tasks:

- Define a bidirectional ACK/NACK response protocol.
- Decide how many recent packets, rows, or compute tiles the FPGA can buffer.
- Evaluate BRAM cost for packet replay versus recompute cost.
- Keep the current simple one-way protocol as a fallback build mode.

### Streaming/Tiled Image Writer For Huge Frames

Host tiling protects FPGA command limits, but the Python host still stores the full final image as a Python list.

Tasks:

- Replace the full-frame Python list with a compact `array('H')`, `numpy`, or streaming row buffer.
- Add tiled PNG/BMP writing or a raw `uint16` output mode.
- Make `16384x16384` practical without requiring a giant Python-object list.
- Treat `65536x65536` as a streaming-only target; raw pixels alone are about 8 GiB.

### Better Transport Than UART

12 Mbaud UART works but still has USB/driver byte-slip risk during long transfers.

Tasks:

- Evaluate FT245-style FIFO, SPI, Ethernet, or Zynq PS memory-mapped transport.
- Define a transport-neutral frame layer so host parser logic can be reused.
- Keep UART as the simplest baseline path.

### Low-LUT Higher-Context Worker

Generic 4ctx now passes board validation on XC7K70T but uses `88.70%` of LUTs. Generic 8ctx exceeded xc7z010 capacity historically and should not be scaled up without a lower-LUT structure.

Tasks:

- Design a specialized 8/12/16-context worker with lower control/register overhead than the generic K-context prototype.
- Reuse one multiplier and one adder first; do not add FP units until context count is high enough.
- Re-run pipeline simulator and RTL simulation for 8ctx/12ctx/16ctx candidates.
- Only evaluate `1M+2A` after a high-context `1M+1A` worker is viable; avoid `2M+1A` unless the ADD bottleneck is solved.

### FP128 Conservative Path

FP128 exists structurally but is not the current high-performance path.

Tasks:

- Make FP128 builds explicitly conservative, for example static scheduling or lower context count if needed.
- Build FP128 and record resource/timing reports.
- Run FP128 unit/core simulations and small hardware smoke tests if timing closes.
- Keep FP64 default performance unaffected.

## P2 - Performance And UX

### Re-Tune Explicit Compute Tile Sizes

The current default favors lower command overhead by using the host tile as the compute tile. Smaller explicit compute tiles may still be useful when retry cost is more important than throughput.

Tasks:

- Sweep `--compute-tile-width 256/512/1024/2048/1920` with `--tile-height 120`.
- Compare retry cost, command overhead, and total frame time across the six standard scenes.
- Keep host tile = compute tile if it remains the best throughput/reliability compromise; otherwise update defaults and docs.

### Reduce Python Host Overhead

The parser already uses bulk `struct.unpack`, but host overhead matters more as compute tiles get smaller.

Tasks:

- Profile receive, unpack, slice assignment, and PNG rendering paths.
- Consider `array('H')`, `memoryview`, or `numpy` for the final buffer.
- Avoid restoring duplicate bitmap checks on the hot path unless debugging.

### Improve Render Output Options

Tasks:

- Add named palettes.
- Add metadata sidecar JSON with command parameters, timing, retry counts, and bitstream defaults.
- Add optional raw `uint16` output for later post-processing.
- Add preset scenes for common zoom points.

## Verification Commands To Run After Major Changes

Host syntax and parser smoke:

```bash
python -m py_compile python\mandelbrot_host.py
python python\mandelbrot_host.py --help
```

Core RTL regressions:

```bash
vivado -mode batch -source sim_multicore_dynamic.tcl
vivado -mode batch -source sim_tx_ctrl_tiled.tcl
vivado -mode batch -source sim_tx_ctrl_host_tiled_4096.tcl
vivado -mode batch -source sim_cmd_parser_soft_reset.tcl
```

Small board smoke:

```bash
python python\mandelbrot_host.py --verify --width 160 --height 120 --max-iter 256 --output python\verify_160x120.png
```

Recommended 1080p transport smoke:

```bash
python python\mandelbrot_host.py --port COM9 --width 1920 --height 1080 --max-iter 128 --center 1.0 1.0 --step 0.002 --timeout 600 --tile-width 1920 --tile-height 120 --tile-retries 3 --quiet --output python\hw_1080p_transport_smoke.png
```

Large logical image smoke, no software verification:

```bash
python python\mandelbrot_host.py --port COM9 --width 4096 --height 4096 --max-iter 8192 --center -0.743643887037151 0.13182590420533 --step 1.2e-09 --timeout 3600 --quiet --output python\hw_4096x4096_smoke.png
```

## Release Checklist

- Run host syntax and `--help` checks.
- Run dynamic multicore simulation.
- Run `tx_ctrl` tiled simulations, including host-tiled `4096x4096`.
- Run soft reset parser simulation.
- Build FP64 bitstream.
- Confirm routed timing has no setup/hold violations.
- Program the board.
- Run one verified small image.
- Run one 1080p quiet transport smoke.
- If transport/tile defaults changed, update `../README.md`, `../README_CN.md`, `ARCHITECTURE.md`, `ARCHITECTURE_CN.md`, `TODO.md`, and `TODO_CN.md` together.
