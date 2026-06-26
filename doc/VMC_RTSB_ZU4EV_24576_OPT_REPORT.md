# VMC RTSB ZU4EV 24.576 MHz Optimization Report

## Goal

- Target board: VMC_RTSB ZU4EV, Vivado part `xczu4ev-sfvc784-1-i`.
- Board clock: single-ended `sys_clk` at `24.576 MHz`.
- Host UART: start at `3,072,000 baud`, then sweep upward through `4,096,000` and `6,144,000` baud if stable.
- Primary optimization target: maximize Mandelbrot compute throughput in pixels per cycle (PPC) under the lower system clock.
- Validation order: RTL simulation, Vivado build/timing/resource review, programming, UART baud validation, 1080p board benchmark.

## Baseline Constraints

The previous ZU4EV migration used a direct 200 MHz configuration inherited from the XC7K70T branch. The new board clock is only `24.576 MHz`, so timing closure is expected to be easy, but raw clock frequency is `8.138x` lower than 200 MHz.

At this lower clock, UART baud must also be reduced. The current UART RX uses single-point sampling rather than 8x/16x oversampling, so practical baud rates need enough system clocks per bit.

| Baud | Clocks/bit at 24.576 MHz | Initial expectation |
| ---: | ---: | --- |
| 1,536,000 | 16 | Exact common divider for 24.576 MHz FPGA clock and 120 MHz FT232HL clock |
| 3,072,000 | 8 | FPGA exact; FT232HL 120 MHz divisor depends on fractional granularity |
| 4,096,000 | 6 | Aggressive but plausible |
| 6,144,000 | 4 | High risk, test only after lower bauds pass |

## Optimization Strategy

The FP64 worker contains one multiplier pipeline and one adder pipeline. With enough in-flight pixel contexts, one worker can keep these units busy, but per-pixel iteration still needs multiple multiply/add issue slots. At `24.576 MHz`, the critical path pressure is greatly reduced, so the most direct way to improve PPC is to increase worker parallelism until DSP/BRAM/LUT resources become the limiting factor.

The first optimization point was aggressive and intentionally tested the resource ceiling:

| Item | Previous ZU4EV default | 24.576 MHz optimization attempt 1 |
| --- | ---: | ---: |
| `CLK_HZ` | 200,000,000 | 24,576,000 |
| `CFG_UART_BAUD` | 12,000,000 / experimental | 3,072,000 |
| `CORE_COUNT` | 6 | 24, then reduced to 12 after resource DRC |
| `WORKER_CONTEXTS` | 4 | 8 |
| Scheduler | Dynamic rows | Dynamic rows |
| Owner table depth | 4096 | 4096 |

Expected resource scaling: each worker instantiates one FP64 multiplier and one FP64 adder. The prior 6-worker design used 60 DSP48E2 in route logs, which implies about 10 DSP per worker. A 24-worker build is expected to use roughly 240 DSP48E2, within the ZU4EV device budget reported by Vivado (`728 DSPs`). BRAM usage scales with per-worker output FIFOs and should remain within budget.

## RTL Changes

- `rtl/config.vh`: default `CFG_CLK_HZ` changed to `24576000`.
- `rtl/config.vh`: default `CFG_UART_BAUD` is now `6144000`; the project-body command path uses host `--tx-byte-gap 0.00005`.
- `rtl/config.vh`: default `CFG_CORE_COUNT` is now `12`; the earlier `24`-worker attempt was simulation-valid but rejected by implementation resource DRC.
- `rtl/config.vh`: default `CFG_WORKER_CONTEXTS` changed to `8`.
- `constraints_vmc_rtsb_zu4ev/led.xdc`: clock period changed to `40.690 ns`.
- `build_fp64.tcl`: default build generics are `CLK_HZ=24576000 CORE_COUNT=12 WORKER_CONTEXTS=8`.
- UART bring-up tops use `CLK_HZ=24576000`.
- `python/mandelbrot_host.py`: default baud is now `6144000`.

## Validation Log

### Step 1: RTL Simulation

Passed.

Planned command:

```powershell
& "Z:\Softwares\Xilinx\Vivado\2024.2\bin\vivado.bat" -mode batch -source sim_multicore_dynamic_contexts.tcl -tclargs WORKER_CONTEXTS=8 CORE_COUNT=24 ROWS=12 COLS=16 MAX_ITER=64 CORE_FIFO_DEPTH=128 TIMEOUT_CYCLES=4000000
```

Result: `DYNAMIC MULTICORE TEST PASS: 192 pixels`.

The 24-worker point was functionally valid in RTL simulation, but later failed implementation resource DRC.

Second simulation command after reducing to 12 workers:

```powershell
& "Z:\Softwares\Xilinx\Vivado\2024.2\bin\vivado.bat" -mode batch -source sim_multicore_dynamic_contexts.tcl -tclargs WORKER_CONTEXTS=8 CORE_COUNT=12 ROWS=12 COLS=16 MAX_ITER=64 CORE_FIFO_DEPTH=128 TIMEOUT_CYCLES=4000000
```

Result: `DYNAMIC MULTICORE TEST PASS: 192 pixels`.

### Step 2: Build And Timing

Passed for the 12-worker point.

Planned command:

```powershell
& "Z:\Softwares\Xilinx\Vivado\2024.2\bin\vivado.bat" -mode batch -source build_fp64.tcl
```

Metrics to record:

| Build | WNS | TNS | LUT | FF | BRAM | DSP | Result |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| 24 workers / 8 ctx | N/A | N/A | Over-utilized | N/A | N/A | 241 synth DSP | Failed: 164,913 LUT-as-logic required vs 87,840 available |
| 12 workers / 8 ctx | 27.781 ns | 0.000 ns | 81,934 LUT-as-logic / 84,946 CLB LUTs | 71,398 | 25.5 tiles | 121 | Passed route and bitstream |
| 14 workers / 4 ctx | 30.896 ns | 0.000 ns | 66,355 LUT-as-logic / 69,869 CLB LUTs | 61,813 | 29.5 tiles | 141 | Passed route and bitstream |

The 12-worker / 8-context build is LUT-limited rather than DSP-limited. It uses `93.28%` LUT-as-logic and `96.71%` total CLB LUTs, leaving too little LUT headroom for another full worker. DSP utilization is only `16.62%`, so the worker count is limited by FP64 control/LUT logic, not DSP blocks.

Timing has very large margin at 24.576 MHz. Route WNS was `27.781 ns`, so further pipeline splitting is not required for timing. The pipeline choice is therefore driven by PPC/resource balance rather than Fmax.

Low-frequency PPC candidate update: `14 workers / 4 contexts` passed RTL simulation and routed successfully. Reducing contexts from 8 to 4 freed enough LUT/control logic to increase worker count from 12 to 14 while reducing LUT utilization. The initial board test produced no UART response on a `160x120` host verify attempt and no bytes on a 1x1 raw probe at `3,072,000` baud. A larger `120x160`, `max_iter=128` RTL simulation was then run after fixing the simulation testbench's owner-table depth parameter and passed `19200` pixels. This keeps `14/4` as a valid functional candidate, but it still needs a fresh baud-controlled rebuild/download to determine whether the first board failure was a stale/overwritten bitstream or a board-only issue.

### Step 3: UART Baud Sweep

Initial full-design test at `3,072,000 baud` with the original UART pin interpretation returned no bytes, so the UART pins were investigated with TX-pattern, RX-scope, and echo-only diagnostic tops. The final confirmed FPGA-side naming is `uart_rx=D12` and `uart_tx=C12`.

Further probing showed that FPGA-to-PC transmit is stable at `3,072,000 baud` when the FPGA drives `C12`. A TX pattern design that drove both `C12` and `D12` returned a clean repeating `55 aa 00 ff 52 4b 01 7e` pattern on COM6. A TX-only design driving only `D12` returned no bytes, so the confirmed FPGA TX pin is `C12`.

PC-to-FPGA receive is not yet confirmed. Echo and RX-detect tests did not trigger when using either `D12` or `C12` as `uart_rx`. The UART RX implementation was changed from single-point fractional NCO sampling to integer clocks-per-bit three-point majority sampling, but RX still did not trigger. This suggests the PC TX path is either on a different pin, gated by board wiring/jumper state, or not connected as assumed.

