# VMC_RTSB ZU4EV 200 MHz Optimization Report

This report records the 200 MHz single-ended-clock adaptation and optimization work for the VMC_RTSB ZU4EV board.

## Goal

- Board clock: single-ended `sys_clk` on package pin `E12`.
- Clock frequency: `200 MHz` (`5.000 ns` period).
- UART target: FT232HL on `COM6`, default `12,000,000 baud`.
- Optimization target: maximize full-system 1080p six-scene performance in pixels per cycle while staying functionally correct and timing-clean on the target FPGA.

## Current Stage

This work resumed from a partially adapted branch:

- UART TX pattern was built, programmed, and validated at `COM6 / 12 Mbaud`.
- UART echo was built, programmed, and validated at `COM6 / 12 Mbaud` for `32/32` trials.
- The main Mandelbrot design still needed ZU4EV 200 MHz single-ended build cleanup before meaningful core/count or pipeline optimization.

The current accepted 200 MHz point is now `12 workers / 8 contexts`, `MUL_LAT=6`, `ADD_LAT=9`, `12 Mbaud UART`.

## Board And Build Adaptation

The first step established a buildable and testable main-design baseline. No Mandelbrot arithmetic pipeline algorithm changes were made in this step.

Changes:

- `rtl/top.v`: use single-ended `sys_clk` through `BUFG`; expose only `led[3:2]` for board LEDs.
- `constraints_vmc_rtsb_zu4ev/mandelbrot_top.xdc`: clean ZU4EV main-design constraints with `sys_clk = E12`, `LVCMOS25`, `5.000 ns`, UART pins, and two status LEDs.
- `constraints_vmc_rtsb_zu4ev/uart_test.xdc`: clean UART bring-up constraints for `uart_echo_top` and `uart_tx_pattern_top`.
- `build_fp64.tcl`, `build_fp64_200mhz.tcl`: target `xczu4ev-sfvc784-1-i`.
- `python/mandelbrot_host.py`, `python/host_tile_stability_benchmark.py`: default port changed to `COM6`.

## Change Set By Plan

This section maps the actual file changes to the optimization plan used in this pass.

| Plan item | Files | Change | Reason | Verification |
|---|---|---|---|---|
| Board clock adaptation | `constraints_vmc_rtsb_zu4ev/mandelbrot_top.xdc`, `rtl/top.v` | Added clean `sys_clk=E12`, `200 MHz`, `LVCMOS25` constraints; changed top-level clocking to single-ended `sys_clk` through `BUFG`. | Match the actual VMC_RTSB reference clock and remove stale differential-clock assumptions. | Main build passed at 200 MHz; UART pattern/echo passed on board. |
| ZU4EV UART pin adaptation | `constraints_vmc_rtsb_zu4ev/mandelbrot_top.xdc`, `constraints_vmc_rtsb_zu4ev/uart_test.xdc` | Added `uart_rx=D12`, `uart_tx=C12`, both `LVCMOS25`. | Use the FT232HL wiring on the current board. | TX pattern received on `COM6`; echo passed `32/32` at `12 Mbaud`. |
| UART test-suite correctness | `rtl/uart_echo_top.v`, `rtl/uart_tx_pattern_top.v`, `build_uart_echo.tcl`, `build_uart_tx_pattern.tcl`, `constraints_vmc_rtsb_zu4ev/uart_test.xdc` | Removed stale differential-clock/MMCM 100MHz test-top assumptions; test tops now use single-ended `sys_clk`, `BUFG`, and explicit `CLK_HZ=200000000`; test XDC only constrains clock, UART, and usable LEDs. | Prevent false UART conclusions caused by tests running at the wrong clock or constrained to old-board LEDs. | TX pattern: `pattern_hits=3921`; echo: `32/32`. |
| Programming flow | `program.tcl` | Switched to Vivado hardware auto-connect and device match for `xczu4`; removed XVC-specific open target. | Current setup uses normal Vivado hardware target, not the old XVC path. | Programmed UART pattern, UART echo, and Mandelbrot `12w/8ctx` bitstreams successfully. |
| Main build target | `build_fp64.tcl`, `build_fp64_200mhz.tcl`, `sim_multicore_dynamic_contexts.tcl` | Target part changed to `xczu4ev-sfvc784-1-i`; default build now uses `CORE_COUNT=12`, `WORKER_CONTEXTS=8`; simulation part updated to ZU4EV. | Build and simulate against the actual FPGA target. | Baseline `6/4` sim/build passed; scaled `12/8` sim/build passed. |
| Host defaults | `python/mandelbrot_host.py`, `python/host_tile_stability_benchmark.py`, `python/uart_echo_probe.py`, `python/uart_listen_raw.py`, `python/uart_raw_probe.py` | Default serial port changed from `COM9` to `COM6`. | Match the current host connection. | Python syntax check passed; all board tests used `COM6`. |
| Performance scaling | `rtl/config.vh`, `build_fp64.tcl` | Default compute configuration changed from `6 workers / 4 contexts` to `12 workers / 8 contexts`. | Baseline routed with large resource headroom; scaling workers and contexts improved occupancy of existing FPU pipelines. | `12/8` sim passed; route passed; small HW/SW verify passed; six scenes passed. |

