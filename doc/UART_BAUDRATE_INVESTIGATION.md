# UART Baudrate Investigation Above 500 kbaud

This note records the follow-up investigation after the initial smoke-test based
baudrate sweep. The main finding is that the failure is not a simple speed wall
immediately above 500 kbaud. Some baudrates slightly above 500 kbaud are unstable
or corrupt, while the common 576000 baud setting is stable in the tests below.

## Current Candidate Setting

The current candidate setting is:

| Item | Value |
|---|---:|
| System clock | 100 MHz |
| Host baud | 576000 |
| RTL `CLOCKS_PER_BIT` | 174 |
| FPGA actual baud | 574712.64 |
| FPGA baud error vs host setting | -0.2235% |

The setting was tested with the existing single-sample UART RX/TX implementation.

## COM6 FT232HL Integer-Divider Retest

COM6 was retested with an FT232HL adapter, which has a much higher advertised baudrate ceiling than the earlier CP2102 bridge. The goal was to test 100 MHz integer-divisor baudrates in isolated directions before attempting the full Mandelbrot protocol.

Test fixtures:

| Fixture | Command | Purpose |
|---|---|---|
| TX-only pattern | `python python\uart_ft232h_sweep.py --mode tx --port COM6 --cpb <N> --seconds 1` | FPGA TX to host RX only; checks repeated `55 aa 00 ff 52 4b 01 7e` pattern hits |
| Echo | `python python\uart_ft232h_sweep.py --mode echo --port COM6 --cpb <N>` | Host TX to FPGA RX plus FPGA TX return; sends one byte at a time and expects exact echo |
| Full protocol smoke | `python python\uart_ft232h_sweep.py --mode full --port COM6 --cpb <N>` | Rebuilds full FP64 design and sends 1x1 Mandelbrot commands through `uart_raw_probe.py` |

The tested baudrate is the actual 100 MHz integer-divisor baudrate:

```text
actual_baud = 100000000 / CLOCKS_PER_BIT
```

COM6/FT232HL results:

| `CLOCKS_PER_BIT` | Actual baud | TX-only result | Echo result | Full protocol / verify result | Notes |
|---:|---:|---|---|---|---|
| 174 | 574712.64 | Not retested | Pass, `8/8` at host `574713` | Current rebuild failed `16x16 --verify` and `160x120 --verify`, no response | Source default remains `CLOCKS_PER_BIT=174` with host `576000`; current board rebuild needs recovery before benchmark acceptance |
| 100 | 1000000.00 | Pass | Pass, `8/8` | Not benchmarked because default full-protocol baseline was not responding | Exact 1 Mbaud link is stable in isolated UART tests only |
| 50 | 2000000.00 | Pass | Pass, `8/8` | Fail, no response in full protocol smoke | Isolated UART link is stable; full protocol path did not return a frame |
| 25 | 4000000.00 | Pass | Pass, `8/8` | Not benchmarked because default full-protocol baseline was not responding | Stable in isolated bidirectional UART echo |
| 20 | 5000000.00 | Pass | Pass, `8/8` | Fail, no response in full protocol smoke | Stable isolated UART; full protocol smoke failed |
| 19 | 5263157.89 | Pass | Not tested | Not benchmarked | TX-only pass while narrowing boundary |
| 18 | 5555555.56 | Pass | Not tested | Not benchmarked | TX-only pass while narrowing boundary |
| 17 | 5882352.94 | Pass | Pass, `8/8` | Fail, no response in full protocol smoke | Highest stable isolated bidirectional point tested |
| 16 | 6250000.00 | Fail | Fail, `0/8` | Not benchmarked | Corrupt bytes, not a usable link point |
| 15 | 6666666.67 | Fail, `pattern_hits=0` | Not tested | Not benchmarked | Received bytes, but no valid TX pattern |
| 12 | 8333333.33 | Pass, `pattern_hits=2` in a 1 s sample | Timeout | Not benchmarked | TX-only occasionally works, but bidirectional echo did not complete |
| 10 | 10000000.00 | Fail, no bytes | Not tested | Not benchmarked | No usable TX-only link observed |
| 9 | 11111111.11 | Fail, no bytes | Not tested | Not benchmarked | Closest integer-divisor test point below 12 Mbaud |

The FT232HL substantially improves the isolated UART link: TX-only and byte-paced echo both work up to `CLOCKS_PER_BIT=17` (`5.882 Mbaud`) and fail at `CLOCKS_PER_BIT=16` (`6.25 Mbaud`). Additional tests toward 12 Mbaud do not establish a higher usable bidirectional point. `CLOCKS_PER_BIT=12` produced a short TX-only pattern hit, but echo timed out, while `CLOCKS_PER_BIT=10` and `9` produced no received bytes in the TX-only test.

