# Compute Pipeline Bubble Analysis And De-Bubbling Feasibility

This report analyzes the bubble situation in the current Mandelbrot compute worker, explores multi-context in-worker scheduling, discusses tagged out-of-order pixel completion and reorder before commit, compares different `fp_mul`/`fp_add` allocations per worker, and estimates theoretical compute and whole-system performance benefits.

The short version: the current worker leaves most FP pipeline issue slots empty. The most efficient way to recover those bubbles is not simply adding more top-level workers. It is to keep several pixel contexts active inside each worker, tag FP results by context, allow pixel contexts to complete out of order, and reorder them before committing to the existing row/raster stream. However, with the current 576000 baud UART output path, most visible whole-system gains are capped unless transport/protocol bandwidth is also improved.

## Current Context

Current implemented accelerator:

| Item | Value |
|---|---:|
| FP mode | FP64 |
| System clock | 100 MHz |
| Worker count | 4 |
| FP clock enable | `FP_CE_DIV=1` |
| Worker FP wait | `PIPE_WAIT=10` |
| Effective result latency used by FSM | `PIPE_WAIT + 1 ~= 11 cycles` |
| Per worker FP units | 1 multiplier + 1 adder |
| UART | 576000 baud |
| UART pixel ceiling | `28800 pixels/s` |
| Output protocol | strict raster-order 16-bit pixels |

The current design is latency scheduled, not throughput scheduled. Each worker issues an FP operation, waits `PIPE_WAIT` cycles, consumes the result, and then issues the next dependent operation. The FP units are internally pipelined, but the worker FSM normally feeds a given unit only once every 11 cycles.

## Current Per-Iteration Schedule

For a non-escaping Mandelbrot iteration, one worker performs these FP operations:

| Step | Multiplier issue | Adder issue | Wait after issue | Purpose |
|---:|---|---|---:|---|
| 1 | `z_re * z_re` | none | 10 | Produce `z_re_sq`. |
| 2 | `z_im * z_im` | none | 10 | Produce `z_im_sq`. |
| 3 | `z_re * z_im` | `z_re_sq + z_im_sq` | 10 | Produce cross product and escape sum. |
| 4 | none | `z_re_sq - z_im_sq` | 10 | Real-part difference. |
| 5 | none | `diff + c_re` | 10 | Next real part. |
| 6 | none | `z_re_z_im + z_re_z_im` | 10 | Double cross product. |
| 7 | none | `2*z_re*z_im + c_im` | 10 | Next imaginary part. |

Useful first-order estimate:

```text
cycles_per_non_escape_iteration ~= 7 * (PIPE_WAIT + 1)
                                 ~= 7 * 11
                                 ~= 77 cycles
```

Operation count per non-escaping iteration:

```text
3 multiplier issues
5 adder issues
```

The adder and multiplier can both be issued during step 3, but otherwise most issue slots use only one of the two FP units.

## Bubble Diagram

`M` is a multiplier issue, `A` is an adder issue, and `.` is an idle feed cycle for that unit.

```text
Issue slot:  1           2           3           4           5           6           7
Cycle span:  0..10       11..21      22..32      33..43      44..54      55..65      66..76
Multiplier:  M.......... M.......... M.......... ........... ........... ........... ...........
Adder:       ........... ........... A.......... A.......... A.......... A.......... A..........
```

The core bubble problem is therefore not that the FP pipelines are too slow to accept work. It is that a single pixel context does not have enough independent work to feed them while waiting for dependent results.

## Current FP Issue Utilization

Assuming 77 cycles per non-escaping iteration:

| Unit | Useful issues per iteration | Available issue cycles | Approximate issue utilization |
|---|---:|---:|---:|
| Multiplier | 3 | 77 | `3.9%` |
| Adder | 5 | 77 | `6.5%` |
| Combined FP issue slots | 8 | 154 | `5.2%` |

This is why adding pipeline stages to close timing was still beneficial, but the resulting FP pipelines remain heavily underfed.

