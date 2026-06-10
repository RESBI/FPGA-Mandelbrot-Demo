# Dynamic Idle-Core-Priority Scheduling Report

This report documents the dynamic idle-core scheduler added beside the existing static interleaved-row scheduler. The implemented mode assigns one full row at a time to the first available Mandelbrot worker, records row ownership in hardware, and preserves the existing raster-order host protocol.

## Implementation Summary

| Item | Status |
|---|---|
| Dynamic dispatcher | Implemented in `rtl/work_dispatch_dynamic_rows.v`. |
| Dynamic result collector | Implemented in `rtl/raster_collect_dynamic_rows.v`. |
| Compile-time mode switch | `SCHED_MODE` in `mandelbrot_multicore` and `top`. |
| Static default | Preserved as `SCHED_MODE=0`. |
| Dynamic optional build | `build_fp64_dynamic.tcl`, `SCHED_MODE=1`. |
| Dynamic simulation | `sim_multicore_dynamic.tcl`. |
| Host protocol | Unchanged raster-order 16-bit pixel stream. |

The default board build remains the static interleaved-row design. Dynamic mode is available for scheduler experiments and row-level load-balance evaluation.

## Current Static Baseline

Static mode assigns rows once at frame start:

| Core | Rows |
|---:|---|
| 0 | `0, 4, 8, ...` |
| 1 | `1, 5, 9, ...` |
| 2 | `2, 6, 10, ...` |
| 3 | `3, 7, 11, ...` |

`raster_merge_static_rows.v` restores output order by using:

```text
source_core = row % CORE_COUNT
```

This is simple and efficient, but a core can finish early and remain idle if another core owns heavier rows.

## Dynamic Scheduler Design

Dynamic mode reuses the existing `mandelbrot_core_worker` instead of introducing a new arithmetic worker. Each dynamic job is one full-width row:

```text
row_start = assigned_row
row_stride = rows
```

Since `row + row_stride >= rows` after that row, the worker finishes after producing exactly one row. The dispatcher then gives it another row if work remains.

The dispatcher tracks active cores internally. This is necessary because the worker latches `start` before `busy` rises, and `done` can remain visible long enough to confuse a naive `!busy` scheduler. `work_dispatch_dynamic_rows.v` therefore marks a core active immediately when it issues a job and waits for `done` to return low before reusing that core.

## Dynamic Result Collection

The host protocol still expects strict raster order with no row tags. Dynamic completion order is therefore hidden inside the FPGA.

`work_dispatch_dynamic_rows.v` writes a row-owner update whenever it issues a row:

```text
owner[row] = core_id
```

`raster_collect_dynamic_rows.v` walks the output raster order. For the current row, it waits until the owner entry exists, selects the recorded core FIFO, and drains pixels from that FIFO.

```mermaid
flowchart LR
    SCHED[work_dispatch_dynamic_rows] -->|row job| C0[worker 0]
    SCHED -->|row job| C1[worker 1]
    SCHED -->|row job| C2[worker 2]
    SCHED -->|row job| C3[worker 3]
    SCHED --> OWNER[[row owner table]]
    C0 --> F0[core FIFO 0]
    C1 --> F1[core FIFO 1]
    C2 --> F2[core FIFO 2]
    C3 --> F3[core FIFO 3]
    OWNER --> COLL[raster_collect_dynamic_rows]
    F0 --> COLL
    F1 --> COLL
    F2 --> COLL
    F3 --> COLL
    COLL --> OUT[shared raster-order FIFO]
```

`DYNAMIC_OWNER_DEPTH` bounds the owner table. The default is `4096`, which covers the validated 1080p image height. Static mode does not use this table.

## Mode Switching

`mandelbrot_multicore` parameters:

| Parameter | Value | Meaning |
|---|---:|---|
| `SCHED_MODE` | `0` | Static interleaved rows, default. |
| `SCHED_MODE` | `1` | Dynamic idle-core rows. |
| `DYNAMIC_OWNER_DEPTH` | `4096` | Dynamic owner-table depth in rows. |

