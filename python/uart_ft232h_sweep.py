#!/usr/bin/env python3
"""FT232H/FT232HL UART baud sweep helper.

The script patches UART BAUD/CLOCKS_PER_BIT, builds/programs either the TX-only
pattern design or the full Mandelbrot design, then runs a serial check on COM6.
It is intentionally simple and serial: only one process owns the port at a time.
"""

import argparse
import pathlib
import re
import subprocess
import sys


ROOT = pathlib.Path(__file__).resolve().parents[1]
VIVADO = r"Z:\Softwares\Xilinx\Vivado\2024.2\bin\vivado.bat"
CLK_HZ = 24_576_000.0
UART_RX = ROOT / "rtl" / "uart_rx.v"
UART_TX = ROOT / "rtl" / "uart_tx.v"
CONFIG = ROOT / "rtl" / "config.vh"
HOST = ROOT / "python" / "mandelbrot_host.py"


def patch_text(path, pattern, repl):
    text = path.read_text()
    new_text, count = re.subn(pattern, repl, text)
    if count == 0:
        raise RuntimeError(f"pattern not found in {path}: {pattern}")
    path.write_text(new_text)


def set_baud(baud):
    approx_cpb = max(1, round(CLK_HZ / baud))
    patch_text(CONFIG, r"`define CFG_UART_BAUD \d+", f"`define CFG_UART_BAUD {baud}")
    patch_text(UART_RX, r"parameter CLOCKS_PER_BIT = CLK_HZ / BAUD|parameter CLOCKS_PER_BIT = \d+", "parameter CLOCKS_PER_BIT = CLK_HZ / BAUD")
    patch_text(UART_TX, r"parameter CLOCKS_PER_BIT = CLK_HZ / BAUD|parameter CLOCKS_PER_BIT = \d+", "parameter CLOCKS_PER_BIT = CLK_HZ / BAUD")
    patch_text(HOST, r"BAUD = \d+", f"BAUD = {baud}")
    return approx_cpb


def set_cpb(cpb):
    baud = round(CLK_HZ / cpb)
    return set_baud(baud)


def set_legacy_cpb(cpb):
    raise RuntimeError("legacy integer CLOCKS_PER_BIT patching is no longer supported; use --cpb or --baud with fractional CFG_UART_BAUD")


def run(cmd, timeout):
    print("RUN:", " ".join(str(x) for x in cmd), flush=True)
    return subprocess.run([str(x) for x in cmd], cwd=str(ROOT), timeout=timeout)


def build_and_program_tx():
    if run([VIVADO, "-mode", "batch", "-source", "build_uart_tx_pattern.tcl"], 600).returncode != 0:
        return False
    bit = ROOT / "uart_tx_pattern_zu4ev_proj" / "uart_tx_pattern.runs" / "impl_1" / "uart_tx_pattern_top.bit"
    return run([VIVADO, "-mode", "batch", "-source", "program.tcl", "-tclargs", bit], 180).returncode == 0


def build_and_program_full():
    if run([VIVADO, "-mode", "batch", "-source", "build_fp64.tcl"], 900).returncode != 0:
        return False
    bit = ROOT / "fp64_zu4ev_proj" / "mandelbrot_fp64.runs" / "impl_1" / "top.bit"
    return run([VIVADO, "-mode", "batch", "-source", "program.tcl", "-tclargs", bit], 180).returncode == 0


def build_and_program_echo():
    if run([VIVADO, "-mode", "batch", "-source", "build_uart_echo.tcl"], 600).returncode != 0:
        return False
    bit = ROOT / "uart_echo_zu4ev_proj" / "uart_echo.runs" / "impl_1" / "uart_echo_top.bit"
    return run([VIVADO, "-mode", "batch", "-source", "program.tcl", "-tclargs", bit], 180).returncode == 0


def test_tx(port, baud, seconds):
    cmd = [sys.executable, ROOT / "python" / "uart_listen_raw.py",
           "--port", port, "--baud", str(baud), "--seconds", str(seconds), "--max-raw", "64"]
    return run(cmd, int(seconds + 15))


def test_full(port, baud):
    cmd = [sys.executable, ROOT / "python" / "uart_raw_probe.py",
           "--port", port, "--baud", str(baud), "--trials", "4", "--read-window", "1",
           "--rows", "1", "--cols", "1", "--max-iter", "5", "--center-re", "2.5", "--center-im", "0.0"]
    return run(cmd, 30)


def test_echo(port, baud):
    cmd = [sys.executable, ROOT / "python" / "uart_echo_probe.py",
           "--port", port, "--baud", str(baud), "--trials", "8", "--timeout", "0.5"]
    return run(cmd, 30)


def main():
    ap = argparse.ArgumentParser()
    baud_group = ap.add_mutually_exclusive_group(required=True)
    baud_group.add_argument("--baud", type=int, help="target UART baud for fractional generator")
    baud_group.add_argument("--cpb", type=int, help="24.576 MHz clocks per UART bit, converted to nearest baud")
    ap.add_argument("--port", default="COM6")
    ap.add_argument("--mode", choices=["tx", "echo", "full"], default="tx")
    ap.add_argument("--no-build", action="store_true")
    ap.add_argument("--no-program", action="store_true")
    ap.add_argument("--seconds", type=float, default=1.0)
    args = ap.parse_args()

    if args.baud is not None:
        baud = args.baud
        approx_cpb = set_baud(baud)
        print(f"baud={baud} approx_integer_cpb={approx_cpb}")
    else:
        baud = round(CLK_HZ / args.cpb)
        approx_cpb = set_cpb(args.cpb)
        print(f"cpb={args.cpb} baud={baud} approx_integer_cpb={approx_cpb}")

    if not args.no_build or not args.no_program:
        if args.mode == "tx":
            ok = build_and_program_tx()
        elif args.mode == "echo":
            ok = build_and_program_echo()
        else:
            ok = build_and_program_full()
        if not ok:
            return 2

    if args.mode == "tx":
        return test_tx(args.port, baud, args.seconds).returncode
    if args.mode == "echo":
        return test_echo(args.port, baud).returncode
    return test_full(args.port, baud).returncode


if __name__ == "__main__":
    raise SystemExit(main())