## Dependency Graph And Lower Bounds

For one non-escaping iteration, the true mathematical dependency graph is shorter than the current 7-wait sequential schedule.

```text
z_re,z_im
  |\
  | +--> z_re*z_im ------------------> double --> next_im
  |
  +----> z_re*z_re ----+
                       +--> escape sum
  +----> z_im*z_im ----+
                       +--> z_re_sq - z_im_sq --> next_re
```

With enough FP units for one pixel, the minimum latency for one iteration is roughly three FP result latencies:

```text
single-context dependency latency ~= 3 * (PIPE_WAIT + 1)
                                  ~= 33 cycles
```

That is still latency, not throughput. Throughput is limited by how many FP operations can be issued per cycle across many independent pixel contexts.

For a worker with `M` multipliers and `A` adders, the ideal issue-limited cycles per non-escaping iteration are:

```text
T_issue = max(3 / M, 5 / A) cycles/iteration
```

This assumes enough independent pixel contexts exist to hide the roughly 33-cycle dependency latency.

## How Many Pixels Can Be In Flight Inside One Worker?

### Rule Of Thumb

With `PIPE_WAIT=10`, one result stream needs about 11 independent contexts to hide one operation latency. More generally, for a fully scheduled multi-context worker:

```text
minimum_contexts ~= ceil(single_context_dependency_latency / T_issue)
                 ~= ceil(33 / T_issue)
```

Practical designs need extra contexts for branch divergence, context refill/drain, output backpressure, row transitions, and phase conflicts.

| Worker FP units | Ideal `T_issue` | Mathematical minimum contexts | Practical context range |
|---|---:|---:|---:|
| 1 mul + 1 add | 5.00 cycles/iter | 7 | 8 to 16 |
| 1 mul + 2 add | 3.00 cycles/iter | 11 | 12 to 20 |
| 2 mul + 1 add | 5.00 cycles/iter | 7 | 8 to 16 |
| 2 mul + 2 add | 2.50 cycles/iter | 14 | 16 to 24 |
| 2 mul + 3 add | 1.67 cycles/iter | 20 | 24 to 32 |
| 3 mul + 5 add | 1.00 cycles/iter | 33 | 40+ |

### Context Count Versus Throughput For 1 Mul + 1 Add

For the existing one-multiplier/one-adder worker, a simple utilization model is:

```text
cycles_per_iteration ~= max(77 / contexts, 5)
```

The `5` comes from the adder bottleneck: one adder must issue 5 operations per iteration.

| Contexts per worker | Approx cycles/iter | Ideal speedup vs current worker | Assessment |
|---:|---:|---:|---|
| 1 | 77.0 | 1.0x | Current design. |
| 2 | 38.5 | 2.0x | Good simulation milestone. |
| 4 | 19.3 | 4.0x | Significant, still simple enough to debug. |
| 8 | 9.6 | 8.0x | Starts hiding most latency. |
| 12 | 6.4 | 12.0x | Near useful saturation. |
| 16 | 5.0 | 15.4x | Near ideal for 1 mul + 1 add. |

In practice, 8 to 16 contexts is the likely useful range for the current FP-unit allocation. Below 8 contexts, many pipeline bubbles remain. Above 16 contexts, the one-adder issue limit dominates and extra contexts mostly add control complexity.

## Required Context State

Each active pixel context needs at least:

| Field | Width |
|---|---:|
| `c_re`, `c_im` | 128 bits total FP64 |
| `z_re`, `z_im` | 128 bits total FP64 |
| `z_re_sq`, `z_im_sq`, `z_re_z_im` | 192 bits total FP64 |
| `iter` | 16 bits |
| row/col or sequence tag | 32 to 48 bits |
| phase/state metadata | 8 to 16 bits |
| pending FP tags/status bits | 8 to 32 bits |

Rough storage estimate:

```text
500 to 650 bits per context
```

Example storage cost:

