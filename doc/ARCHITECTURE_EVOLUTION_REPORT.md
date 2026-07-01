# Architecture Evolution And Optimization Report

This report explains the design thinking behind the Mandelbrot FPGA accelerator and summarizes how the architecture evolved from the initial single-core UART renderer to the current VMC_RTSB ZU4EV 12-worker FP64 implementation. Stage-specific details are intentionally linked to the focused reports instead of duplicated in full.

## Related Stage Reports

| Stage | Report | Scope |
|---|---|---|
| Detailed current architecture | [ARCHITECTURE.md](ARCHITECTURE.md) | Full ../RTL/software architecture, protocol, verification, timing, and current performance. |
| 100 MHz timing closure | [PERFORMANCE_100MHZ.md](PERFORMANCE_100MHZ.md) | FP64 pipeline changes, 50 MHz effective to true 100 MHz migration, timing and performance impact. |
| UART baudrate optimization | [UART_BAUDRATE_BENCHMARK.md](UART_BAUDRATE_BENCHMARK.md) | CP2102 baudrate tests, 500000 baud selection, UART-limited benchmark impact. |
| UART baudrate deep investigation | [UART_BAUDRATE_INVESTIGATION.md](UART_BAUDRATE_INVESTIGATION.md) | Raw-probe integer-divider tests, TX-only isolation, 576000 candidate. |
| UART timing analysis | [UART_TIMING_ANALYSIS.md](UART_TIMING_ANALYSIS.md) | Single-sample RX timing, CP2102 drift, margin analysis, root cause of high-baud failures. |
| FP64 boundary differences | [FP64_BOUNDARY_DIFFERENCE_ANALYSIS.md](FP64_BOUNDARY_DIFFERENCE_ANALYSIS.md) | Truncation vs RNE, chaotic amplification, boundary pixel trace, difference classification. |
| Dynamic idle-core scheduling | [DYNAMIC_IDLE_CORE_SCHEDULING.md](DYNAMIC_IDLE_CORE_SCHEDULING.md) | Optional row-level dynamic scheduler, result collector, mode switching, validation, and limits. |
| Multi-core feasibility | [MULTICORE_FEASIBILITY.md](MULTICORE_FEASIBILITY.md) | Resource model, scheduler alternatives, output-order constraints, expected scaling. |
| Implemented 4-core design | [MULTICORE_4CORE_ARCHITECTURE.md](MULTICORE_4CORE_ARCHITECTURE.md) | Final 4-core architecture, modular dispatch/merge boundary, validation, 1080p benchmark results. |
| Abandoned N-context worker experiments | [CONTEXT_WORKER_ARCHITECTURE_REPORT.md](CONTEXT_WORKER_ARCHITECTURE_REPORT.md) | Generic scoreboard 4/8ctx and ring/lookahead experiments; behavioral pass but not deployable on xc7z010. |
| Direct 200 MHz closure | [200MHZ_ATTEMPT_REPORT.md](200MHZ_ATTEMPT_REPORT.md) | 4ctx direct-clock timing closure, functional failure analysis, request slicing, tag-latency fix, and hardware benchmark. |
| Worker-count scaling | [WORKER_COUNT_SCALING.md](WORKER_COUNT_SCALING.md) | 6/8-worker build, timing, 6-worker 200MHz timing fix, and hardware benchmark comparison. |
| ZU4EV 200 MHz optimization | [VMC_RTSB_ZU4EV_200MHZ_OPT_REPORT.md](VMC_RTSB_ZU4EV_200MHZ_OPT_REPORT.md) | VMC_RTSB ZU4EV board adaptation, single-ended 200 MHz clocking, UART bring-up, 12-worker/8-context scaling, timing/resource data, and 1080p benchmark update. |
| Historical notes | [DESIGN.md](DESIGN.md) | Earlier design notes and historical context. |

## Final Current State

| Item | Current Value |
|---|---:|
| FPGA | Xilinx Zynq UltraScale+ EV `xczu4ev-sfvc784-1-i` |
| Board clock input | 200 MHz single-ended `sys_clk` on `E12` |
| Internal system clock | Direct 200 MHz (`DIRECT_200MHZ=1`) |
| Floating-point mode | FP64 |
| Compute cores | 12 workers |
| Worker contexts | 8 per worker |
| Default scheduler | Dynamic idle-core rows |
| Mandelbrot workers | 12 |
| Effective worker rate | 200 MHz per worker, `FP_CE_DIV=1` |
| Main build | `build_fp64.tcl`, `CORE_COUNT=12`, `WORKER_CONTEXTS=8` |
| UART | 12000000 baud, 8N1, fractional-NCO RX/TX |
| Host serial port default | `COM6` |
| Programming link | Vivado hardware auto-connect, target matched by `*xczu4*` |
| Host protocol | Unchanged raster-order response stream |
| Pixel format | 16-bit little-endian iteration count |
| Largest validated frame | 1920x1080 |
| Current ZU4EV board build status | Full FP64 bitstream builds cleanly |
| Current ZU4EV timing/utilization | `WNS=0.148ns`, `TNS=0.000ns`; 85171 / 87840 CLB LUTs, 71453 / 175680 registers, 121 / 728 DSP48E2, 25.5 / 128 BRAM tiles |
| Most relevant historical reference | XC7K70T direct-200MHz 6-worker/4-context point from [WORKER_COUNT_SCALING.md](WORKER_COUNT_SCALING.md) |

## Initial Architecture Design Thinking

The original design goal was not maximum theoretical Mandelbrot throughput. It was a board-debuggable, end-to-end FPGA accelerator that could accept a complete image command from a PC, compute pixels in hardware, and return a file-renderable image with minimal host-side assumptions.

The initial architecture therefore favored these priorities:

| Priority | Design Choice | Reason |
|---|---|---|
| Simple bring-up | UART command/response protocol | UART is easy to probe, debug, and drive from Python on Windows. |
| Low memory use | Streaming pixels instead of frame buffering | A full 1080p frame at 16 bits/pixel is about 4 MiB, unnecessary for a serial output path. |
| Deterministic validation | Raster-order pixel stream | Host can render directly and compare against a software reference without coordinates per pixel. |
| Manageable RTL | One Mandelbrot FSM using one FP multiplier and one FP adder | Keeps area small and makes pipeline latency explicit. |
| Timing simplicity | One 100 MHz clock domain | Avoids derived-clock CDC issues between UART, parser, compute, FIFO, and TX. |
| Precision for zooms | FP64 default | FP64 supports visually useful deep zooms without committing to a much larger FP128 implementation. |

This produced the first useful architecture:

```mermaid
flowchart LR
    PC[Python Host] --> RX[UART RX]
    RX --> CMD[cmd_parser]
    CMD --> CORE[mandelbrot_core]
    CORE --> FIFO[output FIFO]
    FIFO --> TXC[tx_ctrl]
    TXC --> TX[UART TX]
    TX --> PC

    CORE --> MUL[fp_mul]
    CORE --> ADD[fp_add]
```

The important early decision was to make the hardware/software contract raster-order and image-level rather than pixel-command based. That avoided per-pixel command overhead and made it possible to later insert multi-core compute behind the same protocol.

## Baseline Single-Core Architecture

The baseline compute core used one FP multiplier and one FP adder, scheduled by a finite-state machine. Each pixel iterated:

```text
z_re_next = z_re^2 - z_im^2 + c_re
z_im_next = 2 * z_re * z_im + c_im
escape when z_re^2 + z_im^2 > 4
```

The core issued an FP operation, waited a fixed number of `fp_ce` pulses, then consumed the registered result. This made FP latency explicit and kept the Mandelbrot FSM independent from exact internal FP pipeline details.

```mermaid
flowchart TB
    INIT[Command parameters] --> COORD[Generate c_re/c_im grid]
    COORD --> PIX[Pixel loop]
    PIX --> ITER[Iteration FSM]
    ITER --> MUL[Time-shared fp_mul]
    ITER --> ADD[Time-shared fp_add]
    ITER --> OUT[Write uint16 iteration]
    OUT --> FIFO[Output FIFO]
```

The early design was resource-light. That was useful because it gave enough DSP/LUT/FF headroom to later improve timing and add multiple workers.

## Stage 1: Functional Correctness And Streaming Reliability

Before pursuing performance, the design needed to produce correct pixels and complete frames.

Key fixes included:

