#!/usr/bin/env python3
"""Listen to UART bytes without transmitting anything."""

import argparse
import time

import serial


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", default="COM9")
    ap.add_argument("--baud", type=int, required=True)
    ap.add_argument("--seconds", type=float, default=2.0)
    ap.add_argument("--max-raw", type=int, default=128)
    args = ap.parse_args()

    data = bytearray()
    with serial.Serial(args.port, args.baud, timeout=0) as ser:
        ser.reset_input_buffer()
        deadline = time.monotonic() + args.seconds
        while time.monotonic() < deadline:
            waiting = ser.in_waiting
            if waiting:
                data += ser.read(waiting)
            else:
                time.sleep(0.01)

    raw = bytes(data)
    preview = raw[:args.max_raw].hex()
    if len(raw) > args.max_raw:
        preview += "..."
    print(f"baud={args.baud} seconds={args.seconds} len={len(data)} raw_preview={preview}")
    if data:
        expected = bytes([0x55, 0xAA, 0x00, 0xFF, 0x52, 0x4B, 0x01, 0x7E])
        hits = raw.count(expected)
        print(f"pattern_hits={hits} expected={expected.hex()}")


if __name__ == "__main__":
    raise SystemExit(main())