No arithmetic FPU latency change was made in this pass. The routed evidence showed the immediate limit was not a multi-level FP add/mul combinational path, but high-fanout and route-dominated distribution after scaling. Keeping `MUL_LAT=6` and `ADD_LAT=9` avoided functional risk while still improving throughput through parallelism.

## Optimization Log

| Step | Change | Functional simulation | Timing/build | Hardware result | Decision |
|---|---|---|---|---|---|
| Baseline bring-up | ZU4EV 200 MHz single-ended main-design cleanup | `PASS`, `6 workers / 4 contexts`, `12x160`, `max_iter=256`, `1920 pixels` | `PASS`, `WNS=0.751ns`, `TNS=0.000ns` | Not programmed for benchmark | Buildable baseline; resource headroom remained large |
| Parallelism scale-up | Increase to `12 workers / 8 contexts` while keeping `MUL_LAT=6`, `ADD_LAT=9` | `PASS`, `12x160`, `max_iter=256`, `1920 pixels`; sim finish time improved from `15.978ms` to `6.300ms` | `PASS`, `WNS=0.148ns`, `TNS=0.000ns` | Small verify `19200/19200`; six 1080p scenes transport `6/6` | Current accepted performance point |

## Resource And Timing Log

| Candidate | Core count | Contexts | FPU latency | WNS | TNS | LUT | FF | BRAM | DSP | Decision |
|---|---:|---:|---|---:|---:|---:|---:|---:|---:|---|
| Baseline | 6 | 4 | `MUL_LAT=6`, `ADD_LAT=9` | `0.751ns` | `0.000ns` | `30057 / 87840` (`34.22%`) | `27099 / 175680` (`15.43%`) | `13.5 / 128` (`10.55%`) | `61 / 728` (`8.38%`) | Timing-clean; too much resource headroom to be final |
| Scaled | 12 | 8 | `MUL_LAT=6`, `ADD_LAT=9` | `0.148ns` | `0.000ns` | `85171 / 87840` (`96.96%`) | `71453 / 175680` (`40.67%`) | `25.5 / 128` (`19.92%`) | `121 / 728` (`16.62%`) | Accepted; close to LUT/routing limit |

## Timing Interpretation

The 6-worker baseline routed with positive slack and low resource use. Its worst setup paths were route dominated, for example `add_op_pipe[8][0]` to `c_re_next[58]` in worker 5 had only one LUT level and about `94.8%` route delay. That made it clear that the first optimization should consume available FPGA resources with more workers and enough contexts per worker to hide the existing `MUL_LAT=6` and `ADD_LAT=9` latencies, rather than adding arithmetic pipeline stages.

The accepted 12-worker / 8-context candidate is near the practical LUT/routing limit. Its worst setup path is no longer an arithmetic pipeline path. It is route-dominated command-parameter distribution from `u_cmd/step_reg` to a worker's `step_val_reg`, with zero LUT levels and about `98%` route delay. This indicates the current optimization limit is placement/routing and high-fanout distribution under high worker count, not insufficient arithmetic pipeline cuts.

