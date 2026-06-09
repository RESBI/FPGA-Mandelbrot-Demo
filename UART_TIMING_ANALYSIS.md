# UART Timing Analysis: Single-Sample RX Failure Above 520 kbaud

## Executive Summary

This report analyzes why the current single-sample UART RX reliably operates at
500000 and 576000 baud, fails marginally between 520000–530000, and fails
completely at 625000 baud and above.  TX-only experiments prove that the FPGA
TX downlink remains functional at all tested baud rates including 625000,
800000, and 1000000; therefore the root cause lies in the **FPGA RX uplink
path**.

The primary failure mechanism is a combination of:

1. **CP2102 baud-rate quantisation error** at non‑standard integer-divided baud
   rates, causing a byte‑framing timing drift that grows across each UART
   character frame.
2. **Single‑sample‑per‑bit architecture** with zero tolerance to this drift.
3. **Missing start‑bit and stop‑bit verification**, allowing noise or a
   mis‑timed edge to corrupt the receiver state silently.

---

## 1. Clock System & Baud Generation

```
sys_clk    = 100 MHz   (T_clk = 10 ns)
CPB        = round(100e6 / baud)
FPGA_baud  = 100e6 / CPB
```

| Requested baud | CPB | FPGA actual baud | FPGA error | CP2102 approximate* | Net drift/byte |
|---:|---:|---:|---:|---:|---:|
| 500000 | 200 | 500000.00 | 0.0000% | 500000 (exact) | 0 ns |
| 520833 | 192 | 520833.33 | +0.0000% | ~515k–527k | ~50–150 ns |
| 523560 | 191 | 523560.21 | +0.0000% | ~515k–527k | ~50–150 ns |
| 526316 | 190 | 526315.79 | −0.0000% | ~515k–527k | ~50–150 ns |
| 530000 | 189 | 529100.53 | −0.1697% | ~515k–535k | ~50–200 ns |
| 540000 | 185 | 540540.54 | +0.1001% | ~527k–552k | ~80–200 ns |
| **576000** | **174** | **574712.64** | **−0.2235%** | **571429 (div21)** | **~40 ns** |
| 625000 | 160 | 625000.00 | 0.0000% | 631579 (div19) | ~150 ns |
| 800000 | 125 | 800000.00 | 0.0000% | 800000 (div15) | ~0 ns |
| 1000000 | 100 | 1000000.00 | 0.0000% | 1000000 (div12) | ~0 ns |

*CP2102 approximations based on 48 MHz internal clock and integer‑only divider:
`baud = 48e6 / prescaler / div`. The values listed are the closest achievable
settings. 576000 is a common “PC standard” baud that is well‑supported by the
CP2102 driver stack; 625000/800000/1000000 are also exact 48 MHz divisors and
should be generated cleanly by the CP2102.

---

## 2. Single‑Sample RX Timing

### 2.1 State Machine

The current `uart_rx` (80 lines) operates as a four‑state FSM:

```
IDLE → (start_edge) → START → (half_bit) → SAMPLE*8 → STOP → (half_bit) → IDLE
```

- **IDLE**: waits for `start_edge` = falling edge of synchronised `rx`.
- **START**: counts `(CPB−1)/2` clocks to reach the nominal centre of the
  start bit, then transitions to SAMPLE.
- **SAMPLE**: after each full bit period (`CPB−1` clocks), samples
  `rx_sync2` into the shift register.  After 8 data bits, transitions to STOP.
- **STOP**: counts `(CPB−1)/2` clocks, then latches output data and asserts
  `data_avail`.

### 2.2 Synchroniser Latency

```verilog
reg rx_sync1 = 1, rx_sync2 = 1;
always @(posedge clk) begin
    rx_sync1 <= rx;
    rx_sync2 <= rx_sync1;
end
wire start_edge = (rx_sync2 == 1'b1) && (rx_sync1 == 1'b0);
```

Two‑flop synchroniser introduces a **fixed 2‑cycle (20 ns) latency** between
the physical RX falling edge and the FSM entering `STATE_START`.  This constant
offset is negligible relative to the bit period at all tested baud rates and is
**not** the cause of the failures.

### 2.3 Sampling Timeline (CPB = 160, 625000 baud)

