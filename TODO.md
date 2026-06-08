# TODO - Mandelbrot FPGA Accelerator

This file tracks the current project status and remaining work. Historical timing, arithmetic, UART, FIFO, and large-frame bugs have been fixed; see `ARCHITECTURE.md` for implementation details.

## Current Stable Configuration

| Item | Value |
|---|---:|
| Mode | FP64 |
| System clock | 100 MHz |
| Core/FP effective rate | 100 MHz (`FP_CE_DIV=1`) |
| UART baudrate | 460800 |
| Pixel format | `uint16` iteration count, little-endian |
| Max iteration | 65535 |
| Largest validated frame | 1920x1080 |
| Default host port | `COM4` |

Latest representative timing after true-100 MHz FP pipeline cuts:

| Metric | Value |
|---|---:|
| WNS | 0.258 ns |
| TNS | 0.000 ns |
| WHS | 0.015 ns |
| THS | 0.000 ns |

## Completed

- Fixed FP64 hardware correctness issues in `fp_mul.v`, `fp_add.v`, and `mandelbrot_core.v`.
- Added input/output/pipeline registers to improve timing closure.
- Closed true 100 MHz FP64 core timing with `FP_CE_DIV=1` and no multicycle exceptions.
- Added FP adder and multiplier pipeline cuts for 100 MHz operation.
- Validated true 100 MHz core operation on board.
- Converted UART TX to single `sys_clk` domain.
- Updated UART baudrate to stable `460800`.
- Tested `921600`; it builds but is not board-stable with the current UART RX.
- Fixed FIFO read latency in `tx_ctrl.v` with `S_READ_WAIT`.
- Fixed large-frame pixel count by explicitly widening `rows * cols` to 32-bit.
- Validated frames larger than 65535 pixels, including 1920x1080.
- Added software reference matching RTL integer-centered coordinate convention.
- Added host timing output and `pixels/s` reporting.
- Added `--timeout` host option for long 1080p/high-iteration runs.
- Added random host/reference tests and expanded FP/core simulation coverage.
- Added `README.md` with setup, build, usage, and diagrams.
- Added `ARCHITECTURE.md` with detailed hardware/software architecture.
- Created and pushed initial GitHub repository.

## P0 - Correctness And Reproducibility

### Add Automated TX Controller Large-Frame Simulation

The 32-bit pixel-count fix is hardware-validated, but there is no focused simulation that proves `tx_ctrl` sends exactly `rows * cols` pixels for frames above 65535 pixels.

Tasks:

- Add a `tb_tx_ctrl.v` or extend `tb_core_count.v`.
- Test at least `320x240`, `640x360`, and a small sanity case.
- Check header, byte count, checksum, and final done pulse.

### Add Repository CI-Friendly Tests

Vivado may not be available in generic CI, but lightweight Python checks can still run.

Tasks:

- Add a small Python smoke test for command packet construction/checksum.
- Add a host/reference coordinate convention test.
- Consider a `requirements.txt` with `pyserial` and `pillow`.

### Document Board Pin Assumptions More Clearly

Current `constraint.xdc` is board-specific.

Tasks:

- Identify the exact tested board name/model.
- Add a short pin-mapping section in `README.md` or a `boards/` directory.
- Optionally split constraints by board if multiple boards are used.

## P1 - Performance

### Improve UART Beyond 460800 Baud

`921600` baud was attempted with integer bit periods 108 and 109. Both met timing but timed out on board. Current hypothesis is UART RX sampling robustness rather than core logic.

Tasks:

- Implement oversampling UART RX, e.g. 8x or 16x sampling.
- Consider a fractional baud generator for lower accumulated bit error.
- Re-test `921600`, then try `1M` or higher if hardware allows.
- Keep `460800` as fallback until higher baud is board-stable.

### Add Multi-Core Mandelbrot Compute

The FPGA has resource headroom. Current design is a single serial pixel engine.

Tasks:

- Prototype 2-core raster partitioning.
- Decide row-striping versus pixel interleaving.
- Add arbitration into the output FIFO or a per-core FIFO merge stage.
- Re-evaluate UART bottleneck; multi-core only helps compute-bound scenes unless output bandwidth also improves.

### Add Interior Rejection Fast Paths