## Accepted 12-Worker / 8-Context Point

The first scaled candidate doubles worker count and doubles contexts per worker. This is aligned with the datapath bottleneck: each worker has one FP multiplier and one FP adder, and more contexts are needed to keep those pipelines occupied across `MUL_LAT=6` and `ADD_LAT=9`.

Behavioral simulation before build:

```text
vivado.bat -mode batch -source sim_multicore_dynamic_contexts.tcl -tclargs WORKER_CONTEXTS 8 CORE_COUNT 12 ROWS 12 COLS 160 MAX_ITER 256 CORE_FIFO_DEPTH 4096 TIMEOUT_CYCLES 30000000
=== DYNAMIC MULTICORE TEST PASS: 1920 pixels ===
```

Routed timing at 200 MHz:

```text
Setup : 0 Failing Endpoints, Worst Slack 0.148ns, Total Violation 0.000ns
Hold  : 0 Failing Endpoints, Worst Slack 0.010ns, Total Violation 0.000ns
```

Hardware small-image verification:

```text
python python\mandelbrot_host.py --port COM6 --width 160 --height 120 --max-iter 256 --center -0.5 0.0 --step 0.005 --output python\hw_zu4ev_200m_c12ctx8_160x120.png --verify --quiet --timeout 60 --tile-width 160 --tile-height 120 --tile-retries 3
FPGA elapsed: 0.058s (332476.74 pixels/s)
HW vs SW: 19200/19200 match (100.00%)
```

## Six-Scene 1080p Log

Six 1080p scenes were run once each with host tiles `1920x120`, `12 Mbaud`, and no retry events. Summary file:

```text
python/host_tile_stability_bench/zu4ev200m_c12ctx8_6scene.md
```

| Candidate | Scene | Transport pass | Retry events | FPGA seconds | Pixels/s | Notes |
|---|---|---:|---:|---:|---:|---|
| 12w/8ctx | fast escape @128 | `1/1` | `0` | `4.150` | `499705.08` | Full frame received; boundary exact match `2073588/2073600` |
| 12w/8ctx | standard @64 | `1/1` | `0` | `4.143` | `500531.67` | Exact match `2073600/2073600` |
| 12w/8ctx | Seahorse zoom @512 | `1/1` | `0` | `4.289` | `483464.75` | Full frame received; known FP64/SW boundary differences |
| 12w/8ctx | deep tendrils @8192 | `1/1` | `0` | `4.418` | `469374.80` | Full frame received; known FP64/SW boundary differences |
| 12w/8ctx | deep mini-brot @8192 | `1/1` | `0` | `9.183` | `225810.49` | Full frame received; known FP64/SW boundary differences |
| 12w/8ctx | deep Seahorse @1024 | `1/1` | `0` | `4.767` | `435016.18` | Full frame received; known FP64/SW boundary differences |

## Performance Comparison

### Simulation Throughput

The same behavioral simulation workload was run before and after scaling:

| Candidate | Workers | Contexts | Sim workload | Sim finish time | Relative speed |
|---|---:|---:|---|---:|---:|
| Baseline | 6 | 4 | `12x160`, `max_iter=256`, `1920 pixels` | `15.978ms` | `1.000x` |
| Scaled | 12 | 8 | `12x160`, `max_iter=256`, `1920 pixels` | `6.300ms` | `2.536x` |

This confirms that the extra workers and contexts materially improve pipeline occupancy and row-level throughput before any board-specific UART or host effects are involved.

### XC7K70T 200MHz Comparison

The most relevant historical comparison is the previous XC7K70T direct-200MHz work, not the older 100MHz reference. Two validated 200MHz points are used here:

- XC7K70T `4 workers / 4 contexts`: first timing-clean direct-200MHz point from `doc/200MHZ_ATTEMPT_REPORT.md`.
- XC7K70T `6 workers / 4 contexts`: later timing-fixed worker-count scaling point from `doc/WORKER_COUNT_SCALING.md`.