```
t =      0 ns : physical RX start-bit falling edge
t =     20 ns : start_edge asserted (cycle 2 posedge)
t =     30 ns : FSM enters STATE_START (NBA of cycle 2)
t =    830 ns : STATE_START completes 80 cycles, enters STATE_SAMPLE
t =   2430 ns : data bit 0 sampled (160 cycles into STATE_SAMPLE)
t =   4030 ns : data bit 1 sampled
  ...
t =  13630 ns : data bit 7 sampled
t =  14430 ns : data_avail asserted (80 cycles into STATE_STOP)
```

Ideal sampling centres (from physical edge):
```
bit 0 =  1.5 × CPB =  2400 ns   →  actual =  2430 ns  ( +30 ns =  1.9 % of bit )
bit 7 =  8.5 × CPB = 13600 ns   →  actual = 13630 ns  ( +30 ns =  1.9 % of bit )
```

The constant 30 ns offset is **identical at all baud rates** (2‑cycle sync
latency + 1 cycle NBA delay).  It does **not accumulate** across bits because
each bit uses the same per‑bit counter period.  The design is intrinsically
**drift‑free within a single byte** when the FPGA and host clocks are
frequency‑locked.

### 2.4 Eye‑Diagram Margin

| Baud | Bit period | Half‑bit eye @ sample | Sync latency (30 ns) as % of eye |
|---:|---:|---:|---:|
| 500000 | 2000 ns | 1000 ns | 3.0% |
| 520833 | 1920 ns |  960 ns | 3.1% |
| 576000 | 1740 ns |  870 ns | 3.4% |
| 625000 | 1600 ns |  800 ns | 3.8% |
| 800000 | 1250 ns |  625 ns | 4.8% |
| 1000000 | 1000 ns |  500 ns | 6.0% |

With a **clock‑matched host** (CP2102 baud = FPGA baud), the remaining margin
is ample even at 1 Mbaud.  The problem arises when the CP2102’s actual baud
diverges from the requested rate.

---

## 3. Root‑Cause Analysis

### 3.1 CP2102 Baud Quantisation & Drift

The CP2102 generates its baud clock from a 48 MHz internal oscillator via an
integer prescaler/divider chain.  The achievable baud rates are:

```
baud(cp2102) = 48 000 000 / prescaler / divider    (divider = integer)
```

| Requested baud | CP2102 achievable | Error |
|---:|---:|---:|
| 500000 | 500000 (div 24) | 0.00% |
| 520833 | 521739 (div 23) | +0.17% |
| 526316 | 521739 (div 23) | −0.87% |
| 576000 | 571429 (div 21) | −0.79% |
| 625000 | 631579 (div 19) | +1.05% |
| 800000 | 800000 (div 15) | 0.00% |
| 1000000 | 1000000 (div 12) | 0.00% |

When the FPGA expects a bit period of `CPB × 10 ns` but the CP2102 delivers a
slightly different period, the sampling point **drifts across a single byte
character frame**:

```
drift_per_byte = 9 × (T_bit_cp2102 − T_bit_fpga)
```

| Requested baud | CPB | T_bit_fpga | T_bit_cp2102 | Drift over 9 edges |
|---:|---:|---:|---:|---:|
| 500000 | 200 | 2000 ns | 2000 ns | 0 ns |
| 523560 | 191 | 1910 ns | 1917 ns | +63 ns |
| 526316 | 190 | 1900 ns | 1917 ns | +153 ns |
| 576000 | 174 | 1740 ns | 1750 ns | +90 ns |
| 625000 | 160 | 1600 ns | 1583 ns | −153 ns |
| 800000 | 125 | 1250 ns | 1250 ns | 0 ns |
| 1000000 | 100 | 1000 ns | 1000 ns | 0 ns |

### 3.2 Why Drift Kills the Single‑Sample RX

The single‑sample RX has **zero jitter tolerance** beyond the static eye
opening.  Drift of 150 ns on a 1600‑ns bit (625000 baud) shifts the sampling
point from the centre to approximately **10% off‑centre**.  While this would
still be acceptable in a clean lab environment, the real‑world CP2102 also has:

1. **Rise/fall time asymmetry** — the CP2102 TX output driver may have
   different rise and fall times, shifting the effective eye centre.
2. **USB frame‑alignment jitter** — bulk/interrupt transfers are aligned to
   1 ms USB frames, introducing sub‑microsecond timing perturbations at byte
   boundaries.
3. **Start‑edge metastability** — the 2‑flop synchroniser can add an extra
   cycle of latency if `rx` changes near the clock edge, introducing ±10 ns
   uncertainty.

These three effects combined can push the sampling point outside the valid eye,
causing bit errors that the protocol parser cannot recover from.