| Area | Issue | Resolution |
|---|---|---|
| FP add | Sign/magnitude and normalization corner cases | Added targeted tests and corrected same-sign/opposite-sign behavior. |
| FP mul | Coordinate multiplication cases | Added input and DSP product registers; verified image coordinate cases. |
| Core escape | Escape calculation used stale intermediate value | Corrected scheduling so `z_re^2 + z_im^2` uses the intended current terms. |
| Coordinate grid | Host and RTL center conventions differed | Host reference now mirrors RTL integer-center behavior. |
| TX stream | FIFO read data became valid one cycle after read | Added `S_READ_WAIT` in `tx_ctrl`. |
| Large images | `rows * cols` could truncate to 16 bits | Forced 32-bit pixel count in TX controller. |
| UART TX | Derived pseudo clock caused transfer fragility | Moved UART TX to the single `sys_clk` domain. |

Effect:

| Validation | Result |
|---|---|
| FP unit simulation | Passed targeted multiply/add cases. |
| Core simulation | Passed point/grid/full-size first-pixel regression. |
| Host reference testing | Passed randomized host/reference cases. |
| Hardware smoke | Passed known escape points. |
| Hardware image verify | Achieved 100% match on small frames. |

The outcome of this stage was a stable single-core streaming renderer with a trustworthy software reference.

## Stage 2: True 100 MHz FP64 Core

The early stable hardware used a 100 MHz physical clock but advanced the FP/core datapath every other cycle. That made timing easier but limited compute throughput.

The optimization goal was true 100 MHz operation with no core multicycle exceptions.

Detailed report: [PERFORMANCE_100MHZ.md](PERFORMANCE_100MHZ.md).

### Design Problem

Directly changing `FP_CE_DIV=2` to `FP_CE_DIV=1` failed timing badly:

| Attempt | Result |
|---|---:|
| Direct true 100 MHz | `WNS=-4.626ns`, `TNS=-593.205ns` |

The worst path was initially in `fp_add`, where decode, compare/select, alignment, and add/sub logic were too deep for 10 ns.

### Pipeline Strategy

The fix was not to change Mandelbrot math. It was to cut the long FP timing cones:

```mermaid
flowchart LR
    subgraph Add[fp_add evolution]
        A0[Input] --> A1[Decode/compare/select]
        A1 --> AR[Register]
        AR --> A2[Align + add/sub]
        A2 --> A3[Normalize/output]
    end

    subgraph Mul[fp_mul evolution]
        M0[Input] --> M1[Decode hidden mantissas]
        M1 --> MR[Register]
        MR --> M2[DSP multiply]
        M2 --> M3[Normalize/output]
    end
```

Timing closure path:

| Build | WNS | Result |
|---|---:|---|
| Old effective-50 MHz, multicycle | `2.619ns` | pass |
| Direct true 100 MHz | `-4.626ns` | fail |
| After adder cut | `-1.221ns` | fail, bottleneck moved to multiplier |
| After adder + multiplier cuts | `0.258ns` | pass |

### Stage Effect

Compute-bound workloads improved consistently by about `1.40x-1.41x`. The speedup was below an ideal `2x` because the deeper FP pipeline increased `PIPE_WAIT` from 6 to 9.

Representative 1080p impact from [PERFORMANCE_100MHZ.md](PERFORMANCE_100MHZ.md):

| Case | Old 50 MHz Effective | True 100 MHz | Speedup |
|---|---:|---:|---:|
| Deep tendrils @8192 | `478.776s` | `340.055s` | `1.41x` |
| Deep minibrot @8192 | `1198.049s` | `850.711s` | `1.41x` |
| Deep seahorse @1024 | `511.486s` | `363.254s` | `1.41x` |

UART-bound scenes barely improved, which exposed the next bottleneck.

## Stage 3: UART Baudrate Optimization

Once true 100 MHz was stable, fast scenes were capped by the serial output link.

Detailed reports: [UART_BAUDRATE_BENCHMARK.md](UART_BAUDRATE_BENCHMARK.md), [UART_BAUDRATE_INVESTIGATION.md](UART_BAUDRATE_INVESTIGATION.md), [UART_TIMING_ANALYSIS.md](UART_TIMING_ANALYSIS.md).

### Design Problem

At 460800 baud, the theoretical pixel ceiling was:

```text
460800 bits/s / 10 UART bits/byte / 2 bytes/pixel = 23040 pixels/s
```

Fast 1080p scenes were already near this ceiling.

### Initial Sweep

The 100 MHz clock allowed exact integer dividers for several candidate rates:

| Baudrate | `CLOCKS_PER_BIT` | Board Result |
|---:|---:|---|
| 1000000 | 100 | timeout |
| 800000 | 125 | timeout |
| 625000 | 160 | timeout |
| 500000 | 200 | pass |
| 460800 | 217 | previous stable baseline |

500000 baud was initially selected as the highest stable tested rate.

### Raw-Probe Deep Investigation

A follow-up investigation used `../python/uart_raw_probe.py` to dump raw byte-level responses at each integer-divided baud rate, identifying three distinct failure classes:

| Baud | CPB | FPGA actual | Symptom | Root cause |
|---:|---:|---:|---:|---|
| 500000 | 200 | 500000.00 | Pass | Exact divider |
| 520833 | 192 | 520833.33 | Pass | Exact divider |
| 523560 | 191 | 523560.21 | 1/8 corrupt frames | CP2102 baud quantisation mismatch |
| 526316 | 190 | 526315.79 | All frames byte-corrupted | CP2102 baud quantisation mismatch |
| 530000–540000 | 189–185 | ~530k–541k | Zero response | RX timing margin collapse |
| **576000** | **174** | **574712.64** | **Pass** | **Standard PC baud, clean CP2102 path** |
| 625000 | 160 | 625000.00 | Zero response | FPGA RX uplink |
| 800000 | 125 | 800000.00 | Zero response | FPGA RX uplink |
| 1000000 | 100 | 1000000.00 | Zero response | FPGA RX uplink |

A **TX-only isolation experiment** (`uart_tx_pattern_top.v`) proved definitively that the FPGA TX downlink functions correctly at 625000, 800000, and 1000000 baud — the host receives large volumes of bytes when TX is driven without depending on RX. The failures at those rates are in the **FPGA RX uplink**, caused by the single-sample architecture lacking oversampling, start-bit verification, and majority-vote sampling.

Detailed timing analysis and CP2102 baud quantisation calculations are in [UART_TIMING_ANALYSIS.md](UART_TIMING_ANALYSIS.md).

### Stage Effect

The UART ceiling moved to:

```text
576000 bits/s / 10 / 2 = 28800 pixels/s
```

Representative impact:

| Case | 460800 | 500000 | 576000 | Speedup (500k→576k) |
|---|---:|---:|---:|---:|
| 1080p standard @64 | `90.551s` | `83.510s` | `72.735s` | `1.15x` |
| 1080p Seahorse zoom @512 | — | `83.956s` | `74.265s` | `1.13x` |
| Deep compute-bound cases | unchanged | unchanged | unchanged | `1.00x` |

## Stage 4: Multi-Core Feasibility Study

The next optimization question was whether multiple FP64 Mandelbrot cores fit on the target and whether they would actually help under the unchanged UART protocol.

Detailed report: [MULTICORE_FEASIBILITY.md](MULTICORE_FEASIBILITY.md).

### Resource Reasoning

The single-core 500000 baud design used about 10 DSP48E1 blocks. The compute core accounted for roughly 9 of them.

Planning model:

```text
DSP_total(N) ~= 1 + 9 * N
```

Estimated DSP use:

| Cores | Estimated DSPs | Assessment |
|---:|---:|---|
| 2 | ~19 | easy |
| 4 | ~37 | good target |
| 6 | ~55 | possible, more timing risk |
| 8 | ~73 | high routing/timing risk |

4 cores were chosen as the direct implementation target because they were large enough to materially improve deep zooms while still leaving routing/timing headroom.

### Scheduling Reasoning

The unchanged host protocol requires a raster-order stream with no coordinate metadata. That rules out a simple out-of-order dynamic scheduler unless hardware reorders results internally.

Options considered:

| Strategy | Pros | Cons | Decision |
|---|---|---|---|
| Contiguous row bands | Simple output order | Poor balance on localized zooms | Not selected |
| Interleaved rows | Better balance, simple `row % N` merge | Still strict-order stalls possible | Selected |
| Dynamic row chunks | Better balance | Needs row IDs or more complex reorder | Future |
| Tile scheduling | Best future balance | Needs protocol support for tile IDs | Future |
| Pixel interleaving | Fine balance | Merge/control overhead too high | Not selected |

The chosen path was static interleaved rows plus a hardware raster merger.

## Stage 5: Implemented 4-Core Architecture

The final implemented design instantiates four worker cores and preserves the existing host protocol.

Detailed report: [MULTICORE_4CORE_ARCHITECTURE.md](MULTICORE_4CORE_ARCHITECTURE.md).

### Implemented Data Path

