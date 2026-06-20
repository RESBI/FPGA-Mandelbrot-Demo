# Worker Count Scaling Experiment

This note records the 6-worker and 8-worker scaling attempt on the HVS `xc7k70t` board. After the 6-worker timing fix and hardware benchmark, the default architecture is direct-200MHz, 6 workers, 4 contexts per worker.

## Build Matrix

| Build | Clock | Workers | Contexts/worker | Result | Timing | Resource summary |
|---|---:|---:|---:|---|---|---|
| Default baseline | 200 MHz direct | 4 | 4 | Validated on board | `WNS=0.015ns`, `TNS=0.000ns` | 20288 LUT, 17202 FF, 37 DSP48E1, 9.5 BRAM tiles |
| Worker scale candidate, original | 200 MHz direct | 6 | 4 | Routed but not valid for board test | `WNS=-0.165ns`, `TNS=-8.713ns` | 30301 LUT, 25282 FF, 97 DSP48E1, 13.5 BRAM tiles |
| Worker scale candidate, fixed | 200 MHz direct | 6 | 4 | Bitstream generated, programmed, benchmarked | `WNS=0.003ns`, `TNS=0.000ns` | 29891 LUT, 25501 FF, 97 DSP48E1, 13.5 BRAM tiles |
| Worker scale candidate | 200 MHz direct | 8 | 4 | Placement failed | LUT/slice packing over-utilized | 40635 synth LUT, 33366 FF, 129 DSP48E1, 17.5 BRAM tiles |
| Worker scale fallback | 100 MHz MMCM | 6 | 4 | Bitstream generated, programmed, benchmarked | `WNS=1.586ns`, `TNS=0.000ns` | 29641 LUT, 25278 FF, 97 DSP48E1, 13.5 BRAM tiles |
| Worker scale fallback | 100 MHz MMCM | 8 | 4 | Bitstream generated, programmed, benchmarked | `WNS=1.746ns`, `TNS=0.000ns` | 39265 LUT, 33364 FF, 129 DSP48E1, 17.5 BRAM tiles |

## Simulation

The dynamic multicore testbench was parameterized by `CORE_COUNT` and run for 6 and 8 workers with 4 contexts per worker.

| Configuration | Command shape | Result |
|---|---|---|
| 6 workers, 4ctx | `sim_multicore_dynamic_contexts.tcl -tclargs WORKER_CONTEXTS 4 CORE_COUNT 6 ROWS 12 COLS 160 MAX_ITER 256 CORE_FIFO_DEPTH 4096 TIMEOUT_CYCLES 30000000` | PASS, `1920` pixels |
| 8 workers, 4ctx | `sim_multicore_dynamic_contexts.tcl -tclargs WORKER_CONTEXTS 4 CORE_COUNT 8 ROWS 12 COLS 160 MAX_ITER 256 CORE_FIFO_DEPTH 4096 TIMEOUT_CYCLES 30000000` | PASS, `1920` pixels |

## 1080p Benchmark Results

The 100MHz worker-count fallbacks were programmed successfully and benchmarked with:

```powershell
python "python\host_tile_stability_benchmark.py" --runs 10 --tile-width 1920 --tile-height 120 --tile-retries 3 --run-tag workers6_100mhz --summary-name host_tile_stability_results_workers6_100mhz.md
python "python\host_tile_stability_benchmark.py" --runs 10 --tile-width 1920 --tile-height 120 --tile-retries 3 --run-tag workers8_100mhz --summary-name host_tile_stability_results_workers8_100mhz.md
```

After the 6-worker 200MHz timing fix, the direct-200MHz 6-worker build was also programmed successfully and benchmarked with:

```powershell
python "python\host_tile_stability_benchmark.py" --runs 10 --tile-width 1920 --tile-height 120 --tile-retries 3 --run-tag workers6_200mhz_fixed --summary-name host_tile_stability_results_workers6_200mhz_fixed.md
```

Result file:

```text
python/host_tile_stability_bench/host_tile_stability_results_workers6_100mhz.md
python/host_tile_stability_bench/host_tile_stability_results_workers8_100mhz.md
python/host_tile_stability_bench/host_tile_stability_results_workers6_200mhz_fixed.md
```

| Scene | 4w 100MHz mean s | 6w 100MHz mean s | 8w 100MHz mean s | 4w 200MHz mean s | 6w 200MHz fixed mean s | 6w 200MHz vs 4w 200MHz | 6w 200MHz vs 8w 100MHz |
|---|---:|---:|---:|---:|---:|---:|---:|
| fast escape @128 | `4.683` | `5.027` | `5.141` | `5.072` | `4.641` | `1.093x` | `1.108x` |
| standard @64 | `4.680` | `5.253` | `4.805` | `5.066` | `4.636` | `1.093x` | `1.036x` |
| Seahorse zoom @512 | `9.958` | `9.672` | `7.450` | `7.879` | `5.715` | `1.379x` | `1.304x` |
| deep tendrils @8192 | `17.923` | `16.971` | `12.660` | `12.820` | `8.567` | `1.496x` | `1.478x` |
| deep mini-brot @8192 | `44.148` | `42.313` | `31.785` | `31.625` | `20.963` | `1.509x` | `1.516x` |
| deep Seahorse @1024 | `19.966` | `19.070` | `14.319` | `13.886` | `9.668` | `1.436x` | `1.481x` |

