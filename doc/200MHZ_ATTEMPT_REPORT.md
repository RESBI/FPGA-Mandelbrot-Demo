# 200 MHz Clock Attempt Report

This report records the latest XC7K70T timing-closure work for running the Mandelbrot FP64 design directly from the board 200 MHz differential clock.

## Baseline And Current Default

This report was originally written while the validated default build was the 100MHz 4-context worker. After the 200MHz closure and hardware validation described below, the repository default was changed to direct-200MHz 4ctx. The 100MHz 4ctx build is now kept as `build_fp64_100mhz.tcl` for reference comparisons.

Reference points:

| Build | Clock | WNS | TNS | LUT | FF | DSP |
|---|---:|---:|---:|---:|---:|---:|
| 2ctx historical baseline | 100 MHz MMCM | `1.148ns` | `0.000ns` | `13726` | `14559` | `37` |
| 4ctx 100MHz reference | 100 MHz MMCM | `0.583ns` | `0.000ns` | `36367` | `19149` | `37` |
| 4ctx current default | direct 200 MHz | `0.015ns` | `0.000ns` | `20288` | `17202` | `37` |

This report records the direct-200MHz 4-worker 4ctx build that became the default before the later 6-worker scaling fix. It was built, programmed, verified against software on a `160x120` image, and benchmarked on the six 1080p host scenes.

## 200 MHz Test Entry

The direct-clock experiment is isolated from the default build:

| File | Purpose |
|---|---|
| `build_fp64.tcl` | Current default build; now 6-worker direct-200MHz 4ctx after the worker-count scaling fix. |
| `build_fp64_200mhz.tcl` | Compatibility/experiment entry for direct 200 MHz projects; accepts `-tclargs 2` or `-tclargs 4` for `WORKER_CONTEXTS`. |
| `build_fp64_100mhz.tcl` | 100MHz 4ctx reference build. |
| `rtl/top.v` | Supports both `DIRECT_200MHZ=1` direct clocking and `DIRECT_200MHZ=0` MMCM 100MHz reference clocking. |

The experiment uses `CLK_HZ=200000000`, `DIRECT_200MHZ=1`, `SCHED_MODE=1`, `DYNAMIC_OWNER_DEPTH=4096`, and Vivado performance/phys-opt directives. Timing-failing bitstreams were not programmed.

## Effective RTL Changes

These changes improved routed timing and are worth keeping as 200 MHz candidates:

| Area | Change | Effect |
|---|---|---|
| `fp_add.v` | Split compare/select, normalize, and final mantissa/exponent selection into additional stages. `ADD_LAT` changed from `7` to `9`. | Removed the FP adder normalize/final-select path from the top of the 2ctx timing report. |
| `fp_mul.v` | Split the 53-bit mantissa product into registered 26/27-bit partial products. `MUL_LAT` changed from `6` to `7`. | Improved 2ctx WNS, but increased DSP use from `37` to about `65` and still leaves Vivado DPOP-2 warnings. |
| `tx_ctrl.v` | Added `S_TILE_ADVANCE` and registered tile/row advance calculations. | Removed `tx_ctrl` row/tile counter logic from the worst 2ctx paths. |
| `mandelbrot_core_worker_2ctx.v`, `mandelbrot_core_worker_kctx.v` | Updated FPU result tag pipelines after FP retiming. Current 2ctx uses `MUL_LAT=7`, `ADD_LAT=9`; final request-sliced kctx uses `MUL_LAT=6`, `ADD_LAT=9`. | Required for functional alignment after FPU pipeline changes and request slicing. |
| `mandelbrot_core_worker_kctx.v` | Replaced combinational scans of `add_op_pipe`/`mul_op_pipe` for MAG/ZRZI in-flight detection with per-context issued flags. | Removes a long feedback dependency in the kctx worker, but is not enough to make 4ctx close at 200 MHz. |

## 200 MHz Results