Many high-iteration images spend most time on points inside the main cardioid or period-2 bulb.

Tasks:

- Add optional cardioid check.
- Add optional period-2 bulb check.
- Compare cost in FP hardware versus saved iterations.
- Ensure results remain compatible with the selected reference semantics.

### Explore `PIPE_WAIT` Optimization

Current `PIPE_WAIT=9` is conservative and stable for the pipelined true-100 MHz datapath.

Tasks:

- Sweep smaller `PIPE_WAIT` values in simulation.
- Add targeted tests around previously failing pixels.
- Only reduce if all simulation and board verification still pass.

## P2 - Precision And Deep Zoom

### Validate FP128 Mode End-To-End

FP128 mode exists structurally but has not received the same level of board validation as FP64.

Tasks:

- Build FP128 and record resource/timing reports.
- Run `tb_fp.v` and `tb_core.v` under FP128 configuration.
- Run small hardware smoke tests if timing closes.
- Add FP128 host rendering examples.

### Evaluate Fixed-Point Deep-Zoom Core

FP64 becomes precision-sensitive at very deep zooms. For Mandelbrot-only workloads, fixed-point may be faster and easier to scale to deep zooms.

Tasks:

- Pick target fractional width, e.g. Q4.60, Q4.80, or wider.
- Estimate DSP cost and iteration latency.
- Compare image correctness against Python high-precision reference.

### Add High-Precision Software Reference

Python `float` is not enough for very deep zoom verification.

Tasks:

- Add optional `decimal` or `mpmath` reference for selected points.
- Keep default reference fast for normal tests.
- Use high precision only for deep-zoom validation cases.

## P3 - Usability

### Improve Host UX

Tasks:

- Add preset names for known zoom points.
- Add progress reporting based on elapsed time and received bytes.
- Add output metadata sidecar JSON with parameters and timing.
- Add graceful serial retry/resync after timeout.

### Add Image Palette Options

Current palette is simple periodic coloring.

Tasks:

- Add smooth coloring option if fractional escape estimates are implemented.
- Add multiple named palettes.
- Save parameters into PNG metadata if practical.

### Add GUI Or Notebook Demo

Tasks:

- Simple GUI for center/step/max_iter selection.
- Notebook showing benchmark commands and resulting images.
- Optional click-to-zoom workflow.

## Known Limits

| Limitation | Impact |
|---|---|
| Single compute core | High-iteration 1080p renders can take minutes to hours. |
| UART transport | Fast scenes are capped near 23000 pixels/s at 460800 baud. |
| FP64 precision | Very deep zooms below roughly `1e-12` to `1e-14` step become precision-sensitive. |
| Max iteration is 16-bit | Maximum `max_iter` is 65535. |
| Full IEEE-754 not implemented | NaN/Inf/denormal/full rounding behavior is not supported. |
| FP128 not fully validated | FP64 is the current stable target. |

## Useful Benchmarks To Re-Run After Major Changes

Small correctness:

```bash
python python\test_esc.py
python python\mandelbrot_host.py --verify --width 160 --height 120 --max-iter 256 --output python\verify_160x120.png
```

Large-frame path:

```bash
python python\mandelbrot_host.py --verify --width 320 --height 240 --max-iter 128 --center 1.0 1.0 --step 0.005 --timeout 300 --output python\verify_320x240_fast.png
```

UART-limited 1080p:

```bash
python python\mandelbrot_host.py --width 1920 --height 1080 --max-iter 64 --center -0.5 0.0 --step 0.002 --timeout 1200 --output python\hw_1080p_standard.png
```

Compute-heavy deep zoom:

```bash
python python\mandelbrot_host.py --width 160 --height 90 --max-iter 16384 --center -0.743643887037151 0.13182590420533 --step 0.00000001 --timeout 2400 --output python\deep_seahorse_160x90.png
```

## Release Checklist

- Run `sim_fp.tcl`.
- Run `sim_core.tcl`.
- Build FP64 bitstream.
- Confirm routed timing has no setup/hold violations.
- Program board.
- Run `python/test_esc.py`.
- Run one verified small image.
- Run one large-frame smoke test.
- Update README/ARCHITECTURE if interfaces, baudrate, pins, or timing assumptions changed.