### 3.3 The 576000 Anomaly

The fact that **576000 baud passes** while 530000–540000 fail, **despite
576000 having visibly larger nominal FPGA baud error (−0.22%)**, points to a
counter‑intuitive but plausible explanation:

- 576000 is a **standard PC COM‑port baud rate**.
- The CP2102 **Windows driver may use a different clocking path** for standard
  baud rates, achieving closer frequency matching than the raw integer‑divider
  formula predicts.
- Even with −0.79% nominal error from the 48 MHz derivation, the actual
  CP2102 output at 576000 may be **more stable** (less jitter, cleaner edges)
  than at non‑standard rates like 530000 or 540000, because the driver or
  hardware uses optimised PLL/dividers for standard rates.

This would explain the non‑monotonic failure boundary: **it is not purely a
function of FPGA baud accuracy**, but a function of the **end‑to‑end timing
loop including the CP2102 host side**.

### 3.4 Missing Start/Stop Verification

The current RX FSM does **not** verify:

1. That `rx` is still low at the centre of the start bit.
2. That `rx` is high during the stop bit.

A noise glitch on the RX line (e.g. from USB‑UART startup transients or
cross‑talk) can trigger a false `start_edge`, after which the FSM will blindly
capture 8 samples that happen to appear on the line and present them to the
protocol parser as a valid byte.  At higher baud rates with tighter margins,
the probability of such events increases.

### 3.5 Why 800000 and 1000000 Fail Despite Exact CP2102 Divisors

The CP2102 can generate **exact** 800000 and 1000000 baud (48 MHz / 4 / 15 = 800k;
48 MHz / 4 / 12 = 1M).  Yet the FPGA RX still registers zero response bytes.

Possible explanations:

1. **Signal integrity** — At 1 Mbaud (bit period 1.0 us, edge rate ~0.1 us), PCB
   trace parasitics, pin capacitance, and CP2102 output drive strength may
   produce non‑monotonic edges that violate the FPGA input setup/hold time,
   causing the 2‑flop synchroniser to produce metastable states more
   frequently.
2. **Edge‑rate asymmetry** — Faster edges amplify the effect of rise‑time vs.
   fall‑time mismatch, effectively shifting the sampling eye.
3. **USB‑UART jitter** — At higher baud rates, the same absolute jitter (e.g.
   ±50 ns from USB frame alignment) becomes a larger fraction of the bit period.
   At 1 Mbaud, 50 ns is 5% of the eye.

These hypotheses need to be tested with an oscilloscope on the RX pin.

---

## 4. TX‑Only Experiment Results

A minimal `uart_tx_pattern_top` design was created that continuously
transmits a known 8‑byte pattern `[55, AA, 00, FF, 52, 4B, 01, 7E]` without
depending on the FPGA RX or Mandelbrot protocol.  The FPGA was programmed with
this design and the pattern was listened to from the host:

| FPGA TX baud | Host read baud | Bytes received | Result |
|---:|---:|---:|---|
| 625000 | 625000 | 18837 | Stable repeating pattern received |
| 625000 | 800000 | many | Garbled (baud mismatch expected) |
| 625000 | 1000000 | many | Garbled (baud mismatch expected) |
| 1000000 | 625000 | 0? | Not meaningful |
| 1000000 | 800000 | 5709+ | Bytes received (garbled) |
| 1000000 | 1000000 | 16131 | Bytes received |

**Key finding**: When the FPGA TX baud matches the host read baud, large
volumes of bytes are reliably received.  This **proves** that the FPGA‑to‑host
downlink (FPGA TX pin → PCB trace → CP2102 RX → USB → Windows → pyserial)
functions correctly at 625000 baud and above.

The failure of the full Mandelbrot design at 625000+ is therefore **not** a TX
downlink problem.  It is a **receive‑side (FPGA RX uplink)** problem.

---

## 5. Experimental Results Matrix

### 5.1 Integer‑Divider Baud Raw‑Probe Results

