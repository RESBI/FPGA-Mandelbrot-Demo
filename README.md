# Mandelbrot FPGA Accelerator

UART-controlled FPGA Mandelbrot renderer. The current validated target is VMC_RTSB ZU4EV with a single-ended `24.576 MHz` system clock. The accepted build uses 12 FP64 workers, 8 in-flight pixel contexts per worker, dynamic row scheduling, and a `6.144 Mbaud` FT232HL UART link with a `50 us` host command byte gap.

Current architecture and validation details are in [doc/ARCHITECTURE.md](doc/ARCHITECTURE.md). The optimization log for this board/clock is [doc/VMC_RTSB_ZU4EV_24576_OPT_REPORT.md](doc/VMC_RTSB_ZU4EV_24576_OPT_REPORT.md). Historical evolution from the earlier boards and clocking points is in [doc/ARCHITECTURE_EVOLUTION_REPORT.md](doc/ARCHITECTURE_EVOLUTION_REPORT.md).

## Current Validated Configuration

| Item | Value |
|---|---:|
| FPGA target | `xczu4ev-sfvc784-1-i` |
| Board | VMC_RTSB ZU4EV |
| Clock | Single-ended `sys_clk`, `24.576 MHz` |
| Constraint file | `constraints_vmc_rtsb_zu4ev/led.xdc` |
| UART pins | FPGA RX `D12`, FPGA TX `C12` |
| UART baud | `6,144,000` |
| Host command byte gap | `0.00005 s` |
| Host serial default | `COM6` |
| Floating point | FP64 |
| Workers | `12` |
| Contexts per worker | `8` |
| Scheduler | Dynamic idle-core rows |
| Worker FPU tag latency | `MUL_LAT=6`, `ADD_LAT=9` |
| Largest validated frame | `1920x1080` |
| Final 6-scene result | `6/6 PASS`, `0` retries |

Accepted bitstream path after `build_fp64.tcl`:

```text
fp64_zu4ev_proj/mandelbrot_fp64.runs/impl_1/top.bit
```

## Repository Layout

```text
Mandelbrot/
├── rtl/                                  RTL source
│   ├── top.v                             ZU4EV top-level integration
│   ├── mandelbrot_multicore.v            Worker wrapper, dispatch, FIFOs, collector
│   ├── mandelbrot_core_worker_kctx.v      Accepted multi-context worker
│   ├── fp_mul.v / fp_add.v                FP64 arithmetic pipelines
│   ├── uart_rx.v / uart_tx.v              UART link
│   ├── cmd_parser.v                       Host command parser
│   └── tx_ctrl.v                          Tiled response transmitter
├── constraints_vmc_rtsb_zu4ev/            ZU4EV pin and clock constraints
├── python/                                Host tools and benchmarks
│   ├── mandelbrot_host.py                 Main render/verify CLI
│   ├── host_tile_stability_benchmark.py   Six-scene 1080p benchmark
│   ├── uart_raw_probe.py                  Raw response probe
│   └── uart_rx_burst_capture_probe.py     High-baud command burst diagnostic
├── doc/                                   Architecture and optimization reports
├── build_fp64.tcl                         Accepted ZU4EV 24.576 MHz build
├── build_fp64_zu4ev_24576_sweep.tcl       Worker/context sweep build
├── build_fp64_200mhz.tcl                  Compatibility wrapper to the sweep script
├── program.tcl                            Vivado auto-connect programming script
└── sim_multicore_dynamic_contexts.tcl      Parameterized dynamic multicore simulation
```

## Build

Use Vivado 2024.2 or compatible.

Default accepted build:

```powershell
& "Z:\Softwares\Xilinx\Vivado\2024.2\bin\vivado.bat" -mode batch -source build_fp64.tcl -nolog -nojournal
```

Worker/context sweep build, for example `14 workers / 4 contexts`:

```powershell
& "Z:\Softwares\Xilinx\Vivado\2024.2\bin\vivado.bat" -mode batch -source build_fp64_zu4ev_24576_sweep.tcl -tclargs 4 14 -nolog -nojournal
```

`build_fp64_200mhz.tcl` is kept as a compatibility wrapper but is no longer the preferred name because the current board clock is `24.576 MHz`, not 200 MHz.

## Program

```powershell
& "Z:\Softwares\Xilinx\Vivado\2024.2\bin\vivado.bat" -mode batch -source program.tcl -tclargs "./fp64_zu4ev_proj/mandelbrot_fp64.runs/impl_1/top.bit" -nolog -nojournal
```

The current flow uses Vivado hardware auto-connect. XVC is not required.

## Run And Verify

Small frame verification:

```powershell
python python\mandelbrot_host.py --port COM6 --baud 6144000 --tx-byte-gap 0.00005 --width 160 --height 120 --max-iter 128 --center -0.5 0.0 --step 0.005 --timeout 180 --verify --tile-width 160 --tile-height 120 --tile-retries 1 --output python\hw_24576_160x120_6144k.png
```

Six-scene 1080p benchmark:

```powershell
python python\host_tile_stability_benchmark.py --port COM6 --baud 6144000 --tx-byte-gap 0.00005 --runs 1 --tile-width 1920 --tile-height 120 --tile-retries 3 --run-tag zu4ev24576_6144k_c12ctx8 --summary-name zu4ev24576_6144k_c12ctx8_6scene.md
```

The benchmark writes summaries under `python/host_tile_stability_bench/`.

## Final ZU4EV Performance

Accepted `12 workers / 8 contexts / 6.144 Mbaud / 50 us TX byte gap` result:

| Scene | Transport | Retries | FPGA s | Pixels/s | SW match |
|---|---:|---:|---:|---:|---:|
| fast escape @128 | PASS | 0 | `9.587` | `216,288.01` | `2,073,588 / 2,073,600` |
| standard @64 | PASS | 0 | `9.622` | `215,498.75` | `2,073,600 / 2,073,600` |
| Seahorse zoom @512 | PASS | 0 | `15.192` | `136,492.42` | `2,072,760 / 2,073,600` |
| deep tendrils @8192 | PASS | 0 | `27.377` | `75,742.33` | `2,072,027 / 2,073,600` |
| deep mini-brot @8192 | PASS | 0 | `71.977` | `28,809.10` | `2,058,166 / 2,073,600` |
| deep Seahorse @1024 | PASS | 0 | `31.128` | `66,614.27` | `2,049,714 / 2,073,600` |

Routed resource/timing for the accepted build:

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

## Historical Comparisons

Historical results are retained for perspective. They are not the current build target.

| Platform/config | Clock/UART | Workers/contexts | Representative status |
|---|---|---:|---|
| XC7K70T direct-200MHz | 200 MHz, 12 Mbaud | 6 / 4 | Fastest historical high-clock point; six-scene 1080p passed in earlier branch. |
| XC7K70T 100MHz reference | 100 MHz | 4 / 4 | Useful clock/reference point retained in historical docs. |
| ZU4EV candidate | 24.576 MHz, 6.144 Mbaud | 14 / 4 | Routed and passed six scenes, but slower than 12/8 and had one retry. |
| ZU4EV accepted | 24.576 MHz, 6.144 Mbaud | 12 / 8 | Current default. Six scenes passed with zero retries. |

The `14/4` experiment showed that fewer contexts plus more workers is not better for this low-clock build. Four contexts do not hide the existing FP64 worker latency well enough; `12/8` is the best validated resource/performance point.

## Notes

Deep-scene exact SW match can be below 100% because FP64 boundary pixels differ slightly between the RTL arithmetic and the software reference. Transport pass and full-frame receipt are the board-level stability criteria for those views.

The accepted high-baud mode requires `--tx-byte-gap 0.00005`. Without command pacing, the short host-to-FPGA command burst can be corrupted at `6.144 Mbaud`, even though echo-only tests pass.