`top` forwards the same parameters to `mandelbrot_multicore`, so top-level builds can switch modes with Vivado generics.

Build scripts:

| Script | Mode |
|---|---|
| `build_fp64.tcl` | Static default, `SCHED_MODE=0`. |
| `build_fp64_dynamic.tcl` | Dynamic, `SCHED_MODE=1`. |

## Validation Results

| Command | Result |
|---|---|
| `vivado -mode batch -source sim_fp.tcl` | Pass. |
| `vivado -mode batch -source sim_core.tcl` | `=== CORE TEST PASS ===` |
| `vivado -mode batch -source sim_multicore.tcl` | `=== MULTICORE TEST PASS: 192 pixels ===` |
| `vivado -mode batch -source sim_multicore_dynamic.tcl` | `=== DYNAMIC MULTICORE TEST PASS: 192 pixels ===` |
| `vivado -mode batch -source build_fp64.tcl` | Static bitstream generated, timing met. |
| `vivado -mode batch -source build_fp64_dynamic.tcl` | Dynamic bitstream generated, timing met. |

Routed timing:

| Build | Scheduler | WNS | TNS | WHS | THS |
|---|---|---:|---:|---:|---:|
| `build_fp64.tcl` | Static interleaved rows | 0.358 ns | 0.000 ns | 0.024 ns | 0.000 ns |
| `build_fp64_dynamic.tcl` | Dynamic idle-core rows | 0.269 ns | 0.000 ns | 0.027 ns | 0.000 ns |

Placed utilization:

| Resource | Static | Dynamic |
|---|---:|---:|
| Slice LUTs | 8599 / 17600, 48.86% | 8717 / 17600, 49.53% |
| Slice Registers | 9807 / 35200, 27.86% | 10142 / 35200, 28.81% |
| DSP48E1 | 38 / 80, 47.50% | 38 / 80, 47.50% |
| Block RAM Tile | 8.5 / 60, 14.17% | 9.5 / 60, 15.83% |
| RAMB18 | 1 / 120, 0.83% | 3 / 120, 2.50% |

## Expected Performance Impact

Dynamic scheduling can only recover row-level load imbalance. It does not change the per-worker Mandelbrot FSM, FP latency, or UART output limit.

At 576000 baud, the UART ceiling is:

```text
576000 / 10 / 2 = 28800 pixels/s
```

Measured static 4-core scenes already show about `3.5x-3.6x` scaling on compute-bound cases, so the normal measured-scene upper bound for row-level dynamic scheduling is modest:

| Scene | Current 4-core 576k | Dynamic upper bound | Upper speedup |
|---|---:|---:|---:|
| Fast escape @128 | 28508.56 pps | UART cap 28800 pps | 1.01x |
| Standard @64 | 28508.82 pps | UART cap 28800 pps | 1.01x |
| Seahorse zoom @512 | 27921.47 pps | UART cap 28800 pps | 1.03x |
| Deep tendrils @8192 | 22079.29 pps | about 24393 pps | 1.10x |
| Deep mini-brot @8192 | 8852.78 pps | about 9749 pps | 1.10x |
| Deep seahorse @1024 | 20600.46 pps | about 22834 pps | 1.11x |

The dynamic scheduler is more valuable for highly uneven row-cost distributions, future higher core counts, faster output transports, and future tile-level scheduling.

## 1080p Board Benchmark Results

The dynamic scheduler bitstream was programmed with:

```bash
vivado -mode batch -source program.tcl -tclargs ./fp64_dynamic_proj/mandelbrot_fp64_dynamic.runs/impl_1/top.bit
```

All six 1080p scenes rendered successfully through the unchanged 576000 baud host path.

