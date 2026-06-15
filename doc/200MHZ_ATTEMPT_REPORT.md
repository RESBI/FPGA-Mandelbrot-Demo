# 200 MHz Clock Attempt Report

This report records the attempt to run the XC7K70T Mandelbrot FP64 design directly from the board's 200 MHz differential clock instead of the timing-clean 100 MHz MMCM-derived clock.

## Baseline

The validated default build uses the 200 MHz differential input only as the MMCM source. The Mandelbrot datapath, UART RX/TX baud generators, dispatcher, raster collector, and transmit controller run from the generated 100 MHz `sys_clk`.

The restored default build is timing-clean on `xc7k70tfbg676-1`:

| Build | Clock | WNS | TNS | WHS | THS |
|---|---:|---:|---:|---:|---:|
| Restored default FP64 | 100 MHz MMCM output | `1.148ns` | `0.000ns` | `0.042ns` | `0.000ns` |

The 100 MHz build was hardware-tested with the current large compute-tile host policy: default host tile `1920x120`, compute tile equal to host tile with width capped at 4096. All six 1080p scenes passed once.

| Scene | FPGA s | Throughput |
|---|---:|---:|
| fast escape @128 | `5.127s` | `404464.49 pps` |
| standard @64 | `4.731s` | `438328.75 pps` |
| Seahorse zoom @512 | `19.440s` | `106668.12 pps` |
| deep tendrils @8192 | `37.326s` | `55553.03 pps` |
| deep mini-brot @8192 | `83.561s` | `24815.51 pps` |
| deep Seahorse @1024 | `36.626s` | `56615.56 pps` |

## Attempted 200 MHz Changes

The initial 200 MHz experiment made the smallest possible clocking change:

- `top.v`: drive `sys_clk` directly from the 200 MHz `IBUFDS` output through a `BUFG`.
- `rtl/config.vh`: set `CFG_CLK_HZ=200000000` so fractional UART RX/TX baud accumulators remain correct at 12 Mbaud.
- Keep `FP_CE_DIV=1`, so the whole datapath attempts one useful cycle per 200 MHz clock.

That build produced a bitstream, but timing failed. It was not downloaded or benchmarked because the timing report was not signoff-clean.

## Timing Iterations

| Step | Change | Result |
|---|---|---|
| Direct 200 MHz | `sys_clk=clk_200`, `CFG_CLK_HZ=200000000` | `WNS=-1.290ns`, `TNS=-2592.618ns`, 5836 failing endpoints |
| Add FP adder pipeline cut | Split `fp_add` normalize/leading-zero and shift/final-select work; adjusted worker `ADD_LAT` 7 to 8 | Still failed, routed WNS about `-1.497ns` in that run |
| Split FP multiplier partial products | Replaced direct 53x53 multiply with 26/27-bit partial products and one partial-product register; adjusted worker `MUL_LAT` 6 to 7 | Improved to `WNS=-1.099ns`, `TNS=-854.943ns`, 2840 failing endpoints |
| Vivado performance strategy | Enabled synthesis retiming and `Performance_ExplorePostRoutePhysOpt` | Improved to `WNS=-0.651ns`, `TNS=-306.186ns`, 1617 failing endpoints, still not timing-clean |

The final 200 MHz result still had more than a thousand setup-violating endpoints. The experiment was therefore reverted from the default RTL, and the default build was restored to the timing-clean 100 MHz MMCM clock.

## Critical Path Observations

The first direct 200 MHz attempt showed two dominant timing classes:

- FP adder normalize/final exponent paths such as `u_add/man_result_r` to `u_add/exp_final_r` with long route delay and 12 logic levels.
- FP multiplier DSP cascade paths inside the inferred 53x53 multiply, with Vivado DRC warnings about unpipelined DSP MREG/PREG stages.

After adding one FP adder pipeline stage and splitting the multiplier into registered partial products, the worst paths moved away from pure FP arithmetic and into high-fanout worker control and transmit-controller count/update cones:

- Worker context state to FPU input register paths, for example `c_state_reg` to `mul_a_reg`.
- `tx_ctrl` row/tile counter paths driven by frame/tile dimension registers.

The route fraction of the worst paths remained high, often over 60% and sometimes over 80%, which means this is not only a single missing combinational pipeline cut. The design needs broader control-path restructuring, register duplication, or floorplanning to make 200 MHz practical.

## Decision

The 200 MHz bitstreams were not programmed for performance testing because none met timing. Benchmarking timing-failing bitstreams would not produce a valid performance point.

The repository default has been restored to the timing-clean 100 MHz build. The 200 MHz data is kept as an engineering record and as guidance for a future architecture pass.

## Recommended Next Steps

If 200 MHz remains a goal, the next work should not be another blind implementation strategy sweep. More useful directions are:

1. Add a separate UART/tx clock domain so the compute core can be retimed independently from the serial output controller.
2. Refactor worker issue control to register decoded issue decisions before driving wide `mul_a`, `mul_b`, `add_a`, and `add_b` muxes.
3. Explicitly instantiate or otherwise force fully pipelined DSP48 multiplication for FP64 mantissa products.
4. Pipeline `tx_ctrl` row/tile counters or run `tx_ctrl` at 100 MHz while compute runs faster behind an asynchronous FIFO.
5. Consider an intermediate frequency target such as 125 MHz or 150 MHz before attempting 200 MHz on this speed grade.