The full Mandelbrot protocol path did not produce a benchmarkable high-baud result. Previous smoke attempts at `2 Mbaud`, `5 Mbaud`, and `5.882 Mbaud` returned no response even though isolated echo passed. During the 12 Mbaud follow-up, the current rebuilt default `CLOCKS_PER_BIT=174` bitstream also returned no response to host `--verify` tests, so no high-baud full-protocol rate was promoted to small-frame or large-frame benchmark status.

## Fractional Baud Generator Retest

The UART RX/TX were changed from integer `CLOCKS_PER_BIT` timing to a 32-bit fractional accumulator driven by `CLK_HZ`, `BAUD`, and `ACC_WIDTH`. `CLOCKS_PER_BIT = CLK_HZ / BAUD` remains as a compatibility parameter, but bit timing now comes from the accumulator increment:

```text
BAUD_INC = round(BAUD * 2^ACC_WIDTH / CLK_HZ)
```

The RX also validates the start bit at the half-bit point before sampling data bits. During full-protocol recovery, an RX state-machine off-by-one was fixed: after sampling data bit 7, RX now enters stop-bit checking immediately instead of waiting one extra bit period. Byte-paced echo could pass with the old behavior, but continuous command frames could be sampled one bit late.

COM6/FT232HL fractional-NCO echo results:

| Requested baud | Echo result | Timing note | Notes |
|---:|---|---|---|
| 576000 | Pass, `8/8` | Echo top timing clean | Default candidate; fractional timing replaces integer CPB `174` |
| 1000000 | Pass, `8/8` | Echo top timing clean | Isolated bidirectional echo only |
| 2000000 | Pass, `8/8` | Echo top timing clean | Isolated bidirectional echo only |
| 4000000 | Pass, `8/8` | Routed WNS about `4.953 ns` | Fixed sweep point |
| 6000000 | Pass, `8/8` | Routed WNS about `5.037 ns` | Exceeds old integer-divider bidirectional boundary |
| 8000000 | Pass, `8/8` | Routed WNS about `5.044 ns` | Fixed sweep point |
| 10000000 | Fail, echo probe timed out | Routed WNS about `5.004 ns` | Failure recorded; no boundary narrowing was performed |
| 12000000 | Pass, `8/8` | Routed WNS about `4.953 ns` | Fixed sweep point; echo-only pass does not promote full protocol |

Fractional full-protocol baseline retest at `576000`:

| Test | Command summary | Result |
|---|---|---|
| Raw 1x1 response | `python python\uart_ft232h_sweep.py --mode full --port COM6 --baud 576000` | Pass response shape, `RK`, `1x1`, one pixel. The raw probe checksum parser was corrected to match RTL: response checksum covers pixel payload only, not the 6-byte header. |
| Small verify | `python python\mandelbrot_host.py --port COM6 --width 16 --height 16 --max-iter 64 --center -0.5 0.0 --step 0.01 --verify --output python\baudtest_frac576k_16x16.png --timeout 60` | Pass, `256/256` match, FPGA elapsed `0.026s`, `10025.34 pixels/s` |
| Medium verify | `python python\mandelbrot_host.py --port COM6 --width 160 --height 120 --max-iter 64 --center -0.5 0.0 --step 0.005 --verify --output python\baudtest_frac576k_160x120.png --timeout 180` | Pass, `19200/19200` match, FPGA elapsed `0.686s`, `27997.22 pixels/s` |

The fixed-sequence fractional echo sweep intentionally did not narrow around failures. The `10 Mbaud` timeout was recorded and testing continued directly to `12 Mbaud`.

Full-protocol benchmarking used `../python/uart_fractional_benchmark.py`, which rebuilds/programs the FP64 bitstream for each baudrate, runs a `160x120 --verify` gate, then runs the six existing 1080p scenes for baudrates that pass the gate. Complete logs and generated images are under `../python/uart_fractional_bench/`.

Small-frame gate results:

| Baud | Result | FPGA Time | Throughput | Verify |
|---:|---|---:|---:|---:|
| 576000 | Pass | `0.687s` | `27957.01 pps` | `19200/19200` |
| 1000000 | Pass | `0.404s` | `47562.50 pps` | `19200/19200` |
| 2000000 | Pass | `0.214s` | `89742.82 pps` | `19200/19200` |
| 4000000 | Pass | `0.119s` | `161789.80 pps` | `19200/19200` |
| 6000000 | Pass | `0.101s` | `189240.50 pps` | `19200/19200` |
| 8000000 | Pass | `0.101s` | `190632.21 pps` | `19200/19200` |
| 12000000 | Pass | `0.101s` | `190712.12 pps` | `19200/19200` |