Planned baud sequence:

| Baud | Clocks/bit | Echo | 1x1 raw probe | Small frame | Notes |
| ---: | ---: | --- | --- | --- | --- |
| 1,536,000 | 16 | 16/16 | Pending | Pending | Exact common divider; RX waveform and echo confirmed after reprogramming |
| 3,072,000 | 8 | Pending after RX recovered | 1x1 responds with `RT` tiled frame | 160x120 verify 100% | Main design downloaded and functional |
| 4,096,000 | 6 | Not tested in echo | 1x1 no bytes | 160x120 no header | Built project body; not usable with current UART RX sampling |
| 4,096,000 | 6 | Pending | Pending | Pending | Try if 3.072M passes |
| 6,144,000 | 4 | Pending | Pending | Pending | High-risk upper test |

### Step 4: 1080p Board Benchmark

Completed for the known-good `12 workers / 8 contexts` point at `3,072,000` baud.

Planned command after baud selection:

```powershell
python python\mandelbrot_host.py --port COM6 --width 1920 --height 1080 --max-iter 128 --center 1.0 1.0 --step 0.002 --timeout 900 --tile-width 1920 --tile-height 120 --tile-retries 3 --quiet --output python\hw_1080p_24576_opt.png
```

Metrics to record:

| Configuration | Baud | Scene | FPGA elapsed | Total elapsed | Effective pixels/s | Notes |
| --- | ---: | --- | ---: | ---: | ---: | --- |
| 12 workers / 8 ctx | 16.690 s FPGA elapsed / 19.580 s total | 1080p fast escape | 124,242.33 pixels/s | 0.00505 incl UART/protocol | `python/hw_1080p_24576_opt_3072k.png` | Passed |

Six standard 1080p scenes, one run per scene, host/compute tiles `1920x120`, `--verify`, baud `3,072,000`:

| Scene | Transport pass | Exact SW match | Retry events | FPGA s | Pixels/s | Match |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| fast escape @128 | 1/1 | 0/1 | 0 | 16.691 | 124,236.55 | 2,073,588 / 2,073,600 |
| standard @64 | 1/1 | 1/1 | 0 | 16.695 | 124,201.16 | 2,073,600 / 2,073,600 |
| Seahorse zoom @512 | 1/1 | 0/1 | 0 | 19.298 | 107,450.82 | 2,072,760 / 2,073,600 |
| deep tendrils @8192 | 1/1 | 0/1 | 0 | 27.756 | 74,707.69 | 2,072,027 / 2,073,600 |
| deep mini-brot @8192 | 1/1 | 0/1 | 0 | 72.302 | 28,679.67 | 2,058,166 / 2,073,600 |
| deep Seahorse @1024 | 1/1 | 0/1 | 0 | 31.582 | 65,658.59 | 2,049,714 / 2,073,600 |

Summary file: `python/host_tile_stability_bench/zu4ev24576_3072k_c12ctx8_6scene.md`.

The exact-match column is expected to be below 100% on deep FP64 views because the project already documents small software/RTL floating-point boundary differences. Transport pass and full-frame receipt are the board-level stability criteria here.

Resolved blocker: after reprogramming, the board receives FPGA TX on COM6 from `C12`, and FPGA RX on `D12` captures the host waveform. The main Mandelbrot bitstream at `3,072,000` baud responds with the tiled `RT` protocol and completes frame tests.

Additional RX scope test:

- Added `rtl/uart_rx_scope_top.v`, `build_uart_rx_scope.tcl`, and `python/uart_rx_scope_probe.py`.
- The FPGA samples `uart_rx` directly and reports 100 ms window statistics over the known-good FPGA TX path on `C12`.
- After reprogramming the RX scope bitstream, with current constraints `uart_rx=D12`, while the host continuously sent `0x55` at `1,536,000` baud, the FPGA reported approximately `11.5k-12.8k` falling edges and matching rising edges per 100 ms window, with nonzero low-level samples.
- Interpretation: FPGA does see a UART waveform on `D12`. The earlier all-low result was not repeatable after reprogramming.
- Reprogrammed the echo bitstream and ran `python python\uart_echo_probe.py --port COM6 --baud 1536000 --trials 16 --timeout 0.5`: `echo_pass=16/16`.