The 6-worker 100MHz result is only modestly faster than 4-worker 100MHz on compute-heavy scenes, and slower on the fast/standard scenes. The 8-worker 100MHz result improves compute-heavy scenes by about `1.39x-1.42x` over 4-worker 100MHz, but is only roughly comparable with the previous 4-worker direct-200MHz default. The fixed 6-worker 200MHz result is the best measured point in this set: it beats the previous 4-worker 200MHz default by `1.38x-1.51x` on compute-heavy scenes and also beats 8-worker 100MHz by `1.30x-1.52x` on those scenes.

## 6-Worker 200MHz Timing Fix

The original 6-worker 200MHz build routed but failed timing:

```text
WNS=-0.165ns, TNS=-8.713ns, 168 setup failing endpoints
```

The worst path was not in the FP64 multiplier or adder datapath. It was dominated by routing in the dynamic row dispatcher:

```text
u_core/g_dynamic_sched.u_dispatch/next_row_reg[0]
  -> u_core/g_dynamic_sched.u_dispatch/row_stride_bus_reg[*]/CE
Data Path Delay = 4.767ns, logic = 0.944ns, route = 3.823ns (80.2%)
```

A second class of near-critical paths crossed from dispatcher row assignment into worker row-coordinate setup, and another class remained inside the k-context worker commit/update control. These paths were also route-dominated.

The fix used two small RTL cuts instead of changing the compute algorithm:

| Change | Reason |
|---|---|
| Removed the active-cycle `row_stride_bus[i*16 +: 16] <= rows` assignment from `work_dispatch_dynamic_rows` | In dynamic mode the row stride is constant for the whole frame and already written on `start`; rewriting it on each row assignment created a wide CE/control path and caused the worst timing violation. |
| Added `S_INIT_LATCH` in `mandelbrot_core_worker_kctx` | Worker start inputs are now latched locally first; FP constants such as `row_start_fp` and `row_stride_fp` are generated in the next cycle, cutting the dispatcher-to-worker combinational path. |

The post-fix validation path was:

| Step | Result |
|---|---|
| 6-worker dynamic multicore behavioral sim | PASS, `1920` pixels |
| 6-worker direct-200MHz implementation | Bitstream generated |
| Post-route physopt timing | `WNS=0.003ns`, `TNS=0.000ns`, `WHS=0.042ns`, `THS=0.000ns` |
| Hardware programming | PASS, `xc7k70t_0` programmed through `hw_server:3122` + CH347 XVC `2542` |
| 1080p 10-run benchmark | PASS for all scenes |

## 8-Worker Programming Note

The 8-worker 100MHz bitstream used for the board test was:

```text
fp64_100mhz_c8_ctx4_proj/mandelbrot_fp64_100mhz_c8_ctx4.runs/impl_1/top.bit
```

An initial programming attempt through `hw_server` on `127.0.0.1:3122` and CH347 XVC on `127.0.0.1:2542` reported:

```text
ERROR: [Labtools 27-2269] No devices detected on target 127.0.0.1:3122/xilinx_tcf/Xilinx/127.0.0.1:2542.
```

The XVC port itself was reachable. The successful fix was to restart the dedicated Vivado `hw_server` on port `3122`, then program the same bitstream again. Programming then detected `xc7k70t_0` and completed successfully.

Actions tried before the successful retry:

| Attempt | Result |
|---|---|
| Confirmed `127.0.0.1:3122` hw_server port | Open |
| Confirmed `127.0.0.1:2542` XVC port | Open after restarting XVCD |
| Removed duplicate `ch347_xvcd` processes | Still no JTAG device detected |
| Restarted XVCD at default 30MHz-equivalent path | Still no JTAG device detected |
| Restarted XVCD with `-s 10` | Still no JTAG device detected |
| Tried CH347 index `-i 1` | XVCD did not start/listen |
| Restored CH347 index `-i 0`, speed `-s 10` | XVC listened, but JTAG device still not detected until `hw_server` was restarted |
| Restarted dedicated Vivado `hw_server` on `127.0.0.1:3122` | `xc7k70t_0` detected and programming succeeded |

Re-run command:

```powershell
& "Z:\Softwares\Xilinx\Vivado\2024.2\bin\vivado.bat" -mode batch -source "program.tcl" -tclargs "C:/Users/Administrator/Desktop/FPGA/Vibe/Mandelbrot/fp64_100mhz_c8_ctx4_proj/mandelbrot_fp64_100mhz_c8_ctx4.runs/impl_1/top.bit"
python "python\host_tile_stability_benchmark.py" --runs 10 --tile-width 1920 --tile-height 120 --tile-retries 3 --run-tag workers8_100mhz --summary-name host_tile_stability_results_workers8_100mhz.md
```

## Conclusion

Increasing worker count by instantiating more current 4-context workers now has one useful direct-200MHz point on `xc7k70t`:

| Candidate | Conclusion |
|---|---|
| 6 workers at 200MHz, original | Near fit, but timing failed because of route-dominated dispatcher and worker-control paths. |
| 6 workers at 200MHz, fixed | Timing-clean and benchmarked; best measured point in this matrix. |
| 8 workers at 200MHz | Too close to device limits; placement fails. |
| 6 workers at 100MHz | Valid and benchmarked, but only modestly improves 100MHz compute-heavy scenes and remains slower than the 6-worker 200MHz default. |
| 8 workers at 100MHz | Valid and benchmarked; large gain versus 4-worker 100MHz compute-heavy scenes, but slower than the 6-worker 200MHz default on compute-heavy scenes. |

The fixed direct-200MHz 6-worker build is the best validated performance point so far, at the cost of significantly higher area than the previous 4-worker default: 29891 LUTs, 25501 FFs, 97 DSP48E1, and 13.5 BRAM tiles.