| Contexts | Per worker | Four workers |
|---:|---:|---:|
| 4 | 2.0 to 2.6 kbits | 8 to 10 kbits |
| 8 | 4.0 to 5.2 kbits | 16 to 21 kbits |
| 16 | 8.0 to 10.4 kbits | 32 to 42 kbits |
| 32 | 16.0 to 20.8 kbits | 64 to 83 kbits |

The raw storage is feasible. The expensive parts are the FP64 operand muxes, result writeback muxes, ready queues, hazard tracking, and verification.

## Tagged Out-Of-Order Pixel Completion Inside A Worker

A multi-context worker will not naturally finish pixels in raster order. Different pixels escape at different iteration counts, and contexts may be at different phases. Therefore each context needs a tag.

Minimum tag fields:

| Field | Purpose |
|---|---|
| `context_id` | Routes FP results back to the correct context. |
| `pixel_seq` | Restores worker-local pixel order before commit. |
| `row`, `col` | Optional explicit output coordinates, useful for global tagged output. |
| `phase` | Indicates which operation result is being written back. |

### FP Result Tagging

Each issued FP operation carries metadata through a delay line matching the FP pipeline latency:

```text
issue:    op_a, op_b, context_id, destination_field, phase
latency:  fp_add/fp_mul pipeline
writeback: result -> context[context_id].destination_field
```

This turns the current single-FSM capture states into a small scoreboard/writeback system.

### Pixel Commit Reorder

There are two viable commit policies.

| Policy | Description | Pros | Cons |
|---|---|---|---|
| Ordered commit inside worker | Contexts complete out of order, but a reorder ring emits only `next_pixel_seq`. | Preserves existing per-core FIFO contract. | A slow early pixel can block later completed pixels inside the worker. |
| Tagged output from worker | Worker emits `{row,col,iter}` or `{seq,iter}` as soon as a pixel completes. | Removes worker-local commit stalls. | Requires wider FIFOs and a downstream reorder/packet protocol. |

For near-term compatibility, ordered commit inside each worker is not optional; it is required even for the first 2-context prototype. With two active pixels, either pixel may escape first. If context 1 escapes after 5 iterations while context 0 remains inside until 200 iterations or `max_iter`, the worker would naturally produce context 1 first. Without a sequence tag and reorder buffer, the per-core FIFO would receive pixels in the wrong order and the existing raster merger would silently corrupt the image.

Therefore the minimum multi-context worker must include both:

```text
out-of-order context completion
ordered commit by pixel_seq before writing the worker FIFO
```

Tagged output from the worker is a longer-term alternative after protocol v2 or a downstream reorder layer exists. For the current raster-compatible design, every multi-context prototype must reorder before commit.

### Reorder Buffer Size

If the worker has `C` contexts, a local reorder ring of at least `C` pixel entries is required. More is useful because a long-running interior pixel can block many later fast-escaping pixels.

| Worker contexts | Minimum local commit buffer | Practical buffer |
|---:|---:|---:|
| 4 | 4 pixels | 8 to 16 pixels |
| 8 | 8 pixels | 16 to 32 pixels |
| 16 | 16 pixels | 32 to 64 pixels |
| 32 | 32 pixels | 64+ pixels |

Each committed pixel is only 16 bits plus valid/tag state if the buffer is local and ordered. If the output is globally tagged, each entry needs row/col or sequence metadata.

## Per-Worker FP Unit Allocation Options

The current worker has 1 multiplier and 1 adder. A non-escaping iteration needs 3 multiplier issues and 5 adder issues. Therefore, with enough contexts:

```text
ideal_cycles_per_iteration = max(3 / mul_count, 5 / add_count)
```

Theoretical per-worker compute speedup versus the current 77-cycle latency-scheduled worker:

| Per-worker units | Ideal cycles/iter | Ideal worker speedup | Bottleneck | Notes |
|---|---:|---:|---|---|
| 1 mul + 1 add | 5.00 | 15.4x | adder | Best first de-bubbling target. No extra DSPs. |
| 1 mul + 2 add | 3.00 | 25.7x | multiplier | Good if adders are cheap enough and contexts >= 12. |
| 1 mul + 3 add | 3.00 | 25.7x | multiplier | No gain over 2 adders with one multiplier. |
| 2 mul + 1 add | 5.00 | 15.4x | adder | Extra multiplier gives no ideal throughput gain. |
| 2 mul + 2 add | 2.50 | 30.8x | adder | Strong but DSP-heavy. |
| 2 mul + 3 add | 1.67 | 46.2x | mixed | Very aggressive; needs many contexts. |
| 3 mul + 5 add | 1.00 | 77.0x | balanced issue | Theoretical limit, impractical on this device. |

### Resource Consequences

The current 4-worker FP64 design uses 38 DSP48E1 blocks. The practical planning model is still about 9 DSPs per FP64 multiplier-heavy worker plus shared overhead.

Additional FP64 multipliers are expensive. Additional FP64 adders mainly consume LUTs/registers and routing.

Approximate DSP scaling for four workers:

| Per-worker multipliers | Estimated DSP48E1 use | Feasibility on 80 DSP device |
|---:|---:|---|
| 1 | 38 | Current, comfortable. |
| 2 | about 74 | Possible but high routing/timing risk. |
| 3 | about 110 | Not feasible on Zynq-7010. |

This makes `1 mul + 1 add` multi-context interleaving the most attractive first architecture. `1 mul + 2 add` may be a second step because it avoids extra DSP pressure. `2 mul + 2 add` is only attractive after transport bandwidth is improved and if timing still closes.

## Architecture Options Compared

| Option | Contexts | FP units per worker | Ideal compute gain per worker | Resource risk | Verification risk | Current UART-visible gain |
|---|---:|---|---:|---|---|---|
| Current worker | 1 | 1M + 1A | 1.0x | low | low | current |
| 2-context prototype | 2 | 1M + 1A | 2.0x | low | medium | limited |
| 4-context prototype | 4 | 1M + 1A | 4.0x | low-medium | medium | limited except mini-brot |
| 8-context worker | 8 | 1M + 1A | about 8.0x | medium | high | capped by UART for most scenes |
| 16-context worker | 16 | 1M + 1A | up to 15.4x | medium-high | high | capped by UART except very compute-heavy scenes |
| 12 to 20 contexts | 1M + 2A | up to 25.7x | high LUT/routing | very high | mostly capped by UART |
| 16 to 24 contexts | 2M + 2A | up to 30.8x | high DSP/routing | very high | mostly capped by UART |
| 24+ contexts | 2M + 3A | up to 46.2x | very high | very high | not useful before transport upgrade |

## Whole-System Performance Model At 576000 Baud

With current UART:

```text
new_pps = min(current_pps * compute_speedup, 28800)
```

This cap dominates many scenes. Even an ideal de-bubbled worker cannot exceed the UART ceiling unless output bandwidth improves.

| Scene | Current 4-core 576k | UART-capped maximum | Max visible speedup |
|---|---:|---:|---:|
| Fast escape @128 | 28508.56 pps | 28800 pps | 1.01x |
| Standard @64 | 28508.82 pps | 28800 pps | 1.01x |
| Seahorse zoom @512 | 27921.47 pps | 28800 pps | 1.03x |
| Deep tendrils @8192 | 22079.29 pps | 28800 pps | 1.30x |
| Deep mini-brot @8192 | 8852.78 pps | 28800 pps | 3.25x |
| Deep seahorse @1024 | 20600.46 pps | 28800 pps | 1.40x |

This is why current UART suppresses most benefits from compute de-bubbling. Deep mini-brot remains the one measured scene with large visible headroom.

## Implemented 2-Context RTL Results

The first synthesizable de-bubbling step has now been implemented in `rtl/mandelbrot_core_worker_2ctx.v` and selected by `WORKER_CONTEXTS=2`. The design keeps the original four workers and keeps one FP64 multiplier plus one FP64 adder per worker. It adds a second pixel context inside each worker and interleaves the two contexts over the existing FP units.

