#!/usr/bin/env python3
"""Baudrate sweep helper for board experiments.

This script updates the project baudrate constants, then optionally runs Vivado
build/program and a serial smoke test. It is intentionally project-local so the
exact experiment steps are reproducible.
"""

import argparse
import pathlib
import re
import struct
import subprocess
import sys
import time

import serial


ROOT = pathlib.Path(__file__).resolve().parents[1]
VIVADO = r"Z:\Softwares\Xilinx\Vivado\2020.2\bin\vivado.bat"


FILES = [
    ROOT / "rtl" / "config.vh",
    ROOT / "python" / "mandelbrot_host.py",
    ROOT / "python" / "test_esc.py",
    ROOT / "python" / "test_points.py",
    ROOT / "python" / "scan_points.py",
]


def patch_file(path, baud):
    text = path.read_text()
    if path.name == "config.vh":
        text = re.sub(r"`define CFG_UART_BAUD \d+", f"`define CFG_UART_BAUD {baud}", text)
    elif path.name == "mandelbrot_host.py":
        text = re.sub(r"BAUD = \d+", f"BAUD = {baud}", text)
    else:
        text = re.sub(r"serial\.Serial\(([^,]+),\s*\d+,", rf"serial.Serial(\1, {baud},", text)
    path.write_text(text)


def set_baud(baud):
    for path in FILES:
        patch_file(path, baud)


def run(cmd, timeout):
    print("RUN:", " ".join(cmd), flush=True)
    return subprocess.run(cmd, cwd=str(ROOT), timeout=timeout)


def build():
    return run([VIVADO, "-mode", "batch", "-source", "build_fp64.tcl"], timeout=600)


def program():
    return run([VIVADO, "-mode", "batch", "-source", "program.tcl"], timeout=180)


def make_packet(cr, ci, max_iter=5, rows=1, cols=1, step=0.005):
    p = bytearray([0x4D, 0x00])
    p += struct.pack("<HHH", rows, cols, max_iter)
    p += struct.pack("<d", cr)
    p += struct.pack("<d", ci)
    p += struct.pack("<d", step)
    ck = 0
    for b in p:
        ck ^= b
    p.append(ck)
    return p


def smoke(port, baud, attempts=3):
    tests = [(2.5, 0.0), (2.6, 0.0), (3.0, 0.0), (4.1, 0.0)]
    with serial.Serial(port, baud, timeout=5) as ser:
        for cr, ci in tests:
            ok = False
            for attempt in range(1, attempts + 1):
                ser.reset_input_buffer()
                ser.reset_output_buffer()
                ser.write(make_packet(cr, ci))
                ser.flush()
                data = ser.read(100)
                if len(data) >= 8 and data[0:2] == b"RK":
                    val = struct.unpack("<H", data[6:8])[0]
                    print(f"attempt={attempt} c=({cr},{ci}) len={len(data)} iter={val} raw={data.hex()}")
                    if val == 1:
                        ok = True
                        break
                else:
                    print(f"attempt={attempt} c=({cr},{ci}) len={len(data)} raw={data.hex()}")
                time.sleep(0.1)
            if not ok:
                return False
    return True


def small_frame(port, baud):
    cmd = [
        sys.executable,
        str(ROOT / "python" / "mandelbrot_host.py"),
        "--width", "16",
        "--height", "16",
        "--max-iter", "16",
        "--center", "1.0", "1.0",
        "--step", "0.01",
        "--timeout", "30",
        "--output", str(ROOT / "python" / "baud_sweep_tmp.png"),
    ]
    return run(cmd, timeout=60).returncode == 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--baud", type=int, required=True)
    ap.add_argument("--port", default="COM4")
    ap.add_argument("--no-build", action="store_true")
    ap.add_argument("--no-program", action="store_true")
    ap.add_argument("--no-test", action="store_true")
    ap.add_argument("--small-frame", action="store_true")
    args = ap.parse_args()

    set_baud(args.baud)
    print(f"baud={args.baud} fractional_nco=rtl/config.vh CFG_UART_BAUD")

    if not args.no_build and build().returncode != 0:
        return 2
    if not args.no_program and program().returncode != 0:
        return 3
    if args.no_test:
        return 0

    ok = smoke(args.port, args.baud)
    print("SMOKE", "PASS" if ok else "FAIL")
    if not ok:
        return 4

    if args.small_frame:
        ok = small_frame(args.port, args.baud)
        print("SMALL_FRAME", "PASS" if ok else "FAIL")
        return 0 if ok else 5
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