| Build | Result | Main Feedback |
|---|---:|---|
| 4ctx initial direct 200 MHz | About `WNS=-1.7ns`, very large TNS | Worst paths in kctx FPU operand/control muxes; route delay dominated. |
| 4ctx after clocking cleanup | About `WNS=-1.6ns` | Clocking cleanup helped only slightly; issue/control paths remained dominant. |
| 2ctx baseline direct 200 MHz | `WNS=-1.261ns`, `TNS=-2139.864ns`, 5052 failing endpoints | Worst path in FP multiplier DSP cascade. |
| 2ctx after multiplier split | `WNS=-1.070ns`, `TNS=-1136.965ns`, 3290 failing endpoints | Improved but DSP use increased and DPOP-2 warnings remained. |
| 2ctx after `tx_ctrl` split | `WNS=-0.740ns`, `TNS=-727.716ns`, 2810 failing endpoints | Worst path moved to FP adder normalize/final select. |
| 2ctx after adder normalize/final split | `WNS=-0.271ns`, `TNS=-64.200ns`, 652 failing endpoints | Worst path moved to adder compare/select and worker issue. |
| 2ctx after adder compare/select split | `WNS=-0.122ns`, `TNS=-4.469ns`, 94 failing endpoints | Very close, but not signoff-clean; worst path is `launch_col_reg[11] -> add_a_reg[34]`, route `79.104%`. |
| 4ctx with the same FPU/tx changes | Still not close; one run reached about `WNS=-1.2ns` before a Vivado post-route crash | Remaining paths are kctx `launch_col`, `rows`, `c_state`, and FPU operand mux/control. |
| 4ctx issue-request register experiment | `WNS=-2.196ns`, `TNS=-14997.266ns`; LUT `96.24%`, slice `99.75%` | Rejected. It moved the mux endpoint to request registers and worsened LUT/slice congestion. |
| Attempted 3ctx kctx build | Routed around `WNS=-6.5ns`, `TNS=-74us`; post-route phys-opt crashed | Rejected. `CONTEXTS=3` creates expensive non-power-of-two modulo/selection logic in the current kctx scheduler. |
| 4ctx after targeted kctx cleanup | `WNS=-0.457ns`, `TNS=-356.943ns`, 2177 failing endpoints | Post-route phys-opt brought the design close enough for targeted RTL work. Worst paths were launch/commit/control into wide FPU operand and context registers. |
| 4ctx after clearing `z` on context release and default-driving FPU operands | `WNS=-0.180ns`, `TNS=-20.978ns`, 367 failing endpoints | Removed launch-time wide `z` clear paths and operand-register CE pressure. Remaining worst path was iteration completion feeding next multiply readiness. |
| 4ctx after splitting launch coordinate update | `WNS=-0.127ns`, `TNS=-10.915ns`, 230 failing endpoints | Launch no longer directly drives the 64-bit `c_re_next + step` add operands. Remaining issue was `AOP_NEXT_IM` doing iteration increment/compare and re-arming the next multiply in one cycle. |
| 4ctx with first `C_CHECK_ITER` state | `WNS=0.001ns`, `TNS=0.000ns`, 0 failing endpoints | Rejected as a validated point. Hardware small-image verification failed: `17200/19200` pixels matched (`89.58%`), with many top-row pixels returning `256`. |
| 4ctx `C_CHECK_ITER` repair attempts | `WNS=-0.765ns` to about `-0.139ns` depending on attempt | Rejected. State-qualified issue gating, ready/op clearing, and issue-skip guards put `c_state` or ready clearing into hot FPU issue/operand paths and broke timing. |
| 4ctx reordered post-processing repair, Vivado 2020.2 | `WNS=-0.037ns`, `TNS=-0.739ns`, 41 failing endpoints | Best repaired RTL so far. Moves per-context post-processing before add-result writeback so `AOP_NEXT_IM` can set `C_CHECK_ITER` last without same-cycle overwrite. Not timing-clean, so not programmed. |
| 4ctx reordered post-processing repair, Vivado 2024.2 `Performance_ExplorePostRoutePhysOpt` | `WNS=-0.253ns`, `TNS=-25.008ns`, 402 failing endpoints | Worse than the 2020.2 near-clean run. Not programmed. |
| 4ctx reordered post-processing repair, Vivado 2024.2 `Performance_Explore` | `WNS=-0.256ns`, `TNS=-22.714ns`, 391 failing endpoints | Still timing-failing. Not programmed. |
| 4ctx local issue round-robin pointer | `WNS=-0.374ns`, `TNS=-193.696ns`, 1513 failing endpoints | Rejected. Behavioral simulation passed, but timing worsened significantly. |
| 4ctx two-stage FPU issue request slicing, initial tag alignment | `WNS=0.003ns`, `TNS=0.000ns`, 0 failing endpoints | Rejected as a validated point. Hardware small-image verification failed: `17200/19200` pixels matched (`89.58%`). |
| 4ctx request slicing with corrected multiplier result tag | `WNS=0.015ns`, `TNS=0.000ns`, 0 setup failing endpoints; `WHS=0.002ns`, `THS=0.000ns` | Accepted as the first validated direct-200MHz point. Behavioral regressions passed, hardware small-image verification passed `19200/19200` (`100.00%`), and 1080p transport benchmark passed all six scenes. |