### RTL Architecture

| Block | Implementation detail |
|---|---|
| Context table | Two sets of `z`, `c`, iteration, intermediate, state, and result registers. |
| Shared FP units | One `fp_mul` and one `fp_add` per worker, unchanged in count. |
| FP tags | `mul_op_pipe`/`mul_ctx_pipe` and `add_op_pipe`/`add_ctx_pipe` route delayed results. |
| Ordered commit | `commit_col` writes only the next worker-local column to the per-core FIFO. |
| Row launch | `launch_col` starts new contexts while `c_re_next` tracks the next column coordinate. |
| Dynamic scheduler guard | A core receives a new row only after its per-core FIFO is empty, avoiding UART-backpressure deadlock. |

The important timing lesson is that the tag delay is not the old single-context `PIPE_WAIT + 1` guard. The old worker waited conservatively between issue and capture. A back-to-back tagged worker must match the real FPU input-to-output latency as observed from the worker issue point:

| Unit | RTL tag latency |
|---|---:|
| `fp_mul` | `MUL_LAT=6` |
| `fp_add` | `ADD_LAT=7` |

Using `11/11` tag delays allowed simulations to finish but produced repeatable board mismatches concentrated on odd columns, because adjacent-context results were written back under the wrong delayed tag. Correcting the tag delays made both simulation and board verification match exactly.

### Validation

| Check | Result |
|---|---|
| 32x24 dynamic 2ctx simulation, `step=0.02`, `max_iter=64` | `768/768` matched. |
| 64x48 dynamic 2ctx stress simulation | `3072` pixels, `1317934` cycles. |
| Static 1ctx regression simulation | Passed. |
| Routed timing | `WNS=0.091ns`, `TNS=0.000ns`, `WHS=0.011ns`, `THS=0.000ns`. |
| Placed utilization | 13630 LUTs, 14391 registers, 38 DSP48E1, 9.5 BRAM tiles. |
| Board 32x24 verify | `768/768` matched. |
| Board 160x120 verify | `19200/19200` matched. |

### Measured 1080p Performance

All measurements use 576000 baud UART, 1920x1080 frames, FP64, four workers, dynamic rows, and two contexts per worker.

| Scene | 4-core 1ctx 576k | 4-core 2ctx 576k | 2ctx throughput | Measured speedup | UART ceiling use |
|---|---:|---:|---:|---:|---:|
| Fast escape @128 | `72.736s` | `72.720s` | `28514.74 pps` | `1.000x` | `99.0%` |
| Standard @64 | `72.735s` | `72.721s` | `28514.28 pps` | `1.000x` | `99.0%` |
| Seahorse zoom @512 | `74.265s` | `72.790s` | `28487.54 pps` | `1.020x` | `98.9%` |
| Deep tendrils @8192 | `93.916s` | `72.781s` | `28491.11 pps` | `1.290x` | `98.9%` |
| Deep mini-brot @8192 | `234.231s` | `83.708s` | `24771.84 pps` | `2.798x` | `86.0%` |
| Deep seahorse @1024 | `100.658s` | `72.776s` | `28493.04 pps` | `1.383x` | `98.9%` |

### Theory Versus Measurement

The local 2-context model predicted up to `2x` worker-level speedup for balanced adjacent-pixel traces and much less for pathological ordered-commit traces. The full-system measurement must additionally pass through the UART cap:

```text
visible_pps = min(compute_pps_after_2ctx, 28800 pps)
```

That explains the measured table:

| Case | Interpretation |
|---|---|
| Fast escape and standard | Already UART-bound before 2ctx; compute improvement is hidden. |
| Seahorse zoom | Had only about 3% visible headroom; measured improvement is small and capped. |
| Deep tendrils and deep seahorse | Had 30-40% visible UART headroom; 2ctx fills it and reaches the UART ceiling. |
| Deep mini-brot | Still compute-bound after 2ctx, so it shows the largest speedup, `2.80x`. |

