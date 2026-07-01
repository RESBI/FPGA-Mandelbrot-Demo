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

Six 1080p scenes were run for 10 runs each with host tiles `1920x120`, `12 Mbaud`, and `--tile-retries 3`. Summary file:

```text
python/host_tile_stability_bench/zu4ev200m_c12ctx8_10run.md
```

| Candidate | Scene | Transport pass | Retry events | Mean FPGA s | Min s | Max s | CV | Mean pixels/s | Notes |
|---|---|---:|---:|---:|---:|---:|---:|---:|---|
| 12w/8ctx | fast escape @128 | `10/10` | `4` | `4.563` | `4.146` | `7.261` | `21.96%` | `468446.75` | Full frame received; boundary exact match `2073588/2073600` |
| 12w/8ctx | standard @64 | `10/10` | `2` | `4.353` | `4.141` | `5.191` | `10.06%` | `480268.18` | Exact match `2073600/2073600` |
| 12w/8ctx | Seahorse zoom @512 | `10/10` | `2` | `4.499` | `4.288` | `6.371` | `14.62%` | `467436.73` | Full frame received; known FP64/SW boundary differences |
| 12w/8ctx | deep tendrils @8192 | `10/10` | `3` | `4.739` | `4.417` | `5.492` | `10.79%` | `441838.90` | Full frame received; known FP64/SW boundary differences |
| 12w/8ctx | deep mini-brot @8192 | `10/10` | `6` | `10.146` | `9.181` | `12.295` | `10.91%` | `206484.60` | Full frame received; known FP64/SW boundary differences |
| 12w/8ctx | deep Seahorse @1024 | `10/10` | `2` | `4.967` | `4.754` | `5.805` | `8.89%` | `420129.06` | Full frame received; known FP64/SW boundary differences |

The retry events are tile-level recoveries. They reduce the 10-run mean relative to the best single-run values, especially in fast escape and deep mini-brot, but all 60 scene runs completed successfully.

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

| Scene | XC7K70T 6w/4ctx 200MHz mean s | ZU4EV 12w/8ctx 200MHz mean s | Speedup vs 6w/4ctx | ZU4EV mean pixels/s |
|---|---:|---:|---:|---:|
| fast escape @128 | `4.641` | `4.563` | `1.017x` | `468446.75` |
| standard @64 | `4.636` | `4.353` | `1.065x` | `480268.18` |
| Seahorse zoom @512 | `5.715` | `4.499` | `1.270x` | `467436.73` |
| deep tendrils @8192 | `8.567` | `4.739` | `1.808x` | `441838.90` |
| deep mini-brot @8192 | `20.963` | `10.146` | `2.066x` | `206484.60` |
| deep Seahorse @1024 | `9.668` | `4.967` | `1.946x` | `420129.06` |

The ZU4EV 12w/8ctx 10-run mean improves every scene against the best previous 7K70T 200MHz 6w/4ctx point. The improvement is modest on shallow/fast scenes because fixed host-tile, command, collection, UART overhead, and occasional tile retries are significant. It is much larger on deep compute-heavy scenes, where the added workers and contexts keep more FP pipelines occupied.

### Pixels Per Cycle

For the accepted 200MHz candidate, effective pixels per FPGA cycle are computed as `pixels/s / 200,000,000`.

| Scene | Current mean pixels/s | Current pixels/cycle @200MHz | Normalized PPC vs XC7K70T 6w/4ctx 200MHz |
|---|---:|---:|---:|
| fast escape @128 | `468446.75` | `0.002342` | `1.017x` |
| standard @64 | `480268.18` | `0.002401` | `1.065x` |
| Seahorse zoom @512 | `467436.73` | `0.002337` | `1.270x` |
| deep tendrils @8192 | `441838.90` | `0.002209` | `1.808x` |
| deep mini-brot @8192 | `206484.60` | `0.001032` | `2.066x` |
| deep Seahorse @1024 | `420129.06` | `0.002101` | `1.946x` |

Both designs run at 200MHz, so the normalized PPC column is numerically the same as the time speedup over the XC7K70T 6w/4ctx point. It shows that the ZU4EV gain is not a clock-frequency artifact; it comes from more deployable parallelism and more contexts per worker.

### Resource Cost Of Scaling