```mermaid
flowchart TB
    CMD[cmd_parser parameters] --> MC[mandelbrot_multicore]
    MC --> DISP[work_dispatch_static_rows]
    DISP --> W0[worker 0 rows 0,4,8,...]
    DISP --> W1[worker 1 rows 1,5,9,...]
    DISP --> W2[worker 2 rows 2,6,10,...]
    DISP --> W3[worker 3 rows 3,7,11,...]
    W0 --> F0[core FIFO 0]
    W1 --> F1[core FIFO 1]
    W2 --> F2[core FIFO 2]
    W3 --> F3[core FIFO 3]
    F0 --> MERGE[raster_merge_static_rows]
    F1 --> MERGE
    F2 --> MERGE
    F3 --> MERGE
    MERGE --> OFIFO[shared output FIFO]
    OFIFO --> TX[tx_ctrl + UART]
```

### Modularity For Future Protocols

The scheduler and merger were deliberately separated from the worker arithmetic datapath:

| Current Module | Future Replacement |
|---|---|
| `work_dispatch_static_rows.v` | Dynamic row/tile scheduler. |
| `raster_merge_static_rows.v` | Row/tile packetizer or out-of-order merger. |
| Existing UART response stream | Higher-bandwidth coordinate-tagged stream. |

This keeps future protocol changes localized. Workers already accept row metadata through `row_start_in` and `row_stride_in`.

### 4-Core Timing Closure

The first 4-core route missed timing by a small margin in `fp_add` normalization/output logic:

| Build | Result |
|---|---:|
| First 4-core route | `WNS=-0.133ns`, `TNS=-0.151ns` |
| After additional `fp_add` output-side pipeline | timing met |

Final timing:

| Metric | Value |
|---|---:|
| WNS | `0.224ns` |
| TNS | `0.000ns` |
| WHS | `0.005ns` |
| THS | `0.000ns` |

### 4-Core Resource Result

| Resource | Used | Available | Utilization |
|---|---:|---:|---:|
| Slice LUTs | 8597 | 17600 | 48.85% |
| Slice Registers | 9807 | 35200 | 27.86% |
| Block RAM Tile | 8.5 | 60 | 14.17% |
| DSP48E1 | 38 | 80 | 47.50% |

The result matched the feasibility study closely.

## End-To-End Stage Effects

The table below summarizes how each stage moved the system bottleneck.

| Stage | Main Bottleneck Before | Change | Effect |
|---|---|---|---|
| Functional baseline | Correctness and streaming reliability | Fixed FP/core/TX/host reference bugs | Produced reliable hardware images and simulation regressions. |
| True 100 MHz | FP adder/multiplier timing | Added FP pipeline cuts, removed multicycle constraints | Compute-bound scenes improved about `1.40x-1.41x`. |
| UART 576k baud | 460800 baud output ceiling | Swept integer-divider bauds with raw-probe; TX-only isolation proved TX works at 625k+; 576k selected as stable standard-PC baud | UART-limited scenes improved about `1.15x`; systematic understanding of high-baud failure mode. |
| Multi-core feasibility | Need parallel compute but protocol constrained | Selected 4-core interleaved rows | Clear path with no host protocol change. |
| 4-core implementation | Single-worker compute throughput | Added 4 workers and raster merger | Compute-bound 1080p scenes improved about `3.5x-3.6x`. |
| FP64 boundary differences | Truncation vs RNE discrepancy | Quantified chaotic amplification, documented acceptance criteria | Verified differences are benign and expected. |
| Dynamic scheduler option | Static row modulo can leave row-level tail imbalance | Added `SCHED_MODE=1` idle-core row dispatcher and raster collector | Dynamic mode simulates and builds successfully while preserving the host protocol. |
| Worker-internal 2-context interleaving | Per-worker FP pipelines underfed | Added `mandelbrot_core_worker_2ctx` with tagged FP writeback and ordered commit | Five of six 1080p scenes now hit UART ceiling; deep mini-brot improves `2.80x` vs 4-core 1ctx. |
| Dynamic backpressure fix | Large UART-bound dynamic frames could deadlock | Gate dynamic row reuse on empty per-core FIFO | 1920-wide and full 1080p frames complete reliably under UART backpressure. |
| Fractional UART 12 Mbaud | Integer divider precision and 576k output ceiling | Replaced integer CPB timing with 32-bit fractional baud accumulators in RX/TX | Fast 1080p scenes improve from about `28.5k pps` to `443k-493k pps`; compute-heavy scenes expose core limits. |
| Tiled response and host-driven stripes | 12 Mbaud multi-megabyte bursts can occasionally lose bytes | Added `RT`/`TD`/`TE` response packets and host `1920x120` stripe retries | Six-scene 30-run sweep completed with 30/30 transport pass; two checksum errors recovered at tile granularity. |
| Compute-tile retry and soft reset | Host-tile retry still recomputed large stripes and stale bytes could leave the link out of sync | Added explicit compute-tile controls and UART soft reset `RST!RST!` | Retry unit is one compute tile; current default uses the host tile itself (`1920x120` at 1080p) with width capped at 4096, and optional smaller compute tiles remain available. |
| Planned low-LUT N-context worker | Generic K-context scoreboard proved functional but exceeded LUT capacity | Documented ring/barrel context-slot worker direction | Future 4/8/12/16-context work should reduce wide muxes and scans before adding FP units. |
| XC7K70T 4ctx default worker | 2ctx still leaves FP issue bubbles in deep scenes | Made validated `WORKER_CONTEXTS=4` generic worker the default on larger XC7K70T | Timing clean at `WNS=0.583ns`; deep 1080p scenes improve about `1.8x-2.1x`, but LUT use reaches `88.70%`. |

## Final 1080p Performance Comparison

The 4-core design's gains over single-core are architecture-limited, not baudrate-limited. The tables below show the architectural speedup at matched baud rates.

### At 500000 Baud (Historical Baseline)

| Scene | Single Core 500k | 4-Core 500k | Speedup | Limiting Factor |
|---|---:|---:|---:|---|
| Fast escape @128 | `91.183s` | `83.520s` | `1.09x` | UART |
| Standard @64 | `83.510s` | `83.501s` | `1.00x` | UART |
| Seahorse zoom @512 | `171.817s` | `83.956s` | `2.05x` | UART after compute improvement |
| Deep tendrils @8192 | `340.029s` | `93.960s` | `3.62x` | mixed, near UART |
| Deep mini-brot @8192 | `850.720s` | `234.261s` | `3.63x` | compute |
| Deep seahorse @1024 | `363.253s` | `103.032s` | `3.53x` | mixed, near UART |

### At 576000 Baud (Historical Default)

| Scene | 4-Core 500k | 4-Core 576k | Throughput | vs 4-Core 500k |
|---|---:|---:|---:|---:|
| Fast escape @128 | `83.520s` | `72.736s` | `28508.56 pps` | `1.15x` |
| Standard @64 | `83.510s` | `72.735s` | `28508.82 pps` | `1.15x` |
| Seahorse zoom @512 | `83.956s` | `74.265s` | `27921.47 pps` | `1.13x` |
| Deep tendrils @8192 | `93.960s` | `93.916s` | `22079.29 pps` | `1.00x` |
| Deep mini-brot @8192 | `234.261s` | `234.231s` | `8852.78 pps` | `1.00x` |
| Deep seahorse @1024 | `103.032s` | `100.658s` | `20600.46 pps` | `1.02x` |

The 576000 baud improvement follows UART dependency precisely: UART-bound scenes see the full ~15% raw bandwidth gain (576000/500000 = 1.152), mixed-bound scenes see a partial improvement (1.02x–1.13x), and compute-bound scenes see no change. All six scenes ran successfully at 1080p resolution; the first three were verified with `--verify` against the software reference.

### Dynamic Scheduler At 576000 Baud

The optional `SCHED_MODE=1` dynamic row scheduler was also benchmarked on the same six 1080p scenes after programming `fp64_dynamic_proj/mandelbrot_fp64_dynamic.runs/impl_1/top.bit`.

| Scene | Static 4-Core 576k | Dynamic 4-Core 576k | Dynamic Throughput | Dynamic vs Static |
|---|---:|---:|---:|---:|
| Fast escape @128 | `72.736s` | `72.721s` | `28514.47 pps` | `1.000x` |
| Standard @64 | `72.735s` | `72.719s` | `28515.41 pps` | `1.000x` |
| Seahorse zoom @512 | `74.265s` | `74.253s` | `27926.03 pps` | `1.000x` |
| Deep tendrils @8192 | `93.916s` | `93.907s` | `22081.36 pps` | `1.000x` |
| Deep mini-brot @8192 | `234.231s` | `234.137s` | `8856.36 pps` | `1.000x` |
| Deep seahorse @1024 | `100.658s` | `100.691s` | `20593.74 pps` | `1.000x` |

