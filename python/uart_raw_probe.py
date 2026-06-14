#!/usr/bin/env python3
"""Raw UART response probe.

This script deliberately does not decide pass/fail from Mandelbrot semantics.
It sends a fixed command, reads whatever bytes arrive within a time window, and
prints both raw bytes and a lightweight protocol parse.
"""

import argparse
import struct
import time

import serial


def checksum(data):
    value = 0
    for byte in data:
        value ^= byte
    return value


def make_command(rows, cols, max_iter, center_re, center_im, step):
    packet = bytearray([0x4D, 0x00])
    packet += struct.pack("<HHH", rows, cols, max_iter)
    packet += struct.pack("<d", center_re)
    packet += struct.pack("<d", center_im)
    packet += struct.pack("<d", step)
    packet.append(checksum(packet))
    return packet


def read_window(ser, seconds):
    deadline = time.monotonic() + seconds
    data = bytearray()
    while time.monotonic() < deadline:
        waiting = ser.in_waiting
        if waiting:
            data += ser.read(waiting)
        else:
            time.sleep(0.01)
    waiting = ser.in_waiting
    if waiting:
        data += ser.read(waiting)
    return bytes(data)


def parse_response(data, expected_rows, expected_cols):
    if not data:
        return "no-bytes"
    parts = []
    idx = data.find(b"RK")
    if idx < 0:
        parts.append("no-RK")
    else:
        parts.append(f"RK-at={idx}")
        if len(data) >= idx + 6:
            rows, cols = struct.unpack("<HH", data[idx + 2:idx + 6])
            parts.append(f"rows={rows}")
            parts.append(f"cols={cols}")
            expected_len = 2 + 2 + 2 + rows * cols * 2 + 1
            parts.append(f"declared_len={expected_len}")
            parts.append(f"expected_declared_len={2 + 2 + 2 + expected_rows * expected_cols * 2 + 1}")
            if len(data) >= idx + expected_len and expected_len >= 7:
                frame = data[idx:idx + expected_len]
                ck = checksum(frame[6:-1])
                parts.append(f"checksum={'ok' if ck == frame[-1] else 'bad'}")
                parts.append(f"rx_checksum=0x{frame[-1]:02x}")
                parts.append(f"calc_checksum=0x{ck:02x}")
            else:
                parts.append("incomplete-declared-frame")
    if len(data) >= 9:
        first_word = struct.unpack("<H", data[6:8])[0]
        parts.append(f"word_at_6={first_word}")
    return " ".join(parts)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", default="COM4")
    ap.add_argument("--baud", type=int, required=True)
    ap.add_argument("--trials", type=int, default=5)
    ap.add_argument("--read-window", type=float, default=1.0)
    ap.add_argument("--rows", type=int, default=1)
    ap.add_argument("--cols", type=int, default=1)
    ap.add_argument("--max-iter", type=int, default=5)
    ap.add_argument("--center-re", type=float, default=2.5)
    ap.add_argument("--center-im", type=float, default=0.0)
    ap.add_argument("--step", type=float, default=0.005)
    ap.add_argument("--gap", type=float, default=0.2)
    args = ap.parse_args()

    command = make_command(args.rows, args.cols, args.max_iter, args.center_re, args.center_im, args.step)
    expected_len = 2 + 2 + 2 + args.rows * args.cols * 2 + 1
    print(f"baud={args.baud} command_len={len(command)} expected_response_len={expected_len}")
    print(f"tx={command.hex()}")

    with serial.Serial(args.port, args.baud, timeout=0) as ser:
        for trial in range(1, args.trials + 1):
            ser.reset_input_buffer()
            ser.reset_output_buffer()
            ser.write(command)
            ser.flush()
            data = read_window(ser, args.read_window)
            parsed = parse_response(data, args.rows, args.cols)
            print(f"trial={trial} len={len(data)} raw={data.hex()} parse={parsed}")
            time.sleep(args.gap)


if __name__ == "__main__":
    raise SystemExit(main())
