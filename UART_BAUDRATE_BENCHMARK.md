# UART Baudrate Benchmark With CP2102

This report evaluates higher UART baudrates for the Mandelbrot FPGA accelerator using the current true-100 MHz FP64 core and a CP2102 USB-UART bridge on the host side.

## Goal

The previous stable UART rate was 460800 baud. Fast 1080p scenes were UART-limited near 23000 pixels/s, so increasing serial bandwidth can reduce render time when the compute core is not the bottleneck.

The FPGA clock is 100 MHz. For the current simple UART receiver/transmitter, integer `CLOCKS_PER_BIT` values are preferred because they avoid accumulated FPGA-side bit timing error.

## Baudrate Selection

For a given baudrate:

```text
CLOCKS_PER_BIT = 100000000 / baudrate
```

The tested candidates were selected to divide 100 MHz exactly.

| Baudrate | `CLOCKS_PER_BIT` | FPGA-side divider error | Theoretical pixel ceiling | Board result |
|---:|---:|---:|---:|---|
| 1000000 | 100 | 0.000% | 50000 pixels/s | fail, all smoke points timed out |
| 800000 | 125 | 0.000% | 40000 pixels/s | fail, all smoke points timed out |
| 625000 | 160 | 0.000% | 31250 pixels/s | fail, all smoke points timed out |
| 500000 | 200 | 0.000% | 25000 pixels/s | pass |
| 460800 | 217 | +0.0064% actual baud error | 23040 pixels/s | previous stable baseline |

The pixel ceiling assumes 8N1 UART framing and 16-bit output pixels:

```text
pixels/s = baud / 10 UART bits per byte / 2 bytes per pixel
```

## Why 500000 Baud Was Chosen

`500000 baud` is the highest tested exact-divisor rate that passed board validation with the current UART design and CP2102 link.

It has:

| Item | Value |
|---|---:|
| FPGA clock | 100 MHz |
| `CLOCKS_PER_BIT` | 200 |
| FPGA-side baud error | 0.000% |
| UART bit period | 2.000 us |
| Theoretical max output rate | 25000 pixels/s |
| Improvement over 460800 ceiling | 1.085x |

Higher exact-divisor rates failed even though their FPGA-side timing error is zero. That points to board-level signal quality, CP2102/driver behavior at those nonstandard rates, or the current single-sample UART RX implementation rather than divider accumulation.

## Timing And Validation

The final 500000 baud bitstream was rebuilt and programmed.

Routed timing:

| Metric | Value |
|---|---:|
| WNS | `0.690ns` |
| TNS | `0.000ns` |
| WHS | `0.011ns` |
| THS | `0.000ns` |

Vivado reported:

```text
All user specified timing constraints are met.
```

Board validation at 500000 baud:

| Test | Result |
|---|---|
| `python python\test_esc.py` | pass, all smoke points OK |
| `160x120 @256 --verify` | `19200/19200 match` |
| `scan_points.py --y 0 --x0 0 --x1 159 --max-iter 128` | `PASS: 160/160 row points match` |

## 1080p Benchmark Results

The following compares the same true-100 MHz FP64 core at 460800 baud and 500000 baud.

| Case | 460800 Time | 500000 Time | Time Speedup | 460800 pps | 500000 pps | PPS Speedup |
|---|---:|---:|---:|---:|---:|---:|
| `1080p fast escape @128` | `97.410s` | `91.183s` | `1.07x` | `21287.29` | `22741.04` | `1.07x` |
| `1080p standard @64` | `90.551s` | `83.510s` | `1.08x` | `22899.91` | `24830.65` | `1.08x` |
| `1080p Seahorse zoom @512 step=5e-6` | `173.758s` | `171.817s` | `1.01x` | `11933.83` | `12068.62` | `1.01x` |
| `1080p deep triple spiral @8192` | `90.560s` | `83.499s` | `1.08x` | `22897.40` | `24833.70` | `1.08x` |
| `1080p deep tendrils @8192` | `340.055s` | `340.029s` | `1.00x` | `6097.84` | `6098.30` | `1.00x` |
| `1080p deep minibrot @8192` | `850.711s` | `850.720s` | `1.00x` | `2437.49` | `2437.46` | `1.00x` |
| `1080p deep seahorse @1024` | `363.254s` | `363.253s` | `1.00x` | `5708.39` | `5708.41` | `1.00x` |

## Aggregate Results

| Workload Class | Average Speedup | Explanation |
|---|---:|---|
| UART-limited 1080p cases | `~1.08x` | 500000 baud raises the output ceiling from about 23040 to 25000 pixels/s. |
| Compute-bound 1080p cases | `~1.00x` | Core compute time dominates; faster UART does not materially change total time. |

The fastest measured 500000 baud cases reached about `24834 pixels/s`, which is close to the theoretical `25000 pixels/s` limit.

## Interpretation

500000 baud is a safe incremental improvement for the current hardware and UART implementation:

- It is exactly generated from the 100 MHz FPGA clock.
- It avoids FPGA-side cumulative baud error.
- It is stable with the CP2102 link in smoke, frame verification, and row comparison tests.
- It improves UART-limited 1080p cases by about 8%.

The failed higher exact-divisor candidates show that divider accuracy alone is not enough. The current UART RX samples each bit once near the expected center. At higher rates, less margin is available for cable quality, CP2102 timing behavior, board IO edge quality, and host driver scheduling.

## Recommendation

Use `500000 baud` as the new stable UART rate if the priority is a small, safe throughput gain without redesigning UART RX.

For a larger step beyond 500000 baud, implement a more robust UART receiver before retrying high rates:

1. 8x or 16x oversampling RX.
2. Majority vote around the bit center.
3. Optional fractional baud generator for standard rates such as 921600.
4. Re-test 625000, 800000, 921600, and 1000000 baud after RX redesign.