The `2.80x` whole-system speedup on mini-brot is larger than the simple 2-context local model's balanced `2x` because the implemented worker is not just alternating two complete old FSMs. It also issues independent multiplier and adder operations through tagged pipelines with shorter true FPU latencies (`6/7`) than the old conservative single-context wait model (`11`). It still does not approach the ideal `15.4x` for a fully saturated `1M+1A` worker because two contexts are far below the 8-16 contexts needed to hide most dependency latency.

## Whole-System Model With Faster Output

If the output path allowed 100000 pixels/s, a compute-speedup of 8x from a practical 8-context `1M+1A` worker would become much more visible:

| Scene | Current 4-core 576k | 8x compute model with 100k pps output cap | Visible speedup |
|---|---:|---:|---:|
| Seahorse zoom @512 | 27921 pps | 100000 pps cap | 3.58x |
| Deep tendrils @8192 | 22079 pps | 100000 pps cap | 4.53x |
| Deep mini-brot @8192 | 8853 pps | 70822 pps | 8.00x |
| Deep seahorse @1024 | 20600 pps | 100000 pps cap | 4.85x |

This shows the architectural dependency: de-bubbling is compute-significant, but it should be paired with transport/protocol improvement to be system-significant.

## Recommended De-Bubbled Worker Architecture

## 2-Context Prototype Model And Results

Before changing synthesizable worker RTL, a cycle model was added to validate the scheduling rules and quantify best/worst-case behavior for a two-context worker:

| File | Purpose |
|---|---|
| `python/pipeline_2ctx_model.py` | Cycle model for 1-context vs 2-context FP issue scheduling, tagged completion, and ordered commit. |
| `sim_worker_2ctx_model.tcl` | Convenience Tcl wrapper that runs the model with a fast default trace. |

This is a performance/timing model, not a bitstream replacement. It exists to verify the 2-context design requirements before committing to a larger RTL rewrite.

### Modeled 2-Context Timing Plan

The model uses the current worker's operation sequence and current latency assumption:

```text
PIPE_WAIT = 10
modeled FP result latency = PIPE_WAIT + 1 = 11 cycles
```

Each context owns one pixel and advances through the same per-iteration stages as the RTL worker:

```text
M, M, MA, A, A, A, A
```

Where:

| Symbol | Meaning |
|---|---|
| `M` | Issue one multiplier operation. |
| `A` | Issue one adder operation. |
| `MA` | Issue multiplier and adder in the same cycle, matching `S_MUL_ZISQ_CAPT`. |

The 2-context scheduler has one multiplier issue slot and one adder issue slot per cycle. It scans contexts, issues the first context whose next stage is ready and whose required FP unit is free, then records the next ready cycle:

```text
context.ready_cycle = current_cycle + 11
```

This models the essential timing behavior of a tagged writeback worker: a context cannot consume a result until the FP latency has elapsed, but the other context can issue independent work during that wait.

### Mandatory Ordered Commit In The Model

The model includes the required sequence-based commit mechanism from the start. Each context has:

```text
context_id
pixel_seq
done flag
iter_count result
```

When a context finishes, it writes its result into `done_table[pixel_seq]`. The output side only commits `next_commit_seq`:

```text
when context finishes:
    done_table[context.pixel_seq] = iter_count

while done_table[next_commit_seq] is valid:
    commit done_table[next_commit_seq]
    next_commit_seq++
```

This intentionally models the correctness constraint that a 2-context worker cannot simply write whichever pixel finishes first. If pixel 1 escapes quickly while pixel 0 runs for many iterations, pixel 1 must wait in the reorder table until pixel 0 commits.

### Test Command

Fast default run:

```bash
python python\pipeline_2ctx_model.py --width 32 --height 24 --max-iter 64 --center -0.5 0.0 --step 0.02 --pixels 512
```

Equivalent wrapper:

```bash
vivado -mode batch -source sim_worker_2ctx_model.tcl
```