| Scene | XC7K70T 4w/4ctx 200MHz s | XC7K70T 6w/4ctx 200MHz s | ZU4EV 12w/8ctx 200MHz s | vs 7K70T 4w | vs 7K70T 6w | ZU4EV pixels/s |
|---|---:|---:|---:|---:|---:|---:|
| fast escape @128 | `5.072` | `4.641` | `4.150` | `1.222x` | `1.118x` | `499705.08` |
| standard @64 | `5.066` | `4.636` | `4.143` | `1.223x` | `1.119x` | `500531.67` |
| Seahorse zoom @512 | `7.879` | `5.715` | `4.289` | `1.837x` | `1.333x` | `483464.75` |
| deep tendrils @8192 | `12.820` | `8.567` | `4.418` | `2.902x` | `1.939x` | `469374.80` |
| deep mini-brot @8192 | `31.625` | `20.963` | `9.183` | `3.444x` | `2.282x` | `225810.49` |
| deep Seahorse @1024 | `13.886` | `9.668` | `4.767` | `2.913x` | `2.028x` | `435016.18` |

The ZU4EV 12w/8ctx result improves every scene against the best previous 7K70T 200MHz point. The improvement is modest on shallow/fast scenes because fixed host-tile, command, collection, and UART overheads are significant. It is much larger on deep compute-heavy scenes, where the added workers and contexts keep more FP pipelines occupied.

### Pixels Per Cycle

For the accepted 200MHz candidate, effective pixels per FPGA cycle are computed as `pixels/s / 200,000,000`.

| Scene | Current pixels/s | Current pixels/cycle @200MHz | Normalized PPC vs XC7K70T 6w/4ctx 200MHz |
|---|---:|---:|---:|
| fast escape @128 | `499705.08` | `0.002499` | `1.118x` |
| standard @64 | `500531.67` | `0.002503` | `1.119x` |
| Seahorse zoom @512 | `483464.75` | `0.002417` | `1.333x` |
| deep tendrils @8192 | `469374.80` | `0.002347` | `1.939x` |
| deep mini-brot @8192 | `225810.49` | `0.001129` | `2.282x` |
| deep Seahorse @1024 | `435016.18` | `0.002175` | `2.028x` |

Both designs run at 200MHz, so the normalized PPC column is numerically the same as the time speedup over the XC7K70T 6w/4ctx point. It shows that the ZU4EV gain is not a clock-frequency artifact; it comes from more deployable parallelism and more contexts per worker.

### Resource Cost Of Scaling

| Metric | 6w/4ctx baseline | 12w/8ctx accepted | Increase |
|---|---:|---:|---:|
| CLB LUTs | `30057` (`34.22%`) | `85171` (`96.96%`) | `2.83x` |
| CLB Registers | `27099` (`15.43%`) | `71453` (`40.67%`) | `2.64x` |
| BRAM Tiles | `13.5` (`10.55%`) | `25.5` (`19.92%`) | `1.89x` |
| DSPs | `61` (`8.38%`) | `121` (`16.62%`) | `1.98x` |

The accepted point nearly exhausts LUT capacity while leaving DSP and BRAM capacity mostly unused. This explains why the next optimization should reduce LUT/routing pressure and command-parameter fanout before attempting more workers.

## Current Decision

`12 workers / 8 contexts` is the current accepted 200 MHz single-ended ZU4EV performance point. It is near the practical LUT/routing limit (`96.96%` CLB LUTs and `0.148ns` WNS), so further raw worker-count scaling is unlikely to be safe without structural changes.

Next optimization candidates should target routing pressure rather than arithmetic stage count:

- Register or localize command parameter fanout into per-worker launch metadata.
- Explore floorplanning or worker grouping if build variance becomes significant.
- Consider reducing per-context state or sharing initialization paths before attempting more workers.
- Only change `fp_mul.v` / `fp_add.v` latency if a routed timing report shows arithmetic logic, not pure route, has become the limiter.