This confirms the scheduling model: the current real scenes have little row-level tail imbalance left for dynamic assignment to recover. The dynamic scheduler is useful as an architecture option and validates the scheduler/collector replacement boundary, but the next major performance improvements still require transport upgrades, tagged/tile output, or worker-internal de-bubbling.

The important lesson is that dynamic row assignment targeted the wrong dominant term for these measured scenes. Fast scenes are already limited by UART output time. Compute-heavy scenes are dominated by worker-internal FP latency rather than row ownership imbalance. The existing static scheduler already interleaves adjacent rows, so it was much closer to balanced than a contiguous-band split would have been.

### Default Dynamic + Two-Context Worker At 576000 Baud Historical Baseline

The then-current default combined dynamic row scheduling with two pixel contexts inside each of the four workers. Each worker still shared one FP64 multiplier and one FP64 adder; the improvement came from tagged FP writeback and context interleaving, not from adding more FP units.

| Scene | Previous 4-Core 1ctx 576k | Default Dynamic 2ctx 576k | Throughput | Speedup |
|---|---:|---:|---:|---:|
| Fast escape @128 | `72.736s` | `72.720s` | `28514.74 pps` | `1.000x` |
| Standard @64 | `72.735s` | `72.721s` | `28514.28 pps` | `1.000x` |
| Seahorse zoom @512 | `74.265s` | `72.790s` | `28487.54 pps` | `1.020x` |
| Deep tendrils @8192 | `93.916s` | `72.781s` | `28491.11 pps` | `1.290x` |
| Deep mini-brot @8192 | `234.231s` | `83.708s` | `24771.84 pps` | `2.798x` |
| Deep seahorse @1024 | `100.658s` | `72.776s` | `28493.04 pps` | `1.383x` |

The result matches the earlier whole-system model. Fast escape and standard views had almost no headroom because they were already near the 576000 baud pixel ceiling. Tendrils and deep seahorse improve until they also hit UART. Deep mini-brot remains compute-bound, so it exposes the largest visible improvement.

The implemented 2-context worker required three correctness details:

| Detail | Why it matters |
|---|---|
| FP result tags | Back-to-back FP issues must route delayed results to the correct pixel context. |
| Actual tag latencies | `MUL_LAT=6` and `ADD_LAT=7`; using old `PIPE_WAIT+1` timing mis-tagged adjacent context results. |
| Ordered commit | Contexts can finish out of order, but the per-core FIFO must remain worker-local column order. |

The dynamic scheduler also needed a backpressure rule: only assign a new row to a core when that core's FIFO is empty. Without this, a fast compute scene could fill a core FIFO with future rows while the raster collector waited for an earlier row from that same core, deadlocking under UART backpressure.

Architecturally, the implemented 2-context worker is a tagged two-entry scoreboard. It keeps two pixel context register sets, issues ready operations into one shared FP64 multiplier and one shared FP64 adder, carries operation/context tags through latency-matched delay lines, and commits completed pixels in column order. This was the smallest correct deployable step, but its LUT cost comes from FP64 operand muxing, writeback demuxing, in-flight checks, and ordered commit logic rather than from DSP replication.

The later generic 4/8-context experiment confirmed the functional direction but also showed the wrong deployable RTL shape for xc7z010: direct scoreboard parameterization expands the wide muxes and context scans too aggressively. The documented next architecture direction is a CPU-like barrel or ring worker with fixed context slots, a round-robin issue pointer, latency-delayed return pointers, and an ordered result ring. That approach still stores N pixel states, but it should reduce LUT use by avoiding arbitrary N-way context selection each cycle.

Historical routed timing and placed utilization for this integration point, before the later 12 Mbaud tiled-response controller changes:

| Metric | Value |
|---|---:|
| WNS | `0.091ns` |
| TNS | `0.000ns` |
| WHS | `0.011ns` |
| THS | `0.000ns` |
| Slice LUTs | `13630 / 17600` (`77.44%`) |
| Slice Registers | `14391 / 35200` (`40.88%`) |
| DSP48E1 | `38 / 80` (`47.50%`) |
| Block RAM Tile | `9.5 / 60` (`15.83%`) |

### Fractional UART At 12 Mbaud

The final transport step replaced integer `CLOCKS_PER_BIT` timing with a fractional baud accumulator shared by the UART RX and TX designs. The compatibility parameter remains, but bit ticks now come from:

```text
BAUD_INC = round(BAUD * 2^ACC_WIDTH / CLK_HZ)
```

At `BAUD=12000000`, one bit is `16.666...` system clocks in the current direct-200MHz default, so an integer divider cannot represent it accurately. The accumulator emits a repeating mix of 16- and 17-cycle intervals, preserving the average baudrate while keeping all logic in one clock domain. The older 100MHz reference emitted an 8/9-cycle mix for the same reason.

```mermaid
flowchart LR
    OLD["Integer CPB UART<br/>576000 stable baseline"] --> NCO["Fractional NCO UART<br/>BAUD_INC accumulator"]
    NCO --> GATE["160x120 --verify gate<br/>all tested bauds pass"]
    GATE --> FULL["Six 1080p scenes<br/>12 Mbaud default"]
    FULL --> LIMIT["New visible limits<br/>host burst reliability + compute"]
```

12 Mbaud six-scene results after targeted reprobes:

| Scene | 576k 2ctx | 12M 2ctx | 12M Throughput | Main limiter at 12M |
|---|---:|---:|---:|---|
| Fast escape @128 | `72.720s` | `4.678s` | `443288.08 pps` | UART/host burst overhead |
| Standard @64 | `72.721s` | `4.202s` | `493434.63 pps` | UART/host burst overhead |
| Seahorse zoom @512 | `72.790s` | `17.280s` | `120003.12 pps` | Mixed compute/output |
| Deep tendrils @8192 | `72.781s` | `33.393s` | `62096.41 pps` | Compute/raster ordering |
| Deep mini-brot @8192 | `83.708s` | `83.428s` | `24854.93 pps` | Compute-bound |
| Deep seahorse @1024 | `72.776s` | `36.480s` | `56842.30 pps` | Compute/raster ordering |

The 12 Mbaud path is fast but not yet protocol-hardened. The first six-scene sweep had two late-frame receive timeouts near the end of 4.1 MiB payloads; direct reprobes filled both result cells. This points to occasional host/FT232HL/driver long-burst receive instability rather than deterministic RTL pixel-count failure. The current response protocol has one final checksum and no packet sequence numbers, so any dropped byte causes the host to wait for the declared payload length until timeout.

### Tiled Response And Host-Driven Stripe Retry

The next transport hardening step kept the UART physical layer but changed the response contract. The RTL now emits framed tiled responses using `RT` frame headers, repeated `TD` data packets, and `TE` frame-end markers. Each `TD` packet carries row/column coordinates, tile dimensions, payload bytes, and a payload XOR checksum. The host parser accepts both the original `RK` full-frame response and the new tiled response.

Packetizing the response alone detects byte slips earlier, but it does not let the FPGA retransmit a packet because the UART protocol is still unidirectional during response streaming. Reliability therefore moved one level up: host-driven tiling splits a frame into retryable compute commands. A failed packet invalidates only the current host tile; the host drains the serial stream and recomputes that tile.

```mermaid
flowchart TB
    FULL["Old full-frame command<br/>one 4 MiB response burst"] --> SLIP["Any byte slip loses frame"]
    SLIP --> TILE["Host-driven 1920x120 stripes<br/>nine commands per 1080p frame"]
    TILE --> TD["RTL RT/TD/TE packet stream"]
    TD --> RETRY["Checksum error retries one stripe"]
```

The selected operating point is `--tile-width 1920 --tile-height 120 --tile-retries 3 --quiet`. Smaller `80x60` tiles were reliable but slow because 1080p required 432 commands and thousands of small packet reads. Larger horizontal stripes reduce the command count to nine while retaining a recovery boundary much smaller than a full frame.

Historical routed timing and placed utilization after the 12 Mbaud tiled-response build on the earlier xc7z010 target:

| Metric | Value |
|---|---:|
| WNS | `0.285ns` |
| TNS | `0.000ns` |
| WHS | `0.021ns` |
| THS | `0.000ns` |
| Slice LUTs | `13917 / 17600` (`79.07%`) |
| LUT as Logic | `13641 / 17600` (`77.51%`) |
| LUT as Memory | `276 / 6000` (`4.60%`) |
| Slice Registers | `14458 / 35200` (`41.07%`) |
| DSP48E1 | `37 / 80` (`46.25%`) |
| Block RAM Tile | `9.5 / 60` (`15.83%`) |