| Metric | 6w/4ctx baseline | 12w/8ctx accepted | Increase |
|---|---:|---:|---:|
| CLB LUTs | `30057` (`34.22%`) | `85171` (`96.96%`) | `2.83x` |
| CLB Registers | `27099` (`15.43%`) | `71453` (`40.67%`) | `2.64x` |
| BRAM Tiles | `13.5` (`10.55%`) | `25.5` (`19.92%`) | `1.89x` |
| DSPs | `61` (`8.38%`) | `121` (`16.62%`) | `1.98x` |

The accepted point nearly exhausts LUT capacity while leaving DSP and BRAM capacity mostly unused. This explains why the next optimization should reduce LUT/routing pressure and command-parameter fanout before attempting more workers.

## Increasing ADD/MUL Unit Count Feasibility

This section evaluates whether the next optimization should add more FP64 adders or multipliers inside each worker, rather than adding more workers. The current worker architecture is `12 workers / 8 contexts`, with one `fp_mul` and one `fp_add` per worker:

```text
per worker: 8 contexts -> 1 shared fp_mul + 1 shared fp_add -> ordered commit FIFO
whole design: 12 workers -> 12 fp_mul + 12 fp_add
```

The resource picture is asymmetric:

| Resource | Current used | Device | Headroom | Interpretation |
|---|---:|---:|---:|---|
| CLB LUTs | `85171` | `87840` | `2669` LUTs (`3.04%`) | Very little safe logic/routing headroom. |
| CLB Registers | `71453` | `175680` | `104227` registers | Plenty of FF headroom. |
| DSPs | `121` | `728` | `607` DSPs | DSP capacity is not the limiter. |
| BRAM Tiles | `25.5` | `128` | `102.5` tiles | BRAM capacity is not the limiter. |

Therefore, the feasibility question is not whether the FPGA has enough DSP blocks. It is whether a multi-FPU worker can be implemented without substantially increasing LUT usage, long route delay, wide context muxes, and high-fanout control. In the current generic 8-context scoreboard worker, adding FPU lanes directly would duplicate operand muxes, tag pipes, ready scans, and writeback demux paths. That is likely to be LUT/routing-limited before it becomes DSP-limited.

### Current Per-Pixel Operation Balance

One non-escaping Mandelbrot iteration uses approximately:

| Operation class | Operations per iteration | Current shared lane |
|---|---:|---|
| Multiplication | `3` | `z_re*z_re`, `z_im*z_im`, `z_re*z_im` through one `fp_mul` |
| Addition/subtraction | `5` | magnitude add, subtract real, add `c_re`, double `z_re*z_im`, add `c_im` through one `fp_add` |

The current schedule exposes both multiplication and addition demand. However, the add side has more operations per full non-escaping iteration, and `ADD_LAT=9` is longer than `MUL_LAT=6`. That makes an extra adder more plausible than an extra multiplier. A second multiplier alone would often wait on add-side dependencies and would also increase DSP use without addressing the longer add chain.

### Candidate Options

| Option | Description | Feasibility | Expected performance | Main risk |
|---|---|---|---|---|
| A. `12 workers x 8 ctx x 1M+2A` | Add one extra `fp_add` per worker, keep one multiplier. | Low-to-medium if implemented carefully; poor if added to current generic scoreboard naively. | Deep-scene mean may improve about `1.10x-1.30x`; fast scenes likely `~1.00x-1.05x`. | LUT/routing growth in add ready scan, operand mux, and dual writeback. |
| B. `12 workers x 8 ctx x 2M+1A` | Add one extra `fp_mul` per worker, keep one adder. | Low value. | Likely `~1.00x-1.10x`; only helps if multiplier issue bubbles are a major limiter. | Adds DSP and muxing while leaving add chain bottleneck. |
| C. `12 workers x 8 ctx x 2M+2A` | Add one multiplier and one adder per worker. | Low in current LUT envelope. | Best compute-side theoretical gain, maybe `1.20x-1.45x` on deep scenes if timing closes. | Very likely to exceed LUT/routing headroom in current generic worker. |
| D. `8 or 10 workers x 8 ctx x 1M+2A` | Trade worker count for one extra adder per worker. | Medium; reduces worker fanout and LUT pressure while testing add-lane value. | Deep scenes could match or slightly exceed 12x1M+1A if add-bound; fast scenes may regress from fewer workers. | Uncertain balance: less row parallelism may erase the extra-adder gain. |
| E. Low-LUT ring/barrel worker with `1M+2A` | Redesign worker issue/writeback around fixed slots and local lanes. | Best long-term option. | Could expose real add-lane scaling without generic scoreboard LUT blowup. | Larger RTL change and new verification burden. |