Main-design board tests at `3,072,000` baud:

- Reprogrammed `./fp64_zu4ev_proj/mandelbrot_fp64.runs/impl_1/top.bit`.
- Raw 1x1 probe received a stable `RT` tiled response frame, confirming the host command path and FPGA response path are alive.
- `160x120`, `max_iter=128`, center `(-0.5, 0.0)`, step `0.005`: FPGA elapsed `0.183 s`, `105,071.05 pixels/s`, software verification `19200/19200 match (100.00%)`.
- `1920x1080`, `max_iter=128`, center `(1.0, 1.0)`, step `0.002`, tile `1920x120`: FPGA elapsed `16.690 s`, `124,242.33 pixels/s`, total elapsed `19.580 s`, output `python/hw_1080p_24576_opt_3072k.png`.
- Six standard 1080p scenes completed transport pass `6/6` at `3,072,000` baud with no retry events.

UART baud conclusion for the current project body:

- `1,536,000` baud is the exact common bring-up point for 24.576 MHz FPGA clock and 120 MHz FT232HL fractional divider, and echo passed `16/16`.
- `3,072,000` baud is the highest project-body baud validated so far. It uses 8 FPGA clocks/bit and completed small-image verify plus all six standard 1080p scenes.
- `4,096,000` baud uses 6 FPGA clocks/bit and was built into the project body, but small-image verify and 1x1 raw probe returned no bytes. It is not accepted with the current integer three-sample RX implementation.
- `6,144,000` baud was not pursued after `4,096,000` failed, because it would leave only 4 FPGA clocks/bit and less sampling margin.

Follow-up UART-only echo tests were run to separate the physical UART link from the Mandelbrot project body:

| Baud | Echo build config | Echo result | Interpretation |
| ---: | --- | ---: | --- |
| 4,096,000 | `CFG_UART_BAUD=4096000` | 16/16 | UART RX/TX path is stable in a lightweight echo design. The earlier Mandelbrot no-response result is not explained by a basic FT232HL or pin failure. |
| 6,144,000 | `CFG_UART_BAUD=6144000` | 32/32 | Highest echo-only baud validated so far. This is aggressive because the RX samples at the minimum 4 FPGA clocks/bit, but it worked for the echo pattern. |
| 8,192,000 | `CFG_UART_BAUD=8192000` | 0/32 | Failed with consistent but wrong 8-byte echoes, indicating RX sampling/bit-period error rather than a dead link. |

Echo-only conclusion: the board UART link can operate above `3,072,000` baud in a simple design, up to `6,144,000` in the tested pattern. This does not yet make `6,144,000` an accepted Mandelbrot project-body baud; the full design still needs a fresh build/program and at least 1x1 raw plus small-frame verify at that baud.

High-baud no-response root-cause update:

- Added `rtl/uart_rx_burst_capture_top.v`, `build_uart_rx_burst_capture.tcl`, and `python/uart_rx_burst_capture_probe.py` to test host-to-FPGA burst reception without the echo design's TX-backpressure artifact.
- The original echo test sent one byte and waited for one echoed byte, so it inserted a large effective inter-byte gap. That test does not represent the Mandelbrot host command, which writes the full 33-byte FP64 command as one burst.
- At `6,144,000` baud, burst capture showed the 33-byte command was often received as only 20-32 bytes or with corrupted tail bytes. The dropped/corrupted bytes were often `0x00`, so XOR could still appear valid in some cases even though field alignment was wrong. This explains the project-body no-response: `cmd_parser` does not receive a valid command frame and never starts compute.
- Two UART RX fixes were made in `rtl/uart_rx.v`: include the final same-cycle sample in the majority vote, and allow immediate transition from STOP to START if the line is already low at the end of the stop bit. These are correct fixes, but they did not make continuous `6,144,000` baud command bursts reliable enough on the board.
- With a `50 us` delay between command bytes, the same `6,144,000` baud burst-capture test passed `10/10` with exact 33-byte command matches. This is practical because host-to-FPGA commands are only 33 bytes, while the performance-sensitive direction is the much larger FPGA-to-host image payload.
- `python/mandelbrot_host.py`, `python/uart_raw_probe.py`, and `python/host_tile_stability_benchmark.py` now support `--tx-byte-gap` so high-baud tests can slow only the short command write while keeping the UART baud high for receive payloads.
- A fresh `6,144,000` baud Mandelbrot full-design build initially exceeded a 30-minute route timeout, then completed when rerun with a longer timeout. Route timing met with WNS `25.024 ns`, TNS `0.000 ns`, WHS `0.010 ns`.
- `12 workers / 8 contexts @ 6,144,000 baud` routed resource usage: CLB LUTs `84,949 / 87,840 = 96.71%`, LUT-as-logic `81,937 / 87,840 = 93.28%`, CLB registers `71,408 / 175,680 = 40.65%`, Block RAM Tile `25.5 / 128 = 19.92%`, DSPs `121 / 728 = 16.62%`.
- Programmed `./fp64_zu4ev_proj/mandelbrot_fp64.runs/impl_1/top.bit` and verified 1x1 raw response at `6,144,000` baud with `--tx-byte-gap 0.00005`: stable 25-byte `RT/TD/TE` tiled response for 3/3 trials.
- `160x120`, `max_iter=128`, center `(-0.5, 0.0)`, step `0.005`, `--verify`, `--tx-byte-gap 0.00005`: FPGA elapsed `0.166 s`, `115,439.28 pixels/s`, software verification `19200/19200 match (100.00%)`.
- `1920x1080` fast escape, `max_iter=128`, center `(1.0, 1.0)`, step `0.002`, host tile `1920x120`, `--verify`, `--tx-byte-gap 0.00005`: FPGA elapsed `9.594 s`, `216,133.85 pixels/s`, match `2,073,588 / 2,073,600`. The 12 mismatches are the known FP boundary differences.
- Current highest accepted project-body UART mode: `6,144,000` baud with host command byte gap `50 us`.

Final 6-scene deployment benchmark at `12 workers / 8 contexts / 6,144,000 baud / 50 us TX byte gap`:

| Scene | Transport | Retries | FPGA s | Pixels/s | SW match |
|---|---:|---:|---:|---:|---:|
| fast escape @128 | PASS | 0 | `9.587` | `216,288.01` | `2,073,588 / 2,073,600` |
| standard @64 | PASS | 0 | `9.622` | `215,498.75` | `2,073,600 / 2,073,600` |
| Seahorse zoom @512 | PASS | 0 | `15.192` | `136,492.42` | `2,072,760 / 2,073,600` |
| deep tendrils @8192 | PASS | 0 | `27.377` | `75,742.33` | `2,072,027 / 2,073,600` |
| deep mini-brot @8192 | PASS | 0 | `71.977` | `28,809.10` | `2,058,166 / 2,073,600` |
| deep Seahorse @1024 | PASS | 0 | `31.128` | `66,614.27` | `2,049,714 / 2,073,600` |

Summary file: `python/host_tile_stability_bench/zu4ev24576_6144k_c12ctx8_6scene.md`.

`14 workers / 4 contexts` candidate:

- Motivation: reduce per-worker context state/control LUT use and spend the freed resources on two more workers. This was expected to improve low-frequency pixels per cycle if four contexts were enough to hide the shared FP64 add/mul latency.
- RTL simulation: `120x160`, `max_iter=128`, `CORE_COUNT=14`, `WORKER_CONTEXTS=4`, `CORE_FIFO_DEPTH=4096`, `DYNAMIC_OWNER_DEPTH=4096` passed with `19200` pixels.
- Route timing: WNS `30.896 ns`, TNS `0.000 ns`, WHS `0.010 ns` at `24.576 MHz`.
- Routed resource usage: CLB LUTs `69,869 / 87,840 = 79.54%`, LUT-as-logic `66,355 / 87,840 = 75.54%`, CLB registers `61,813 / 175,680 = 35.18%`, Block RAM Tile `29.5 / 128 = 23.05%`, DSPs `141 / 728 = 19.37%`.
- Board raw probe at `6,144,000` baud with `50 us` TX byte gap produced stable tiled responses for 3/3 trials. The earlier no-response symptom was therefore caused by the high-baud command burst issue, not by the `14/4` datapath itself.
- `160x120` verify passed: FPGA elapsed `0.175 s`, `109,734.54 pixels/s`, `19200/19200` match.