Repeated 12 Mbaud host-tiled stability results:

| Scene | Completed runs | Tile retries | Mean FPGA s | Stddev s | CV | Mean pps | vs previous 12M single-burst |
|---|---:|---:|---:|---:|---:|---:|---:|
| Fast escape @128 | `5/5` | `0` | `4.844` | `0.001` | `0.02%` | `428068.64` | `0.966x` |
| Standard @64 | `5/5` | `0` | `4.450` | `0.001` | `0.02%` | `466030.04` | `0.944x` |
| Seahorse zoom @512 | `5/5` | `1` | `17.598` | `1.151` | `6.54%` | `118207.86` | `0.982x` |
| Deep tendrils @8192 | `5/5` | `1` | `34.026` | `1.873` | `5.51%` | `61080.26` | `0.981x` |
| Deep mini-brot @8192 | `5/5` | `0` | `83.281` | `0.001` | `0.00%` | `24898.89` | `1.002x` |
| Deep seahorse @1024 | `5/5` | `0` | `36.343` | `0.002` | `0.00%` | `57056.36` | `1.004x` |

The benchmark target was five repeats for each of the six standard 1080p scenes. After 23 completed frame runs, the FT232H disappeared from Windows and subsequent attempts failed before opening the serial port; after reconnecting the device, the failed/open-port logs were rerun with `--resume`, completing all 30 frame runs. The completed sweep shows that the stripe retry path recovers occasional checksum errors with only a small performance penalty on transport-bound scenes and no meaningful penalty on compute-bound mini-brot or deep Seahorse.

Test parameters for the comparison table:

| Scene | Center | Step | Max Iter |
|---|---|---:|---:|
| Fast escape @128 | `(1.0, 1.0)` | `0.002` | `128` |
| Standard @64 | `(-0.5, 0.0)` | `0.002` | `64` |
| Seahorse zoom @512 | `(-0.743643887037151, 0.13182590420533)` | `5e-6` | `512` |
| Deep tendrils @8192 | `(-0.77568377, 0.13646737)` | `1e-9` | `8192` |
| Deep mini-brot @8192 | `(-1.25066, 0.02012)` | `1e-9` | `8192` |
| Deep seahorse @1024 | `(-0.743643887037151, 0.13182590420533)` | `1e-8` | `1024` |

### N-Context Worker Experiments And XC7K70T 4ctx Validation

After the 2-context worker became the default timing-clean design, the next compute-side question was whether more contexts could hide more FP latency without adding DSPs. Two related experiments were tried and abandoned for xc7z010 deployment, but the later XC7K70T migration provided enough LUT capacity to validate the 4-context generic worker on board.

The first experiment was the generic K-context scoreboard worker, `mandelbrot_core_worker_kctx`. It preserves the 2ctx tagged writeback idea but scales it to `CONTEXTS=4` or `8` by using generic context arrays, ready scans, context tags, and ordered commit. Behavioral simulation passed, but synthesis showed that the LUT cost scales too poorly:

| Case | Behavioral sim | Slice LUTs | Placement result |
|---|---:|---:|---|
| Current 2ctx specialized worker | Board baseline | `13917 / 17600` (`79.07%`) | Timing-clean default |
| Generic 4ctx scoreboard | PASS, 192 pixels | `37350 / 17600` (`212.22%`) | Not placeable |
| Generic 8ctx scoreboard | PASS, 192 pixels | `71462 / 17600` (`406.03%`) | Not placeable |

On XC7K70T, the 4ctx version becomes deployable:

| Case | Target | Timing | Slice LUTs | Registers | DSPs | Board result |
|---|---|---:|---:|---:|---:|---|
| Generic 4ctx scoreboard | XC7K70T | `WNS=0.583ns` | `36367 / 41000` (`88.70%`) | `19149 / 82000` (`23.35%`) | `37 / 240` (`15.42%`) | Timing-clean default, `160x120` verify PASS |
| Historical 2ctx worker | XC7K70T | `WNS=1.148ns` | `13726 / 41000` (`33.48%`) | `14559 / 82000` (`17.75%`) | `37 / 240` (`15.42%`) | Timing-clean lower-LUT baseline, `160x120` verify PASS |

The 4ctx bitstream was built with `build_fp64_contexts.tcl 4`, programmed from `fp64_ctx4_proj/mandelbrot_fp64_ctx4.runs/impl_1/top.bit`, and verified at `160x120`: `19200/19200` pixels matched (`100.00%`) with `0.091s` FPGA elapsed.

One-run 1080p results at 12 Mbaud using `1920x120` host/compute tiles:

| Scene | Historical 2ctx FPGA s | Default 4ctx FPGA s | Default 4ctx pps | 4ctx vs 2ctx |
|---|---:|---:|---:|---:|
| Fast escape @128 | `5.127` | `4.683` | `442824.20` | `1.09x` |
| Standard @64 | `4.731` | `5.782` | `358640.05` | `0.82x` |
| Seahorse zoom @512 | `19.440` | `9.836` | `210825.06` | `1.98x` |
| Deep tendrils @8192 | `37.326` | `17.677` | `117303.25` | `2.11x` |
| Deep mini-brot @8192 | `83.561` | `44.146` | `46971.46` | `1.89x` |
| Deep Seahorse @1024 | `36.626` | `19.965` | `103861.51` | `1.83x` |

The result updates the earlier conclusion: generic K-context is not deployable on the small xc7z010, but 4ctx is deployable on XC7K70T. It is still not the best long-term RTL shape because it spends most of the extra device headroom on wide context arrays, operand muxes, writeback demuxes, and scans. The right next high-context architecture remains a lower-LUT explicit-slot or barrel/ring worker.

The second experiment modeled a ring/barrel worker with a small lookahead window. The model suggested that `4ctx ring_la4` could recover most of the lost scheduling freedom while avoiding a full K-way scoreboard. A minimal RTL attempt implemented that idea by adding lookahead scheduling to the generic K-context worker. It was also abandoned because it still left Vivado with generic FP64 context arrays and wide mux/writeback fabrics:

| Case | Behavioral sim | Implementation result |
|---|---:|---|
| `4ctx LA1` generic lookahead | PASS, 192 pixels, `497905 ns` | Bitstream generated but timing failed: `WNS=-0.271ns`, `TNS=-3.574ns` |
| `4ctx LA2` generic lookahead | PASS, 192 pixels, `468745 ns` | Placement blocked: synth `25194 / 17600` Slice LUTs (`143.15%`) |
| `4ctx LA4` generic lookahead | PASS, 192 pixels, `444355 ns` | Placement blocked: synth `39025 / 17600` Slice LUTs (`221.73%`) |
| `8ctx LA4` generic lookahead | PASS, 192 pixels, `328325 ns` | Not pursued to implementation after 4ctx failed |

No 1080p board benchmark was run for the abandoned xc7z010 lookahead variants because there was no suitable timing-clean candidate bitstream. The current architectural decision is to use the timing-clean XC7K70T 4ctx generic worker as the default, keep the 2ctx worker as a lower-LUT baseline, and not pursue the old generic lookahead implementation path in this repository.

The practical lesson is that model-level scheduling improvements are not enough when the RTL shape still exposes generic FP64 context arrays to synthesis. XC7K70T proves the performance direction for 4ctx, but its `88.70%` LUT use also shows why any future 8/12/16-context attempt should be a fresh hand-shaped worker with explicit slots and measured single-core/two-core LUT scaling, not a wider parameterized extension of `mandelbrot_core_worker_kctx`.

## Stage 9: Direct 200 MHz Timing Closure

The then-validated 100 MHz 4ctx default left one obvious question: can the full Mandelbrot/UART domain run directly from the board 200 MHz clock? The first answer was no. A direct switch to 200 MHz exposed route-dominated paths in the generic 4ctx worker: context scans, launch/commit control, and 64-bit FPU operand muxes.

Detailed report: [200MHZ_ATTEMPT_REPORT.md](200MHZ_ATTEMPT_REPORT.md).

### Design Constraint

The direct-clock experiment had stricter acceptance rules than earlier exploratory work:

| Rule | Reason |
|---|---|
| Keep the then-default 100 MHz 4ctx intact | 100 MHz was already board-validated and balanced. |
| Use a separate `build_fp64_200mhz.tcl` entry | Avoid silently changing the product/default build. |
| Run behavioral simulation before implementation | Timing-clean broken RTL is not useful. |
| Do not program timing-failing bitstreams | Avoid collecting invalid performance data. |
| Do not accept timing-clean but HW/SW-failing bitstreams | Timing success alone is not a functional design point. |

### Failed But Informative Attempts