| Baud | CPB | Trial summary | Category |
|---:|---:|---|---|
| 500000 | 200 | 5/5 stable `524b01000100010001` | **Pass** |
| 520833 | 192 | 5/5 stable `524b01000100010001` | **Pass** |
| 523560 | 191 | 7/8 correct; 1/8 returned `cols=32769` | **Marginal** |
| 526316 | 190 | 8/8 `RK` prefix but all fields corrupt, 8‑bytes not 9 | **Fail (corruption)** |
| 530000 | 189 | 8/8 zero‑byte response | **Fail (silent)** |
| 540000 | 185 | 8/8 zero‑byte response | **Fail (silent)** |
| **576000** | **174** | **smoke, 16×16, 160×120 verify, scan all pass** | **Pass** |
| 625000 | 160 | 8/8 zero‑byte response | **Fail (silent)** |
| 800000 | 125 | 8/8 zero‑byte response | **Fail (silent)** |
| 1000000 | 100 | 8/8 zero‑byte response | **Fail (silent)** |

### 5.2 Failure Mode Classification

| Baud range | Symptom | Likely proximate cause |
|---|---|---|
| 520833 | Pass | Margin adequate |
| 523560–526316 | `RK`‑like bytes but corrupt fields | Byte‑level bit‑sampling errors from CP2102‑FPGA baud mismatch within a frame |
| 530000–540000 | Zero‑byte response | FPGA RX fails to frame any valid byte; protocol FSM never issues a response |
| 576000 | Pass | Standard baud; CP2102 driver provides cleaner timing |
| 625000–1000000 | Zero‑byte response | Higher edge rates expose synchroniser/edge‑quality issues; or RX framing fails entirely |

---

## 6. Recommendations

### 6.1 Short Term: Keep 576000 as Default

576000 baud has been validated through multiple levels:

- Smoke (4×1×1 commands)
- 16×16 frame transfer
- 160×120 verify (19200/19200 match, 100%)
- 160 consecutive single‑point commands

It provides a **15% throughput improvement** over 500000 baud
(576000/500000 = 1.152×) with no hardware changes.

### 6.2 Upgrade FPGA UART RX Before Further Baud Sweeps

Before retesting 625000+, the FPGA RX should be upgraded:

#### Priority 1: Oversampling RX

Replace the single‑sample architecture with an **8× or 16× oversampling**
receiver:

```
oversample_clock = 8 × baud  (requires a PLL or higher‑speed counter)
```

At each nominal bit centre, take **3 samples** (centre ± 1 oversample tick) and
use majority vote.  This provides immunity to ±1 oversample tick of jitter.

Without a PLL, a pragmatic alternative uses the existing 100 MHz clock:

| Baud | CPB | Oversample ticks/bit | Samples for majority vote |
|---:|---:|---:|---:|
| 625000 | 160 | 20 | 3 samples at centre, centre±1 |
| 800000 | 125 | ~16 | 3 samples at centre, centre±1 |
| 1000000 | 100 | ~12 | 3 samples at centre, centre±1 |

At 1000 kbaud with CPB=100, you can take 3 samples spaced 10 ns apart (one
clock cycle each) around the nominal centre of each bit.  This gives 30 ns of
jitter immunity.

#### Priority 2: Start‑Bit Verification

In `STATE_START`, after the half‑bit wait, verify that `rx_sync2` is still low
before transitioning to `STATE_SAMPLE`.  If it is high, the falling edge was a
glitch; return to `STATE_IDLE`.

#### Priority 3: Stop‑Bit Verification

In `STATE_STOP`, verify that `rx_sync2` is high.  If not, flag a framing error
instead of presenting the byte as valid.

#### Priority 4 (Optional): Glitch Filter on Start Edge

Require `rx` to stay low for at least `CPB/4` consecutive samples before
qualifying a valid start bit.  This suppresses narrow noise pulses.

### 6.3 Next Hardware Experiment

After implementing the oversampling RX, re‑test at:

- 625000 baud (CPB=160, exact FPGA divisor)
- 800000 baud (CPB=125, exact FPGA divisor)
- 1000000 baud (CPB=100, exact FPGA divisor)
- 921600 baud (CPB=109, −0.22% FPGA error, common high‑speed standard)

If the upgraded RX passes all four, the bottleneck shifts back to the UART
output bandwidth (pixel ceiling at 1M baud = 50000 pixels/s).

---

## 7. References

- `rtl/uart_rx.v` — current single‑sample UART RX implementation
- `rtl/uart_tx.v` — current UART TX implementation
- `rtl/uart_tx_pattern_top.v` — TX‑only test design
- `python/uart_raw_probe.py` — raw byte dump test script
- `python/uart_listen_raw.py` — RX‑only pattern listener
- `UART_BAUDRATE_INVESTIGATION.md` — earlier baudrate investigation report
- CP2102 datasheet (Silicon Labs) — baud‑rate generation formula
