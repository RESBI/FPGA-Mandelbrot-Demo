# Worker Count Scaling Experiment

This note records the 6-worker and 8-worker scaling attempt on the HVS `xc7k70t` board. The default architecture remains direct-200MHz, 4 workers, 4 contexts per worker.

## Build Matrix

| Build | Clock | Workers | Contexts/worker | Result | Timing | Resource summary |
|---|---:|---:|---:|---|---|---|
| Default baseline | 200 MHz direct | 4 | 4 | Validated on board | `WNS=0.015ns`, `TNS=0.000ns` | 20288 LUT, 17202 FF, 37 DSP48E1, 9.5 BRAM tiles |
| Worker scale candidate | 200 MHz direct | 6 | 4 | Routed but not valid for board test | `WNS=-0.165ns`, `TNS=-8.713ns` | 30301 LUT, 25282 FF, 97 DSP48E1, 13.5 BRAM tiles |
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

6-worker and 8-worker 100MHz were programmed successfully and benchmarked with:

```powershell
python "python\host_tile_stability_benchmark.py" --runs 10 --tile-width 1920 --tile-height 120 --tile-retries 3 --run-tag workers6_100mhz --summary-name host_tile_stability_results_workers6_100mhz.md
python "python\host_tile_stability_benchmark.py" --runs 10 --tile-width 1920 --tile-height 120 --tile-retries 3 --run-tag workers8_100mhz --summary-name host_tile_stability_results_workers8_100mhz.md
```

Result file:

```text
python/host_tile_stability_bench/host_tile_stability_results_workers6_100mhz.md
python/host_tile_stability_bench/host_tile_stability_results_workers8_100mhz.md
```

| Scene | 4w 100MHz mean s | 6w 100MHz mean s | 8w 100MHz mean s | 6w vs 4w 100MHz | 8w vs 4w 100MHz | 4w 200MHz mean s | 6w 100MHz vs 4w 200MHz | 8w 100MHz vs 4w 200MHz |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fast escape @128 | `4.683` | `5.027` | `5.141` | `0.932x` | `0.911x` | `5.072` | `1.009x` | `0.987x` |
| standard @64 | `4.680` | `5.253` | `4.805` | `0.891x` | `0.974x` | `5.066` | `0.964x` | `1.054x` |
| Seahorse zoom @512 | `9.958` | `9.672` | `7.450` | `1.030x` | `1.337x` | `7.879` | `0.815x` | `1.058x` |
| deep tendrils @8192 | `17.923` | `16.971` | `12.660` | `1.056x` | `1.416x` | `12.820` | `0.755x` | `1.013x` |
| deep mini-brot @8192 | `44.148` | `42.313` | `31.785` | `1.043x` | `1.389x` | `31.625` | `0.747x` | `0.995x` |
| deep Seahorse @1024 | `19.966` | `19.070` | `14.319` | `1.047x` | `1.394x` | `13.886` | `0.728x` | `0.970x` |

The 6-worker 100MHz result is only modestly faster than 4-worker 100MHz on compute-heavy scenes, and slower on the fast/standard scenes. The 8-worker 100MHz result improves compute-heavy scenes by about `1.39x-1.42x` over 4-worker 100MHz, but is only roughly comparable with the current 4-worker direct-200MHz default: slightly faster on Seahorse zoom and deep tendrils, essentially tied on deep mini-brot, and slower on deep Seahorse.

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

Increasing worker count by instantiating more current 4-context workers is not a good direct-200MHz path on `xc7k70t`:

| Candidate | Conclusion |
|---|---|
| 6 workers at 200MHz | Near fit, but timing fails; not valid for board benchmark. |
| 8 workers at 200MHz | Too close to device limits; placement fails. |
| 6 workers at 100MHz | Valid and benchmarked, but only modestly improves 100MHz compute-heavy scenes and remains slower than the 4-worker 200MHz default. |
| 8 workers at 100MHz | Valid and benchmarked; large gain versus 4-worker 100MHz compute-heavy scenes, but only roughly comparable to the 4-worker 200MHz default. |

The current direct-200MHz 4-worker default remains the best validated default because it is timing-clean at 200MHz, uses much less area than 8 workers, and is competitive with or faster than 8-worker 100MHz on the deep 1080p benchmark set.