The path to a valid 200 MHz point was not a single timing tweak. Several ideas were rejected because they either broke hardware function or made timing worse:

| Attempt | Result | Lesson |
|---|---|---|
| First `C_CHECK_ITER` timing-clean repair | `WNS=0.001ns`, but hardware verify only `17200/19200` | Separating hot state updates can hide a tag/operand alignment bug. |
| State-qualified issue gating and ready clearing | Timing failed | Adding state conditions to issue mux paths puts control back into the hot cone. |
| Local issue round-robin pointers | Behavioral pass, `WNS=-0.374ns` | Reducing conceptual scan freedom is not enough if it adds routing/control pressure. |
| Operand-latched request slicing | Behavioral pass, post-route phys-opt `WNS=-0.042ns` | Latching 64-bit request operands moves the hot endpoint to request registers. |
| Simple `MUL_LAT/ADD_LAT +1` | Still failed function | The issue was not generic extra latency; it was exact tag/result pulse alignment. |

### Final Timing Design

The final accepted design combines arithmetic pipeline cuts with a control-path request stage:

```text
Context/control scan        64-bit operand drive        FPU pipeline/result
Cycle N                    Cycle N+1                  Cycle N+latency
req_valid/op/ctx    --->   mul_a/mul_b/add_a/add_b ->  tagged writeback
```

The important detail is that the request stage latches only operation and context, not the 64-bit operands. This cuts the context-selection decision from the operand-drive cycle without creating a new 64-bit request-register endpoint.

Example multiply issue:

```text
N:   context 2 has z_re*z_im ready
     mul_req_valid=1, mul_req_op=MOP_ZRZI, mul_req_ctx=2

N+1: mul_a=c_z_re[2]
     mul_b=c_z_im[2]
     mul_op_pipe[0]=MOP_ZRZI
     mul_ctx_pipe[0]=2

N+6: mul_done_op=MOP_ZRZI
     mul_done_ctx=2
     c_z_re_z_im[2] <= mul_result
```

The functional breakthrough was measuring the actual request-sliced FPU result alignment. `fp_add` stayed aligned at `ADD_LAT=9`, but `fp_mul` aligned at `MUL_LAT=6`. With `MUL_LAT=7/8`, high-iteration boundary pixels could capture the following zero-output cycle, producing max-iteration results where software escaped.

Final kctx direct-200MHz tag constants:

```verilog
localparam MUL_LAT = 6;
localparam ADD_LAT = 9;
```

The direct-200MHz implementation also keeps earlier timing cuts: FP multiplier partial-product registers, FP adder compare/select and normalize/output splits, `tx_ctrl` tile-advance split, context release cleanup, launch coordinate update split, and `C_CHECK_ITER`.

### Validation Sequence

The final 200 MHz candidate passed progressively stronger gates:

| Gate | Result |
|---|---|
| Worker-only row 0, `160x12`, `max_iter=256` | PASS, 160 pixels |
| Worker-only row 9, `160x12`, `max_iter=256` | PASS, 160 pixels |
| Multicore dynamic, `160x12`, `CORE_FIFO_DEPTH=4096` | PASS, 1920 pixels |
| Multicore dynamic, `160x120`, `CORE_FIFO_DEPTH=4096` | No mismatch through 10240 pixels before practical sim-time limit |
| Routed timing | `WNS=0.015ns`, `TNS=0.000ns`, `WHS=0.002ns`, `THS=0.000ns` |
| Hardware small image | `19200/19200` exact match, FPGA elapsed `0.158s` |
| 1080p stability | 60/60 transport pass across six scenes and 10 runs each |

### 10-Run Direct-200MHz Result

| Scene | Transport pass | Retry events | Mean FPGA s | Mean pps | vs 100MHz 4ctx |
|---|---:|---:|---:|---:|---:|
| fast escape @128 | `10/10` | `6` | `5.072` | `413592.02` | `0.923x` |
| standard @64 | `10/10` | `6` | `5.066` | `414046.70` | `1.141x` |
| Seahorse zoom @512 | `10/10` | `6` | `7.879` | `273303.15` | `1.248x` |
| deep tendrils @8192 | `10/10` | `3` | `12.820` | `162504.12` | `1.379x` |
| deep mini-brot @8192 | `10/10` | `2` | `31.625` | `65709.99` | `1.396x` |
| deep Seahorse @1024 | `10/10` | `0` | `13.886` | `149325.97` | `1.438x` |

### Architectural Decision

The 200 MHz 4-worker design became a valid repository default at this stage. Relative to the 100MHz 4ctx data, it was slower on the fast-escape scene and faster on standard/deep scenes, with `1.14x-1.44x` improvement across the non-fast scenes in the 10-run mean. The 100MHz 4ctx build remained available as an explicit reference for shallow-scene comparisons.

## Stage 10: 6-Worker Direct-200MHz Default

The next measured question was whether the direct-200MHz 4ctx worker could be replicated beyond four workers on XC7K70T. This was not treated as a parameter-only change: timing-failing bitstreams were not programmed, and a candidate had to pass behavioral simulation, implementation timing, programming, and the 1080p six-scene benchmark before becoming a valid performance point.

Detailed report: [WORKER_COUNT_SCALING.md](WORKER_COUNT_SCALING.md).

### Worker Count Matrix

| Build | Clock | Workers | Contexts/worker | Result | Timing/resource summary |
|---|---:|---:|---:|---|---|
| Previous default | direct 200MHz | 4 | 4 | Validated on board | `WNS=0.015ns`; 20288 LUT, 17202 FF, 37 DSP48E1, 9.5 BRAM tiles |
| Original 6-worker candidate | direct 200MHz | 6 | 4 | Routed but not valid for board test | `WNS=-0.165ns`, `TNS=-8.713ns`; route-dominated dispatcher/worker-control paths |
| Fixed 6-worker candidate | direct 200MHz | 6 | 4 | Timing-clean, programmed, benchmarked, became the XC7K70T-stage default | `WNS=0.003ns`, `TNS=0.000ns`; 29891 LUT, 25501 FF, 97 DSP48E1, 13.5 BRAM tiles |
| 8-worker candidate | direct 200MHz | 8 | 4 | Placement failed | LUT/slice packing over-utilized; 40635 synth LUT, 33366 FF, 129 DSP48E1 |
| 8-worker reference | 100MHz | 8 | 4 | Timing-clean and benchmarked | Useful comparison point, but slower than fixed 6-worker 200MHz on compute-heavy scenes |

The original 6-worker direct-200MHz implementation was close enough to be worth fixing. The worst path was not an FP datapath; it was dominated by routing from the dynamic dispatcher into worker-control fanout. Two minimal RTL cuts made the build timing-clean:

| Change | Purpose |
|---|---|
| Remove the active-cycle `row_stride_bus` rewrite in `work_dispatch_dynamic_rows.v` | `row_stride_bus` is a frame-constant in dynamic mode after start, so the repeated write only created a long control path. |
| Add `S_INIT_LATCH` in `mandelbrot_core_worker_kctx.v` | Latch `row_start`, `row_stride`, `rows`, and `cols` locally before generating FP row-start/stride values, cutting dispatcher-to-worker conversion paths. |

Validation after the fix:

| Gate | Result |
|---|---|
| 6-worker dynamic multicore behavioral simulation | PASS, `1920` pixels |
| Direct-200MHz implementation | Bitstream generated |
| Post-route phys-opt timing | `WNS=0.003ns`, `TNS=0.000ns`, `WHS=0.042ns`, `THS=0.000ns` |
| Board programming | PASS |
| 1080p 10-run benchmark | PASS for all six scenes |

### 6-Worker 10-Run Result

| Scene | Transport pass | Retry events | Mean FPGA s | Mean pps | vs 4w 200MHz | vs 100MHz 4ctx |
|---|---:|---:|---:|---:|---:|---:|
| fast escape @128 | `10/10` | `2` | `4.641` | `453333.47` | `1.09x` | `1.009x` |
| standard @64 | `10/10` | `2` | `4.636` | `450824.12` | `1.09x` | `1.247x` |
| Seahorse zoom @512 | `10/10` | `2` | `5.715` | `366227.26` | `1.38x` | `1.721x` |
| deep tendrils @8192 | `10/10` | `1` | `8.567` | `242675.75` | `1.50x` | `2.063x` |
| deep mini-brot @8192 | `10/10` | `0` | `20.963` | `98916.27` | `1.51x` | `2.106x` |
| deep Seahorse @1024 | `10/10` | `1` | `9.668` | `214934.36` | `1.44x` | `2.065x` |

### Updated Default Decision