The Tcl wrapper just executes the Python model. It does not launch HDL simulation.

### 2-Context Model Results

Measured model output:

| Trace | Pixels | Avg iter | 1-context cycles | 2-context cycles | Speedup | Max reorder occupancy | Ordered-commit wait cycles |
|---|---:|---:|---:|---:|---:|---:|---:|
| Real small frame | 768 | 61.61 | 3,636,874 | 1,827,819 | 1.99x | 2 | 16,321 |
| Uniform short | 512 | 1.00 | 51,201 | 25,603 | 2.00x | 1 | 0 |
| Uniform long | 512 | 64.00 | 2,518,017 | 1,259,011 | 2.00x | 1 | 0 |
| Alternating long/short | 512 | 32.50 | 1,284,609 | 1,259,010 | 1.02x | 2 | 1,233,152 |
| Long head, short tail | 512 | 1.12 | 56,019 | 30,421 | 1.84x | 2 | 4,817 |
| Banded synthetic | 512 | 19.00 | 756,609 | 378,307 | 2.00x | 1 | 0 |

### Result Interpretation

The 2-context model behaves exactly as the dependency analysis predicts:

| Case | Interpretation |
|---|---|
| Uniform short/long | Both contexts have similar work. Latency hiding is effective and speedup reaches about 2x. |
| Real small frame | Adjacent Mandelbrot pixels are similar enough that the two contexts stay balanced; speedup is about 1.99x. |
| Banded synthetic | Work is grouped, so adjacent contexts still see similar work; speedup remains about 2x. |
| Long head, short tail | One early long-running pixel blocks later ordered commits, but the second context still helps after the head clears; speedup is 1.84x. |
| Alternating long/short | Worst case for ordered commit. Every short pixel finishes behind a long predecessor and waits; speedup collapses to 1.02x. |

This proves that two pixels in flight are not enough by themselves. Correctness requires reorder-before-commit, and performance depends strongly on whether ordered commit blocks on long-running earlier pixels.

### Expected Versus Measured Model

The theoretical upper bound for two contexts is near 2x because, with only two independent pixels, at most two single-context latency gaps can be overlapped. The measured model reaches that upper bound for balanced traces. It falls below the upper bound only when ordered commit serializes a short pixel behind a long earlier pixel.

| Expectation | Model result |
|---|---|
| Balanced two-context traces should approach 2x. | Confirmed: real small frame, uniform, and banded traces are about 1.99x-2.00x. |
| Out-of-order completion must be handled. | Confirmed: reorder occupancy reaches 2 and commit waits appear on nonuniform traces. |
| Pathological alternating long/short traces can defeat ordered commit. | Confirmed: speedup drops to 1.02x with 1.23M commit-wait cycles. |
| More contexts are needed for robust throughput. | Confirmed: 2 contexts are a correctness and timing proof, not the final performance target. |

### Design Implication

The next RTL implementation should not try to build a two-context worker that simply alternates pixels and writes outputs directly. The minimum correct RTL block must include:

| Required block | Reason |
|---|---|
| Context table with two entries | Stores per-pixel state and phase. |
| FP operation tags | Routes delayed `fp_add`/`fp_mul` results to the right context. |
| Per-context completion state | Allows a later pixel to finish before an earlier one. |
| Sequence reorder table | Holds completed results until `next_commit_seq` is ready. |
| Ordered commit FSM | Preserves current per-core FIFO/raster merger contract. |

The model also shows why the real performance target should be 8 to 16 contexts. Two contexts validate the mechanism and can reach 2x on balanced traces, but they cannot keep FP units close to saturation and are vulnerable to ordered-commit stalls.

### Stage 1: Simulation-Only Multi-Context Worker

Start with `1 mul + 1 add` and 2 contexts. Do not add FP units yet. The 2-context design must already include out-of-order completion tracking and ordered commit, because two pixels do not necessarily finish in issue order.

Goals:

| Goal | Reason |
|---|---|
| Context table | Holds per-pixel `z`, `c`, iteration, phase, and sequence tag. |
| Tagged FP writeback | Proves result routing by `context_id`. |
| Simple ready queues | Selects contexts ready to issue multiplier or adder operations. |
| Completion flags per context | Records pixels that finish before earlier sequence numbers. |
| Ordered local commit by `pixel_seq` | Mandatory even for 2 contexts; preserves existing worker output order. |

Minimum 2-context commit behavior:

```text
next_commit_seq = first pixel sequence assigned to the worker

when context finishes:
    done_table[context.pixel_seq] = iter_count

while done_table[next_commit_seq] is valid and output FIFO has space:
    write done_table[next_commit_seq] to worker output FIFO
    clear done_table[next_commit_seq]
    next_commit_seq++
```

This is deliberately more complex than simply alternating two contexts, but it is the smallest correct design. A two-context worker without ordered commit can pass some uniform-cost tests but fail on normal Mandelbrot views where adjacent pixels escape at different iterations.

### Stage 2: Scale Context Count

Scale 2 -> 4 -> 8 -> 16 contexts while keeping `1M+1A`.

Expected milestones:

| Contexts | Expected result |
|---:|---|
| 2 | Confirms tagged writeback, out-of-order completion, and mandatory local reorder. |
| 4 | Should show clear simulation cycle reduction. |
| 8 | Hides most latency. |
| 16 | Near-saturates `1M+1A` issue limits. |

### Stage 3: Output Tagging Beyond The Worker

After the worker-local ordered commit path is stable, choose whether to keep that compatibility layer or move to a wider tagged output path:

| Policy | When to use |
|---|---|
| Ordered worker-local commit | Required for current multicore/raster merger. Keep this for compatibility. |
| Tagged worker output | Best after protocol v2 or tile/row tagged output exists. |

For long-term performance, tagged output is preferable because it allows later fast pixels to leave the worker immediately. This should be treated as a second output architecture after the basic worker-local reorder has already been proven.

### Stage 4: Evaluate More Adders Before More Multipliers

If `1M+1A` with 16 contexts is proven and transport is no longer the bottleneck, evaluate `1M+2A`. It improves the ideal issue limit from 5 cycles/iter to 3 cycles/iter without adding DSP-heavy FP multipliers.

Only after that should `2M+2A` be considered. It consumes most of the remaining DSP budget on the current device.

## Practical Recommendation

Recommended priority:

| Priority | Work | Reason |
|---:|---|---|
| 1 | Higher-bandwidth output path | Current UART hides most compute gains. |
| 2 | Tagged row/tile protocol | Enables out-of-order worker/tile completion without large FPGA reorder buffers. |
| 3 | Scale the proven 2-context RTL to 4/8 contexts | The 2-context worker is now correct on board; more contexts are needed to hide most FP latency. |
| 4 | 8/16-context `1M+1A` worker | Best compute gain per DSP after the 2-context proof point. |
| 5 | Add second adder per worker | Useful next issue-limit improvement without DSP pressure. |
| 6 | Consider second multiplier per worker | Only after bandwidth and timing headroom are proven. |

## Conclusion

The current worker has substantial pipeline bubbles: roughly 3 multiplier issues and 5 adder issues are spread across about 77 cycles. A multi-context worker can theoretically reduce a `1M+1A` worker toward 5 cycles per non-escaping iteration, a per-worker compute gain up to about 15x before practical overhead.

The first de-bubbling architecture has now been proven with two in-flight pixel contexts per worker, one multiplier, one adder, tagged FP writeback, and ordered commit. The next compute target is still 8 to 16 in-flight pixel contexts per worker. Adding more multipliers is not the first move because the adder is the bottleneck for `2M+1A`, and extra FP64 multipliers consume scarce DSPs. Adding a second adder after proving deeper multi-context scheduling is more attractive.

However, whole-system speedup on the current 576000 baud UART design is capped near 28800 pixels/s. De-bubbling becomes strategically important only when paired with faster output and tagged/out-of-order result handling.