### Recommended Feasible Path

The recommended first experiment is not to add both multiplier and adder lanes. The most defensible path is:

1. Implement an experimental `1M+2A` worker variant.
2. Start with a reduced replication target such as `8 workers / 8 contexts / 1M+2A` or `10 workers / 8 contexts / 1M+2A`.
3. Compare it against the current `12 workers / 8 contexts / 1M+1A` point using simulation first, then route if simulation shows useful improvement.
4. Only consider `2M+2A` after `1M+2A` proves that the add side is the active bottleneck and that the extra lane can be routed.

This ordering avoids spending the small remaining LUT/routing margin on multiplier capacity that may not improve the dependent add-heavy iteration chain.

### Performance Projection

The table below uses the 10-run ZU4EV 12w/8ctx results as the current baseline. The projections are intentionally conservative because host-tile retry events, UART overhead, strict raster order, and row scheduling can hide compute-side gains.

| Scene | Current 12w/8ctx mean s | Current limiter | `12w 1M+2A` projected s | `8-10w 1M+2A` projected s | Notes |
|---|---:|---|---:|---:|---|
| fast escape @128 | `4.563` | UART/host/retry overhead | `4.35-4.55` | `4.50-4.90` | Extra FPU lanes have little useful work on fast escape; fewer workers may regress. |
| standard @64 | `4.353` | Mostly transport/overhead | `4.15-4.35` | `4.30-4.70` | Best single-run values are already near transport ceiling. |
| Seahorse zoom @512 | `4.499` | Mixed compute/output | `3.9-4.2` | `4.0-4.5` | Some add-side improvement may be visible. |
| deep tendrils @8192 | `4.739` | Compute-heavy with retry variance | `3.7-4.2` | `3.9-4.5` | Extra adder is most likely to help here. |
| deep mini-brot @8192 | `10.146` | Compute-bound | `7.8-8.9` | `8.0-9.5` | Best target for `1M+2A`; upper bound still below ideal because dependencies remain. |
| deep Seahorse @1024 | `4.967` | Compute-heavy/mixed | `3.9-4.4` | `4.1-4.7` | Likely similar to tendrils. |

Expected speedup ranges versus current 12w/8ctx:

| Candidate | Fast/standard | Mixed zooms | Deep compute-heavy | Confidence |
|---|---:|---:|---:|---|
| `12w 1M+2A` if it routes | `1.00x-1.05x` | `1.07x-1.15x` | `1.15x-1.30x` | Medium performance, low timing confidence. |
| `8-10w 1M+2A` | `0.90x-1.02x` | `1.00x-1.12x` | `1.05x-1.25x` | Medium feasibility, medium performance uncertainty. |
| `12w 2M+1A` | `1.00x-1.03x` | `1.00x-1.08x` | `1.00x-1.10x` | Low value. |
| `12w 2M+2A` if it routes | `1.00x-1.07x` | `1.12x-1.25x` | `1.25x-1.45x` | Low feasibility in current generic worker. |

The most likely useful result is a compute-heavy speedup, not a new fast-scene record. Fast scenes are already dominated by transport, packet overhead, retries, and host behavior. Extra FP lanes cannot push the 12 Mbaud UART payload ceiling above roughly `600k pixels/s`.

### Concrete RTL Design For `1M+2A`

A minimal experimental `1M+2A` variant would need more than simply instantiating another `fp_add`. The current worker has single-lane assumptions in several places:

| Current structure | Required change for two adders |
|---|---|
| Single `add_a`, `add_b`, `add_neg` operand registers | Split into `add0_*` and `add1_*`, or an indexed array. |
| Single `add_req_valid`, `add_req_op`, `add_req_ctx` | Allow two independent add issue slots per cycle. |
| Single `add_op_pipe[ADD_LAT]`, `add_ctx_pipe[ADD_LAT]` | Duplicate tag pipes per adder lane: `add_lane_op_pipe[lane][stage]`, `add_lane_ctx_pipe[lane][stage]`. |
| Single `add_result` wire | Instantiate `fp_add u_add0` and `fp_add u_add1`, each with separate result. |
| Single add writeback case | Process up to two add completions per cycle, with conflict handling if both target the same context. |
| Generic all-context ready scan | Select up to two independent ready add operations, preferably with lane-local scan windows to avoid N-way mux growth. |
| Initialization path writes directly into add pipe stage 0 | Route init operations through the same lane allocator, or reserve lane 0 for init while lane 1 remains compute-only. |