All echo-passing baudrates passed the small-frame gate and were promoted to the six-scene 1080p test. The 1080p tests were run with `--verify`; the `Verify` column records exact HW/SW pixel matches. Values below 100% on deep or boundary-heavy scenes are the existing FP64 boundary-difference behavior, not a transport failure, as long as the full frame was received.

1080p verified benchmark results:

| Baud | Fast escape @128 | Standard @64 | Seahorse zoom @512 | Deep tendrils @8192 | Deep mini-brot @8192 | Deep Seahorse @1024 |
|---:|---:|---:|---:|---:|---:|---:|
| 576000 | `72.631s`, `28549.81 pps`, `2073588/2073600` | `72.615s`, `28555.90 pps`, `2073600/2073600` | `72.684s`, `28528.93 pps`, `2072731/2073600` | `72.661s`, `28538.05 pps`, `2072010/2073600` | `83.718s`, `24768.78 pps`, `2058168/2073600` | `72.661s`, `28538.08 pps`, `2049732/2073600` |
| 1000000 | `42.044s`, `49319.78 pps`, `2073588/2073600` | `42.057s`, `49304.93 pps`, `2073600/2073600` | `42.160s`, `49184.08 pps`, `2072731/2073600` | `42.120s`, `49230.41 pps`, `2072010/2073600` | `83.525s`, `24825.99 pps`, `2058168/2073600` | `44.190s`, `46924.32 pps`, `2049732/2073600` |
| 2000000 | `21.310s`, `97304.80 pps`, `2073588/2073600` | `21.333s`, `97203.33 pps`, `2073600/2073600` | `23.189s`, `89420.41 pps`, `2072731/2073600` | `33.490s`, `61916.50 pps`, `2072010/2073600` | `83.509s`, `24830.85 pps`, `2058168/2073600` | `36.513s`, `56790.08 pps`, `2049732/2073600` |
| 4000000 | `10.952s`, `189336.80 pps`, `2073588/2073600` | `10.958s`, `189233.47 pps`, `2073600/2073600` | `17.486s`, `118584.23 pps`, `2072731/2073600` | `33.405s`, `62073.82 pps`, `2072010/2073600` | `83.444s`, `24850.20 pps`, `2058168/2073600` | `36.499s`, `56812.50 pps`, `2049732/2073600` |
| 6000000 | `7.531s`, `275342.12 pps`, `2073588/2073600` | `7.512s`, `276030.90 pps`, `2073600/2073600` | `17.261s`, `120130.31 pps`, `2072731/2073600` | `33.401s`, `62082.33 pps`, `2072010/2073600` | `83.448s`, `24849.01 pps`, `2058168/2073600` | `36.507s`, `56800.84 pps`, `2049732/2073600` |
| 8000000 | `5.912s`, `350720.06 pps`, `2073588/2073600` | `5.813s`, `356734.98 pps`, `2073600/2073600` | `17.262s`, `120124.85 pps`, `2072731/2073600` | `33.396s`, `62091.07 pps`, `2072010/2073600` | `83.431s`, `24854.08 pps`, `2058168/2073600` | `36.486s`, `56832.03 pps`, `2049732/2073600` |
| 12000000 | <span style="color:red">`4.678s`, `443288.08 pps`, reprobe full frame</span> | `4.202s`, `493434.63 pps`, `2073600/2073600` | <span style="color:red">`17.280s`, `120003.12 pps`, reprobe full frame</span> | `33.393s`, `62096.41 pps`, `2072010/2073600` | `83.428s`, `24854.93 pps`, `2058168/2073600` | `36.480s`, `56842.30 pps`, `2049732/2073600` |

The 1080p results show three regimes. Fast UART-bound scenes scale almost linearly through `8 Mbaud`. Compute-heavy scenes stop improving once compute dominates: deep mini-brot stays near `83.4s` regardless of baudrate, and deep tendrils/deep Seahorse flatten around `33.4s` and `36.5s`. `12 Mbaud` is now the source default for experimentation. The first six-scene sweep had two late-stream timeouts, but the red 12 Mbaud entries above are direct reprobes of those two empty cells and both completed full-frame transfers.

Follow-up 12 Mbaud failure triage:

| Check | Observation | Interpretation |
|---|---|---|
| Failed fast escape log | Header was valid, payload stopped at `4146984/4147200` bytes | The command was received and compute/streaming started; failure was near the end of a long burst |
| Failed Seahorse zoom log | Header was valid, payload stopped at `4146851/4147200` bytes | Same late-stream symptom, not a bad command or bad dimensions |
| `tx_ctrl` inspection | Payload length is fixed from `rows*cols*2`; checksum is sent only after all payload bytes | No obvious fixed off-by-one in the TX byte counter |
| Merge/FIFO inspection | Raster collector writes exactly `rows*cols` pixels into the output FIFO; successful 12 Mbaud scenes receive full frames | Not consistent with a deterministic missing-row or missing-tail compute bug |
| Fast escape reprobe | Same 12 Mbaud bitstream completed full `1920x1080` transfer in <span style="color:red">`4.678s`, `443288.08 pps`</span> | Failure is not deterministic for that scene; red table value fills the original timeout cell |
| Seahorse zoom reprobe | Same 12 Mbaud bitstream completed full `1920x1080` transfer in <span style="color:red">`17.280s`, `120003.12 pps`</span> | Failure is likely high-baud burst reliability, host/USB scheduling, or serial driver buffering; red table value fills the original timeout cell |

The most likely cause of the observed missing tail bytes is occasional byte loss or receive starvation in the FT232HL/host path during multi-megabyte 12 Mbaud bursts. The current protocol has only a final checksum and no packet framing or retransmission, so a small number of dropped bytes makes the host wait forever for the declared payload length and then timeout.

Recommended next steps for using the FT232HL bandwidth:

| Step | Purpose |
|---|---|
| Soak-test `12000000` before relying on it | It is now the experimental default but has shown occasional late-frame byte loss |
| Keep `8000000` as the fallback high-baud setting | It completed all six verified 1080p scenes in the first sweep |
| Add RX/TX FIFO and protocol-level resynchronization | Reduce risk of late-frame byte loss at very high baudrates |
| Add UART RX oversampling or majority vote | Increase margin beyond single-sample fractional timing |
| Keep `576000` documented as a conservative fallback | It remains useful when 12 Mbaud long-burst reliability is more important than speed |

## Test Method

The sweep used `../python/baud_sweep.py`, which patches the UART constants, builds
the bitstream, programs the FPGA, then runs serial tests. The serial port tests
were run serially because `COM4` cannot be shared.

Validation levels:

| Level | Command | Purpose |
|---|---|---|
| Smoke | `python python\baud_sweep.py --baud <baud>` | Four 1x1 known-escape commands |
| Small frame | `python python\baud_sweep.py --baud <baud> --no-build --no-program --small-frame` | 16x16 frame transfer |
| Medium verify | `python python\mandelbrot_host.py --verify --width 160 --height 120 --max-iter 256 --output ... --timeout 180` | Full frame plus software comparison |
| Repeated commands | `python python\scan_points.py --y 0 --x0 0 --x1 159 --max-iter 128` | 160 consecutive single-point commands |

## Results

| Requested baud | `CLOCKS_PER_BIT` | FPGA actual baud | FPGA error | Result | Notes |
|---:|---:|---:|---:|---|---|
| 500000 | 200 | 500000.00 | 0.0000% | Pass | Baseline, smoke and 16x16 pass |
| 520000 | 192 | 520833.33 | +0.1603% | Pass | Smoke and 16x16 pass |
| 523560 | 191 | 523560.21 | +0.0000% | Marginal/fail | Smoke eventually passed, but first response had corrupt fields; 16x16 timed out |
| 526316 | 190 | 526315.79 | -0.0000% | Fail | Returned `RK`-like frames with corrupt payload/header fields |
| 530000 | 189 | 529100.53 | -0.1697% | Fail | No response in smoke |
| 540000 | 185 | 540540.54 | +0.1001% | Fail | No response in smoke |
| 576000 | 174 | 574712.64 | -0.2235% | Pass | Smoke, 16x16, 160x120 verify, and 160 repeated point commands pass |

Additional previous results:

| Requested baud | `CLOCKS_PER_BIT` | FPGA actual baud | Result | Notes |
|---:|---:|---:|---|---|
| 625000 | 160 | 625000.00 | Fail | Exact FPGA divider, board timeout in previous sweep |
| 800000 | 125 | 800000.00 | Fail | Exact FPGA divider, board timeout in previous sweep |
| 1000000 | 100 | 1000000.00 | Fail | Exact FPGA divider, board timeout in previous sweep |