`14/4` 6-scene board benchmark at `6,144,000 baud / 50 us TX byte gap`:

| Scene | Transport | Retries | FPGA s | Pixels/s | SW match |
|---|---:|---:|---:|---:|---:|
| fast escape @128 | PASS | 1 | `11.269` | `184,012.37` | `2,073,588 / 2,073,600` |
| standard @64 | PASS | 0 | `9.661` | `214,635.66` | `2,073,600 / 2,073,600` |
| Seahorse zoom @512 | PASS | 0 | `16.722` | `124,007.52` | `2,072,760 / 2,073,600` |
| deep tendrils @8192 | PASS | 0 | `29.609` | `70,032.91` | `2,072,027 / 2,073,600` |
| deep mini-brot @8192 | PASS | 0 | `76.179` | `27,220.25` | `2,058,166 / 2,073,600` |
| deep Seahorse @1024 | PASS | 0 | `33.725` | `61,486.05` | `2,049,714 / 2,073,600` |

Summary file: `python/host_tile_stability_bench/zu4ev24576_6144k_c14ctx4_6scene.md`.

Decision: keep `12 workers / 8 contexts` as the accepted deployment point. The `14/4` candidate used fewer LUTs and had larger timing slack, but it was slower in all six full-frame scenes and had one retry event in the fast-escape scene. The result indicates that four contexts per worker do not fully hide the current FP64 worker pipeline latency; the extra two workers do not compensate for the reduced per-worker occupancy.

Pipeline latency retiming check:

- The worker/FPU completion tags were parameterized as `CFG_WORKER_MUL_LAT` and `CFG_WORKER_ADD_LAT`, with default values left at the accepted `6` and `9` cycles. This makes latency experiments explicit without changing the accepted default design.
- `sim_multicore_dynamic_contexts.tcl` now supports `WORKER_MUL_LAT` and `WORKER_ADD_LAT` overrides and adds a latency suffix to override simulation project names, avoiding concurrent simulation project collisions.
- Default `MUL_LAT=6`, `ADD_LAT=9`, `12 workers / 8 contexts`, `120x160`, `max_iter=128` RTL simulation passed after the parameterization change.
- `MUL_LAT=4`, `ADD_LAT=7`, `120x160`, `max_iter=128` failed with `1902` pixel mismatches, proving the larger test catches early FPU result tagging.
- `MUL_LAT=5`, `ADD_LAT=8`, `120x160`, `max_iter=128` failed with `1902` pixel mismatches.
- `MUL_LAT=6`, `ADD_LAT=8`, `120x160`, `max_iter=128` failed with `1902` pixel mismatches.
- `MUL_LAT=5`, `ADD_LAT=9`, `120x160`, `max_iter=128` failed with `1902` pixel mismatches.
- Conclusion: the current FPU output/result-tag alignment requires `MUL_LAT=6` and `ADD_LAT=9` in the worker. Simply consuming results earlier is not safe. A real latency reduction would require restructuring `fp_mul.v` and/or `fp_add.v` together with dedicated FPU latency scoreboards, then repeating RTL simulation, build, and board tests. That is not a safe final optimization for this pass.

Small host-side cleanup:

- `python/mandelbrot_host.py` now estimates UART payload time using the selected `--baud` instead of the default global baud. This fixes misleading logs such as reporting `3072000` baud while running at `6144000` baud.

## Notes

- Pipeline depth is not reduced in attempt 1. At low clock, reducing FP pipeline depth may reduce per-pixel latency, but it can also reduce maximum worker occupancy if not retuned carefully. The first-order PPC gain comes from increasing parallel workers while keeping enough contexts to hide FP latency.
- 24 workers / 8 contexts exceeded LUT-as-logic capacity before placement. The next attempt is 12 workers / 8 contexts, chosen by roughly halving the LUT demand while keeping enough contexts to hide FP pipeline latency.
- If 8 contexts do not improve PPC versus 4 contexts in simulation, the design should return to 4 contexts to save LUT/registers and allow more workers.