The fixed 6-worker direct-200MHz build became the repository default for the XC7K70T stage because it was timing-clean, hardware-benchmarked, and fastest across that measured six-scene 1080p set. The previous 4-worker direct-200MHz build remained the lower-area 200MHz reference, and the 100MHz 4ctx build remained an explicit reference for comparisons.

## Stage 11: VMC_RTSB ZU4EV 200MHz 12-Worker/8-Context Default

The next architecture step moved the validated direct-200MHz design from the XC7K70T target to the VMC_RTSB ZU4EV board and used the larger FPGA to increase both worker count and per-worker context count. This stage was not treated as a board-only port. The final accepted point changes the active platform, the constraints, the UART bring-up assumptions, the programming flow, the default worker/context parameters, and the performance baseline.

Detailed report: [VMC_RTSB_ZU4EV_200MHZ_OPT_REPORT.md](VMC_RTSB_ZU4EV_200MHZ_OPT_REPORT.md).

### Board And Constraint Migration

The old active target used an XC7K70T board with differential `CLK_200_P/N` and CH347/XVC-oriented programming assumptions. The current target is VMC_RTSB ZU4EV with a single-ended 200 MHz reference clock.

| Area | Previous active target | Current target |
|---|---|---|
| FPGA part | `xc7k70tfbg676-1` | `xczu4ev-sfvc784-1-i` |
| Clock input | Differential `CLK_200_P/N` | Single-ended `sys_clk` on `E12` |
| Clock constraint | 200 MHz differential board clock | `create_clock -period 5.000 [get_ports sys_clk]` |
| Main XDC directory | `constraints_hvs_xc7k70t` | `constraints_vmc_rtsb_zu4ev` |
| Main XDC file | XC7K70T board constraints | `constraints_vmc_rtsb_zu4ev/mandelbrot_top.xdc` |
| UART pins | Old board mapping | `uart_rx=D12`, `uart_tx=C12`, `LVCMOS25` |
| Status LEDs | Broad XC7K70T LED/J1 mapping | `led[2]=A11`, `led[3]=A12`, `LVCMOS25` |
| Host port | `COM9` | `COM6` |
| Programming | XVC-specific flow | Vivado hardware auto-connect, device match `*xczu4*` |

The active constraints were migrated into `constraints_vmc_rtsb_zu4ev`. The old `constraints_hvs_xc7k70t` directory is no longer referenced by active build scripts. The stale `led.xdc` content in the ZU4EV constraint area was removed because it used an old `E10` clock assumption and conflicted with the current UART pins.

### Top-Level And UART Bring-Up Changes

The ZU4EV top-level clocking is intentionally simpler than the old board-specific differential path:

```text
E12 sys_clk pad -> BUFG -> sys_clk_i -> UART/parser/core/FIFOs/TX
```

The UART test tops were updated before relying on hardware measurements:

| Test top | Change | Board result |
|---|---|---|
| `rtl/uart_tx_pattern_top.v` | Single-ended `sys_clk`, `BUFG`, explicit `CLK_HZ=200000000` | Pattern `55aa00ff524b017e` received at `COM6 / 12 Mbaud`, `pattern_hits=3921` |
| `rtl/uart_echo_top.v` | Single-ended `sys_clk`, `BUFG`, explicit `CLK_HZ=200000000` | Echo passed `32/32` trials at `COM6 / 12 Mbaud` |

This avoided a common false-positive risk during board migration: testing UART with a stale MMCM/100MHz assumption while the main design uses direct 200MHz timing.

### Default Architecture Change

The previous best XC7K70T point was 6 workers with 4 contexts per worker at direct 200 MHz. On ZU4EV, the first buildable baseline used the same 6/4 shape to verify clocking, constraints, and part migration. The accepted performance point then doubled both worker count and contexts per worker.

| Candidate | Workers | Contexts/worker | Clock | Result | Timing/resource summary |
|---|---:|---:|---:|---|---|
| ZU4EV baseline | 6 | 4 | 200 MHz | Sim/build passed | `WNS=0.751ns`; 30057 / 87840 LUT, 27099 / 175680 FF, 61 / 728 DSP, 13.5 / 128 BRAM |
| ZU4EV accepted default | 12 | 8 | 200 MHz | Sim/build/program/HW benchmark passed | `WNS=0.148ns`; 85171 / 87840 LUT, 71453 / 175680 FF, 121 / 728 DSP, 25.5 / 128 BRAM |

The reason for scaling contexts as well as workers is pipeline occupancy. Each worker still owns one FP64 multiplier and one FP64 adder. With `MUL_LAT=6` and `ADD_LAT=9`, more live contexts help each worker keep its shared FP pipelines busy while additional workers provide row-level parallelism.

No arithmetic latency change was made in this stage:

```verilog
localparam MUL_LAT = 6;
localparam ADD_LAT = 9;
```

The routed timing evidence did not point to a deep FP add/mul combinational cone. The accepted 12/8 worst path is route-dominated command-parameter distribution, for example from `u_cmd/step_reg` to worker-local `step_val_reg`, with about `98%` route delay and zero LUT levels. That makes the next compute optimization a fanout/routing problem, not an arithmetic pipeline-depth problem.

### Simulation And Hardware Validation

The scaled 12/8 candidate passed behavioral simulation before implementation:

```text
vivado.bat -mode batch -source sim_multicore_dynamic_contexts.tcl -tclargs WORKER_CONTEXTS 8 CORE_COUNT 12 ROWS 12 COLS 160 MAX_ITER 256 CORE_FIFO_DEPTH 4096 TIMEOUT_CYCLES 30000000
=== DYNAMIC MULTICORE TEST PASS: 1920 pixels ===
```

The same behavioral workload improved materially before UART or host effects were involved:

| Candidate | Workers | Contexts | Sim workload | Sim finish time | Relative speed |
|---|---:|---:|---|---:|---:|
| Baseline | 6 | 4 | `12x160`, `max_iter=256`, `1920 pixels` | `15.978ms` | `1.000x` |
| Scaled | 12 | 8 | `12x160`, `max_iter=256`, `1920 pixels` | `6.300ms` | `2.536x` |

The accepted bitstream was then verified on hardware with a small software-checked image:

```text
python python\mandelbrot_host.py --port COM6 --width 160 --height 120 --max-iter 256 --center -0.5 0.0 --step 0.005 --output python\hw_zu4ev_200m_c12ctx8_160x120.png --verify --quiet --timeout 60 --tile-width 160 --tile-height 120 --tile-retries 3
FPGA elapsed: 0.058s, 332476.74 pixels/s
HW vs SW: 19200/19200 match (100.00%)
```

### 1080p Performance Update

The current ZU4EV 12-worker/8-context result was benchmarked for 10 runs per scene with the same six 1080p scene set, `1920x120` host/compute tiles, and `12 Mbaud` UART. The summary file is `../python/host_tile_stability_bench/zu4ev200m_c12ctx8_10run.md`.

| Scene | Transport pass | Retry events | Mean FPGA seconds | Mean pixels/s | vs XC7K70T 6w/4ctx 200MHz |
|---|---:|---:|---:|---:|---:|
| fast escape @128 | `10/10` | `4` | `4.563` | `468446.75` | `1.017x` |
| standard @64 | `10/10` | `2` | `4.353` | `480268.18` | `1.065x` |
| Seahorse zoom @512 | `10/10` | `2` | `4.499` | `467436.73` | `1.270x` |
| deep tendrils @8192 | `10/10` | `3` | `4.739` | `441838.90` | `1.808x` |
| deep mini-brot @8192 | `10/10` | `6` | `10.146` | `206484.60` | `2.066x` |
| deep Seahorse @1024 | `10/10` | `2` | `4.967` | `420129.06` | `1.946x` |

The improvement pattern is important. Fast escape and standard scenes move only modestly because UART, host parsing, response packetization, command overhead, and raster-order collection are already significant. Deep scenes improve much more because more workers and more contexts increase FP pipeline occupancy and row-level throughput.

### Resource Cost And Architectural Decision

The accepted ZU4EV point nearly exhausts LUT capacity while leaving DSP and BRAM capacity mostly unused:

| Metric | 6w/4ctx baseline | 12w/8ctx accepted | Increase |
|---|---:|---:|---:|
| CLB LUTs | `30057` (`34.22%`) | `85171` (`96.96%`) | `2.83x` |
| CLB Registers | `27099` (`15.43%`) | `71453` (`40.67%`) | `2.64x` |
| BRAM Tiles | `13.5` (`10.55%`) | `25.5` (`19.92%`) | `1.89x` |
| DSPs | `61` (`8.38%`) | `121` (`16.62%`) | `1.98x` |