| Scene | Static 4-core 576k | Dynamic 4-core 576k | Dynamic throughput | Dynamic vs static |
|---|---:|---:|---:|---:|
| Fast escape @128 | 72.736 s | 72.721 s | 28514.47 pps | 1.000x |
| Standard @64 | 72.735 s | 72.719 s | 28515.41 pps | 1.000x |
| Seahorse zoom @512 | 74.265 s | 74.253 s | 27926.03 pps | 1.000x |
| Deep tendrils @8192 | 93.916 s | 93.907 s | 22081.36 pps | 1.000x |
| Deep mini-brot @8192 | 234.231 s | 234.137 s | 8856.36 pps | 1.000x |
| Deep seahorse @1024 | 100.658 s | 100.691 s | 20593.74 pps | 1.000x |

Generated benchmark images:

| Scene | Output file |
|---|---|
| Fast escape @128 | `python/dyn_1080p_fast_escape_i128.png` |
| Standard @64 | `python/dyn_1080p_standard_i64.png` |
| Seahorse zoom @512 | `python/dyn_1080p_seahorse_zoom_i512_s5e-6.png` |
| Deep tendrils @8192 | `python/dyn_1080p_deep_tendrils_i8192_s1e-9.png` |
| Deep mini-brot @8192 | `python/dyn_1080p_deep_minibrot_i8192_s1e-9.png` |
| Deep seahorse @1024 | `python/dyn_1080p_deep_seahorse_i1024_s1e-8.png` |

Interpretation:

| Observation | Meaning |
|---|---|
| UART-bound scenes are unchanged | Fast escape and standard views already sit at the 576000 baud pixel ceiling. |
| Mixed scenes are unchanged | Seahorse zoom and deep seahorse have little row-level tail imbalance to recover before hitting other limits. |
| Compute-bound scenes are unchanged | Deep tendrils and mini-brot remain limited by worker-internal compute, not by static row assignment imbalance. |
| Dynamic mode is functionally validated | The row-owner collector preserves raster-order output for full 1080p frames. |

These results confirm the model: the implemented dynamic row scheduler is useful as an architectural option and validation of the dispatch/collect boundary, but it is not a performance win for the current measured scenes. Bigger gains require either highly row-imbalanced views, tile-level dynamic scheduling, more cores, transport upgrades, or worker de-bubbling.

## Limitations

| Limitation | Detail |
|---|---|
| Row granularity | Current dynamic mode schedules full rows, not tiles. |
| Strict raster output | The collector can still wait for an earlier row before emitting later rows. |
| Owner depth | Dynamic mode supports rows below `DYNAMIC_OWNER_DEPTH`; default is 4096. |
| Worker initialization overhead | Each row is a separate worker job, so each row repeats worker initialization. This is acceptable for 1080p rows but not ideal for very narrow images. |
| No FP de-bubbling | Per-worker FP issue bubbles remain unchanged. |
| No UART relief | UART-bound scenes cannot improve materially. |

## Future Direction

The implemented compatible dynamic mode is a useful stepping stone. The next larger architectural step is a tagged row/tile protocol where the FPGA can emit completed chunks out of order and the host reorders them. That would remove strict raster collector stalls and make dynamic tile scheduling practical.

Recommended next steps:

| Priority | Work |
|---:|---|
| 1 | Board-benchmark static vs dynamic on artificial row-imbalanced scenes. |
| 2 | Add dynamic-mode host/build documentation for programming the dynamic bitstream. |
| 3 | Prototype `CHUNK_ROWS > 1` to reduce row-job initialization overhead. |
| 4 | Define protocol v2 with tagged row/tile packets. |
| 5 | Move from row-level jobs to tile-level jobs after tagged output exists. |

## Conclusion

Dynamic idle-core row scheduling is now implemented, switchable, simulated, and synthesizable. The default stable design remains static interleaved rows. Dynamic mode preserves host compatibility and adds only modest resources, but its expected performance gain on current 576000-baud measured scenes is limited because UART and per-worker FP latency remain the dominant constraints.
