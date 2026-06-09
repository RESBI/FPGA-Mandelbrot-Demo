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

## Test Method

The sweep used `python/baud_sweep.py`, which patches the UART constants, builds
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