The repository default is now the ZU4EV 12-worker/8-context direct-200MHz build. It is timing-clean, passes simulation, has been programmed and verified on hardware, and improves every measured scene against the previous best 7K70T 200MHz point. Because LUT utilization is already `96.96%` and the worst path is route dominated, the next architecture step should not be naive worker replication. The next useful compute-side changes are localizing command-parameter fanout, reducing per-context LUT pressure, grouping/floorplanning workers if needed, or adding a higher-bandwidth transport so the existing compute capacity is easier to observe on fast scenes.

## Architectural Lessons

### Streaming Was The Right Initial Choice

Streaming kept memory use low and allowed early board validation with a simple UART protocol. The same stream contract survived the transition from one core to four cores.

### The Host Protocol Became Both Strength And Constraint

The raster-order protocol made validation simple and backward-compatible. It also forced the FPGA to reorder internally, which limits future scheduling flexibility. This is acceptable for 4 cores over UART, but not ideal for higher bandwidth or more cores.

### Timing Closure Required Data Path Changes, Not Constraints

The true 100 MHz stage succeeded because long FP logic cones were pipelined. Removing multicycle constraints simplified STA and made multi-core replication safer.

### 4 Cores Were A Good Match For The 576000 Baud Stage

At the 576000 baud stage, four workers were enough to push many compute-heavy scenes near the UART ceiling (~28800 pps). More workers would have consumed resources while often waiting on UART unless the scene was extremely compute-bound.

At 12 Mbaud, that conclusion changes. Fast scenes are still transport-sensitive, but several deep scenes now expose compute/raster-order limits. The timing-fixed 6-worker direct-200MHz build demonstrates that modest worker replication is still valuable on XC7K70T when the route-dominated scheduler/control paths are cut carefully. However, the failed 8-worker direct-200MHz placement shows that simply adding more identical workers is near the device limit.

### Dynamic Row Scheduling Is Now The Default Scheduling Layer

The original 4-core implementation deliberately separated dispatch and merge logic. That boundary has now been exercised by making dynamic row scheduling the default path while keeping static scheduling as a regression mode:

| Mode | Dispatcher | Collector | Protocol |
|---|---|---|---|
| Static regression | `work_dispatch_static_rows` | `raster_merge_static_rows` | Existing raster stream. |
| Dynamic default | `work_dispatch_dynamic_rows` | `raster_collect_dynamic_rows` | Existing raster stream. |

Dynamic mode assigns one full row at a time to an idle core and records row ownership. The collector still emits rows in order, so the host does not change. The dispatcher now waits for a core's per-core FIFO to become empty before reusing that core. This prevents large UART-bound frames from deadlocking under strict raster output when compute runs ahead of transmit.

Why the measured speedup is effectively zero:

| Cause | Effect |
|---|---|
| UART-bound views already ran at about 99% of the 576000 baud pixel ceiling | A better scheduler could not send pixels faster than the old UART. |
| Static interleaved rows already spread smooth Mandelbrot row costs across all four cores | Dynamic assignment has little tail imbalance to recover. |
| Dynamic mode uses one-row jobs to reuse the existing worker safely | Each row repeats worker startup work, which consumes part of any balancing gain. |
| The collector still emits strict raster order | A slow earlier row can still hold the output stream even if later rows completed. |
| High-iteration views are dominated by the worker FSM and `PIPE_WAIT=10` FP latency | Row scheduling does not increase per-worker FP issue utilization. |

The architectural value is therefore not just immediate throughput. It validates that the dispatch/collection boundary can be replaced without touching UART, command parsing, FP datapaths, or host protocol, and it remains the scheduling layer used by the current ZU4EV 12-worker/8-context default build.

Validation after adding this mode:

| Command | Result |
|---|---|
| `../sim_multicore.tcl` | `=== MULTICORE TEST PASS: 192 pixels ===` |
| `../sim_multicore_dynamic.tcl` | `=== DYNAMIC MULTICORE TEST PASS: 192 pixels ===` |
| `../build_fp64.tcl` | Static bitstream generated, timing met. |
| `../build_fp64_dynamic.tcl` | Dynamic bitstream generated, timing met. |

## Recommended Next Evolution

The next major improvement should target routing pressure, protocol resilience, and transport bandwidth before adding more compute cores.

```mermaid
flowchart LR
    NOW[Current ZU4EV 12w/8ctx raster UART] --> FANOUT[Reduce parameter fanout and LUT pressure]
    FANOUT --> LINK[Higher bandwidth link]
    LINK --> PROTO[Coordinate-tagged rows/tiles]
    PROTO --> SCHED[Dynamic tile scheduler]
    SCHED --> CORES[More workers only with lower routing/resource pressure]
```

Recommended order:

| Priority | Step | Reason |
|---:|---|---|
| 1 | Keep ZU4EV 12-worker/8-context direct-200MHz as the performance default | It is the fastest timing-clean, board-benchmarked point so far. |
| 2 | Reduce command-parameter fanout and worker-local routing pressure | The accepted ZU4EV build is LUT-heavy and its worst path is route dominated, not arithmetic-depth dominated. |
| 3 | Add sequence numbers and true retransmission | Current `RT`/`TD`/`TE` packets detect errors, and host-driven tiling can recompute a stripe, but the FPGA still cannot retransmit one packet. |
| 4 | Add request IDs and stronger row/tile IDs | Enables resynchronization, duplicate rejection, and out-of-order completion beyond the current raster collector. |
| 5 | Add a higher-bandwidth transport | USB FIFO, SPI, Ethernet, or PS memory mapping would remove UART/driver burst limits. |
| 6 | Keep XC7K70T 4-worker/6-worker 200MHz and 100MHz 4ctx data as explicit historical references | They remain useful for regression and architecture comparison, but they are no longer the active default. |
| 7 | Extend row-level dynamic scheduling to dynamic tiles | Improves load balance on localized deep zooms once output can be tagged. |
| 8 | Revisit more workers only with lower-route-pressure structure | The current ZU4EV point already uses `96.96%` CLB LUTs. |
| 9 | Add mathematical interior tests | Cardioid/period-2 bulb rejection can reduce compute for standard views. |

## Summary

The project evolved through a pragmatic sequence:

1. Build a correct single-core streaming renderer.
2. Close true 100 MHz FP64 timing.
3. Raise UART bandwidth safely to 576000 baud via systematic integer-divider sweep, raw-probe, and TX-only isolation experiments.
4. Perform UART timing analysis proving FPGA RX was the old high-baud failure root.
5. Study multi-core scaling under the unchanged raster protocol.
6. Implement 4-core interleaved-row workers with a modular scheduler and raster merger.
7. Analyze and document FP64 boundary differences (truncation vs RNE rounding, chaotic amplification).
8. Add a dynamic idle-core row scheduler and matching raster collector, now used by default.
9. Add a two-context worker with tagged FP writeback and ordered commit.
10. Fix dynamic row reuse under UART backpressure by requiring an empty per-core FIFO before assigning another row to a core.
11. Replace integer UART timing with a fractional baud accumulator and validate 12 Mbaud full-protocol operation.
12. Add tiled response framing and host-driven 1920x120 stripe retries to make 12 Mbaud operation recoverable at tile granularity.
13. Make the validated 4-context generic worker the XC7K70T default, confirming the context-scaling performance direction while exposing the LUT cost.
14. Close and validate direct-200MHz 4ctx using request-sliced FPU issue and corrected tag latency.
15. Replicate the validated 4ctx worker to six direct-200MHz workers, fix route-dominated dispatcher/worker-control timing, and make the timing-clean 6-worker XC7K70T result the default for that stage.
16. Migrate the active target to VMC_RTSB ZU4EV with single-ended `sys_clk` on `E12`, clean ZU4EV constraints, Vivado auto-connect programming, and `COM6` host defaults.
17. Scale the ZU4EV default to 12 workers and 8 contexts per worker, preserving `MUL_LAT=6`, `ADD_LAT=9`, direct 200MHz timing, dynamic row scheduling, and the existing UART command/response protocol.

The current design preserves the original host command protocol while running the active VMC_RTSB ZU4EV target at direct 200 MHz, `12 Mbaud`, 12 workers, and 8 contexts per worker. Fast 1080p scenes now average about `468k-480k pixels/s` across the 10-run set, and the accepted ZU4EV default raises deep mini-brot from the previous XC7K70T 6-worker/4-context 200MHz `20.963s` mean to a ZU4EV 10-run mean of `10.146s` (`2.066x`). Relative to the previous best 7K70T 200MHz point, the ZU4EV 12w/8ctx build improves every measured scene, with the largest gains in deep compute-heavy views. The next major architecture step is no longer another integer baud tweak or naive worker replication; it is reducing route/fanout pressure, strengthening packet/request identity, adding true retransmission or a higher-bandwidth transport, and only then revisiting additional compute parallelism.