## Functional Simulation

The final 4ctx request-sliced RTL was checked without programming hardware using Vivado 2024.2 behavioral simulation:

```text
vivado.bat -mode batch -source sim_multicore_dynamic_contexts.tcl -tclargs WORKER_CONTEXTS=4
=== DYNAMIC MULTICORE TEST PASS: 192 pixels ===
```

Additional focused regressions were added and run:

```text
vivado.bat -mode batch -source sim_worker_kctx.tcl -tclargs CONTEXTS 4 ROWS 12 COLS 160 ROW_START 0 MAX_ITER 256 TIMEOUT_CYCLES 10000000
=== WORKER KCTX TEST PASS: 160 pixels ===

vivado.bat -mode batch -source sim_worker_kctx.tcl -tclargs CONTEXTS 4 ROWS 12 COLS 160 ROW_START 9 MAX_ITER 256 TIMEOUT_CYCLES 10000000
=== WORKER KCTX TEST PASS: 160 pixels ===

vivado.bat -mode batch -source sim_multicore_dynamic_contexts.tcl -tclargs WORKER_CONTEXTS 4 ROWS 12 COLS 160 MAX_ITER 256 CORE_FIFO_DEPTH 4096 TIMEOUT_CYCLES 30000000
=== DYNAMIC MULTICORE TEST PASS: 1920 pixels ===
```

The `160x120`, `max_iter=256`, `CORE_FIFO_DEPTH=4096` simulation progressed to `10240/19200` pixels without mismatches before hitting the practical simulation-time limit. This gave useful extra coverage, but the final signoff was the hardware HW/SW verification below.

The important functional fix was correcting the kctx multiplier result tag alignment after issue request slicing. The FPU latency probe showed `fp_mul` produces a one-cycle valid output pulse that lined up with `MUL_LAT=6` in the request-sliced worker, while `fp_add` remained aligned at `ADD_LAT=9`. Earlier `MUL_LAT=7/8` attempts captured the following zero-result cycle under some high-iteration pixels.

## Validated 200 MHz Hardware Result

The final candidate was built with:

```text
vivado.bat -mode batch -source build_fp64_200mhz.tcl -tclargs 4
```

Timing and utilization:

| Metric | Result |
|---|---:|
| Clock | `clk_200`, `5.000ns` period |
| Setup | `WNS=0.015ns`, `TNS=0.000ns`, 0 failing endpoints |
| Hold | `WHS=0.002ns`, `THS=0.000ns`, 0 failing endpoints |
| LUT | `20288 / 41000` (`49.48%`) |
| FF | `17202 / 82000` (`20.98%`) |