## Failure Symptoms

The failures above 520000 baud are not all the same:

| Baud | Symptom | Interpretation |
|---:|---|---|
| 523560 | First smoke attempt returned `524b018040010001`, then a retry returned a valid `524b01000100010001`; 16x16 timed out | Marginal sampling: short commands can occasionally align well enough, but longer transfer loses byte framing |
| 526316 | Responses like `524b0180400180c0`, `524b018040010001`, `524b010001804001`; smoke failed | Byte stream is being sampled into plausible but wrong bytes; this is corruption, not pure no-response |
| 530000 / 540000 | `len=0` for smoke reads | FPGA likely did not receive a valid command, or host did not recognize any valid TX bytes after corrupted command handling |
| 625000+ | Previous tests timed out | Current UART design and/or board USB-UART path lacks enough margin at these settings |

The `RK` prefix appearing in some failing cases is important. It means at least
some transmitted bits are decoded as a response header, but later fields are
wrong. That points to sampling/baud/edge-margin corruption rather than a pure
protocol FSM or Mandelbrot compute failure.

## Why Exact FPGA Dividers Still Fail

The exact-divider failures at 523560, 526316, 625000, 800000, and 1000000 show
that FPGA-side integer divider error is not the only factor.

Likely contributors:

1. The current RX is single-sample-per-bit. It detects a falling edge, waits half
   a bit, then samples once per bit. There is no 8x/16x oversampling and no
   majority vote.
2. The RX does not re-check that the start bit is still low at the center of the
   start bit. A narrow glitch or metastability-delayed edge can start a bad
   frame.
3. The sampling point includes synchronizer and edge-detection phase uncertainty.
   At 500000 baud, one bit is 200 system clocks. At 576000 baud, one bit is about
   174 clocks. At 1000000 baud, one bit is only 100 clocks. The same fixed phase
   uncertainty consumes more of the eye as baud increases.
4. Host-side CP2102/driver baud generation for arbitrary baudrates is not
   guaranteed to match the requested value exactly. The 523560/526316 region may
   land on an unfavorable host-side divisor or jitter pattern even though the FPGA
   divisor is nearly exact.
5. The current protocol has no resynchronization inside a response body. A single
   byte framing error can shift all following fields until the host times out or
   misreads header/size/checksum.

The surprising pass at 576000 supports the host-divisor hypothesis. Even though
the FPGA is -0.2235% away from the nominal requested baud, 576000 is a common
serial rate and may be generated more cleanly by the CP2102/driver stack than
some nearby nonstandard values.

## Why Smoke Alone Was Misleading

The smoke test sends four tiny 1x1 commands and only checks for a valid iteration
count after reading up to 100 bytes. This catches complete failures quickly, but
it can miss marginal links.

Observed example at 523560:

```text
attempt=1 c=(2.5,0.0) len=8 iter=256 raw=524b018040010001
attempt=2 c=(2.5,0.0) len=9 iter=1   raw=524b01000100010001
SMOKE PASS
...
16x16 frame timed out
```

The retry makes smoke pass even though the link is not robust enough for a frame.
For baudrate acceptance, the minimum useful gate should be smoke + small frame +
medium verify + repeated commands.

## Recommendation

Use `576000` as the next candidate baudrate instead of trying to tune arbitrary
values between 520000 and 540000.

Before declaring it the new default, run a longer soak test:

```powershell
python python\test_esc.py
python python\mandelbrot_host.py --verify --width 160 --height 120 --max-iter 256 --output python\verify_576k.png --timeout 180
python python\scan_points.py --y 0 --x0 0 --x1 159 --max-iter 128
python python\mandelbrot_host.py --width 1920 --height 1080 --max-iter 64 --output python\hw_1080p_576k_smoke.png --timeout 180
```

For baudrates beyond 576000, improve the UART before further sweeps:

| Upgrade | Purpose |
|---|---|
| 8x or 16x oversampling RX | Reduce sensitivity to start-edge phase and bit-center error |
| Start-bit center validation | Reject glitches before entering data sampling |
| 3-sample majority vote around bit center | Improve noise/jitter tolerance |
| Fractional baud generator | Match common baudrates more closely when 100 MHz is not an integer multiple |
| Protocol-level frame resync and stricter checksum handling | Recover cleanly from one bad byte instead of timing out |

The next RTL experiment should be an oversampling RX while keeping the TX simple.
Most observed failures start with command reception or byte framing; strengthening
RX should increase the usable margin for 625000, 800000, 921600, and 1000000.