The safest experimental split is to keep multiplier logic unchanged and add a compute-only second adder:

```text
adder lane 0: existing init + compute add operations
adder lane 1: compute add operations only during S_RUN
```

This reduces the number of init-path changes. During `S_INIT_*`, lane 1 is idle. During `S_RUN`, the scheduler can issue up to two add operations per cycle if two contexts have independent `c_add_ready` work. The existing ordered commit path does not need to change, because it sees completed pixel results, not raw FPU lane count.

Conflict policy should be conservative:

- Do not issue two add operations for the same context in the same cycle.
- If two add results return for the same context in the same cycle due to earlier scheduling, serialize by construction rather than by writeback arbitration.
- Keep operation dependencies as they are today: `AOP_SUB_RE -> AOP_NEXT_RE -> AOP_2X -> AOP_NEXT_IM` remains a chain for one context.

This means the second adder only helps when multiple contexts are add-ready at the same time. That is why at least 8 contexts are useful, and why reducing contexts while adding adders is not attractive.

### Concrete Build Matrix

Before touching the accepted default, the experiment should be isolated behind explicit parameters and separate project names.

Recommended matrix:

| Build | Workers | Contexts | Adders/worker | Multipliers/worker | Purpose |
|---|---:|---:|---:|---:|---|
| `zu4ev_c8_w8_a2m1` | 8 | 8 | 2 | 1 | Feasibility route with lower worker fanout. |
| `zu4ev_c8_w10_a2m1` | 10 | 8 | 2 | 1 | Middle point if 8-worker has timing/resource margin. |
| `zu4ev_c8_w12_a2m1` | 12 | 8 | 2 | 1 | Direct apples-to-apples performance target; likely routing risk. |
| `zu4ev_c8_w12_a1m2` | 12 | 8 | 1 | 2 | Low-priority multiplier-only sanity check if modeling suggests mul starvation. |

Pass gates for each candidate:

1. Behavioral simulation with the existing dynamic-context test at `ROWS=12`, `COLS=160`, `MAX_ITER=256`.
2. Routed 200MHz timing with no setup/hold failures.
3. Resource check that leaves enough LUT headroom for route stability. A practical target is below `95%` CLB LUT for exploratory builds.
4. Small hardware `160x120` `--verify` before any 1080p benchmark.
5. Six-scene benchmark only after the first four gates pass.

### Decision

Adding FP units is technically possible, but not as a direct extension of the current generic scoreboard without risk. The current design is already near the LUT/routing limit, while DSP utilization is only `16.62%`. The best near-term experiment is an isolated `1M+2A` worker variant, preferably first tested at 8 or 10 workers to establish area and timing behavior. A second multiplier alone is not recommended as the first step. A full `2M+2A` worker should wait until a lower-LUT ring/barrel or lane-local issue structure exists.

The most important implementation rule is to prevent the extra FPU lane from doubling the already-expensive global context scan and FP64 operand muxes. If the design requires arbitrary two-of-eight context selection with two 64-bit operand mux trees and two writeback demux trees per worker, it is unlikely to fit or route robustly at the current 12-worker scale.

## Current Decision

`12 workers / 8 contexts` is the current accepted 200 MHz single-ended ZU4EV performance point. It is near the practical LUT/routing limit (`96.96%` CLB LUTs and `0.148ns` WNS), so further raw worker-count scaling is unlikely to be safe without structural changes.

Next optimization candidates should target routing pressure rather than arithmetic stage count:

- Register or localize command parameter fanout into per-worker launch metadata.
- Explore floorplanning or worker grouping if build variance becomes significant.
- Consider reducing per-context state or sharing initialization paths before attempting more workers.
- Only change `fp_mul.v` / `fp_add.v` latency if a routed timing report shows arithmetic logic, not pure route, has become the limiter.