The bitstream was programmed through Vivado 2024.2 `hw_server` on `127.0.0.1:3122` plus CH347 XVC on `127.0.0.1:2542`:

```text
vivado.bat -mode batch -source program.tcl -tclargs ./fp64_200mhz_ctx4_proj/mandelbrot_fp64_200mhz_ctx4.runs/impl_1/top.bit
Programming complete
```

Small-image hardware verification passed exactly:

```text
python python/mandelbrot_host.py --width 160 --height 120 --max-iter 256 --center -0.5 0.0 --step 0.005 --output python/hw_xc7k70t_ctx4_200mhz_small_verify.png --verify --quiet
FPGA elapsed: 0.158s (121376.49 pixels/s)
HW vs SW: 19200/19200 match (100.00%)
```

Fresh 10-run 1080p host-tiled benchmark, tile `1920x120`, 12 Mbaud UART. The speedup column is computed against the validated 100MHz 4ctx measurements (`4.683/5.782/9.836/17.677/44.146/19.965s`):

| Scene | Transport pass | Retry events | Mean FPGA s | Mean pps | vs 100MHz 4ctx |
|---|---:|---:|---:|---:|---:|
| fast escape @128 | `10/10` | `6` | `5.072` | `413592.02` | `0.923x` |
| standard @64 | `10/10` | `6` | `5.066` | `414046.70` | `1.141x` |
| Seahorse zoom @512 | `10/10` | `6` | `7.879` | `273303.15` | `1.248x` |
| deep tendrils @8192 | `10/10` | `3` | `12.820` | `162504.12` | `1.379x` |
| deep mini-brot @8192 | `10/10` | `2` | `31.625` | `65709.99` | `1.396x` |
| deep Seahorse @1024 | `10/10` | `0` | `13.886` | `149325.97` | `1.438x` |

Fast escape is not faster because request slicing, retries, and launch/output overhead dominate the low-iteration workload. Standard and deep scenes are faster because more of the workload benefits from the 200 MHz compute clock.

## Current Interpretation

The 200 MHz path now has a validated 4ctx functional/timing point:

1. The accepted candidate is timing-clean at 200 MHz and passes hardware HW/SW verification.
2. The key control-path improvement is two-stage FPU issue request slicing without latching the 64-bit operands in the request stage. Latching the operands increased timing pressure and was rejected.
3. The key functional fix is `mandelbrot_core_worker_kctx.v` tag alignment with `MUL_LAT=6`, `ADD_LAT=9` in the request-sliced path.
4. The design is now the repository default, with the caveat that fast-escape scenes can be slower than the 100MHz 4ctx reference.
5. The direct-200MHz mode improves standard and deep/compute-heavy scenes in the measured set, where the 10-run benchmark shows `1.14x` to `1.44x` improvement over the 100 MHz 4ctx data.
6. The partial-product multiplier still causes Vivado DPOP-2 style warnings and may not be the final best DSP implementation.

## Recommended Next Changes

For future 200 MHz work:

1. Keep `build_fp64.tcl` as the direct-200MHz 4ctx default unless new data invalidates it.
2. Preserve `build_fp64_100mhz.tcl` as the 100MHz reference point for shallow-scene comparisons.
3. Re-run worker-only and multicore behavioral simulations after any worker/FPU latency or issue-control changes.
4. Treat `CORE_FIFO_DEPTH=4096` as the hardware-equivalent dynamic multicore simulation setting for 160-wide or larger rows; the old 128-depth test setting creates artificial collector pressure.
5. Consider replacing the inferred partial-product multiplier with explicit or better-guided DSP48E1 pipelining.
6. Run multi-run stability benchmarks before claiming final production performance numbers.

## Decision

The direct 200 MHz 4ctx experiment now has a valid timing-clean and hardware-verified performance point.

The repository default is now the validated direct-200MHz 4ctx build. The 100MHz 4ctx build remains available as an explicit reference because it is faster on the fast-escape shallow scene.
