#!/usr/bin/env python3
import argparse
import time

import serial


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", default="COM9")
    ap.add_argument("--baud", type=int, required=True)
    ap.add_argument("--trials", type=int, default=8)
    ap.add_argument("--timeout", type=float, default=0.5)
    args = ap.parse_args()

    pattern = bytes([0x55, 0xAA, 0x00, 0xFF, 0x52, 0x4B, 0x01, 0x7E])
    ok = 0
    with serial.Serial(args.port, args.baud, timeout=args.timeout) as ser:
        for trial in range(1, args.trials + 1):
            ser.reset_input_buffer()
            ser.reset_output_buffer()
            data = bytearray()
            for value in pattern:
                ser.write(bytes([value]))
                ser.flush()
                data.extend(ser.read(1))
            passed = data == pattern
            ok += 1 if passed else 0
            print(f"trial={trial} len={len(data)} pass={passed} rx={bytes(data).hex()}")
            time.sleep(0.05)
    print(f"baud={args.baud} echo_pass={ok}/{args.trials}")
    return 0 if ok == args.trials else 1


if __name__ == "__main__":
    raise SystemExit(main())
