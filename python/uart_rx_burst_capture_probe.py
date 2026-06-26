#!/usr/bin/env python3
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
    return bytes(packet)


def read_exact_window(ser, seconds):
    deadline = time.monotonic() + seconds
    data = bytearray()
    while time.monotonic() < deadline:
        waiting = ser.in_waiting
        if waiting:
            data += ser.read(waiting)
        else:
            time.sleep(0.005)
    waiting = ser.in_waiting
    if waiting:
        data += ser.read(waiting)
    return bytes(data)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", default="COM6")
    ap.add_argument("--baud", type=int, required=True)
    ap.add_argument("--trials", type=int, default=4)
    ap.add_argument("--read-window", type=float, default=0.5)
    ap.add_argument("--rows", type=int, default=1)
    ap.add_argument("--cols", type=int, default=1)
    ap.add_argument("--max-iter", type=int, default=5)
    ap.add_argument("--center-re", type=float, default=2.5)
    ap.add_argument("--center-im", type=float, default=0.0)
    ap.add_argument("--step", type=float, default=0.005)
    ap.add_argument("--gap", type=float, default=0.2)
    ap.add_argument("--tx-byte-gap", type=float, default=0.0)
    args = ap.parse_args()

    command = make_command(args.rows, args.cols, args.max_iter, args.center_re, args.center_im, args.step)
    expected_xor = checksum(command)
    print(f"baud={args.baud} command_len={len(command)} expected_xor=0x{expected_xor:02x}")
    print(f"tx={command.hex()}")

    with serial.Serial(args.port, args.baud, timeout=0) as ser:
        for trial in range(1, args.trials + 1):
            ser.reset_input_buffer()
            ser.reset_output_buffer()
            if args.tx_byte_gap > 0:
                for byte in command:
                    ser.write(bytes([byte]))
                    ser.flush()
                    time.sleep(args.tx_byte_gap)
            else:
                ser.write(command)
                ser.flush()
            data = read_exact_window(ser, args.read_window)
            if len(data) >= 5 and data[0:2] == b"BC":
                count_raw = data[2]
                overflow = bool(count_raw & 0x80)
                count = count_raw & 0x7f
                rx_xor = data[3]
                captured = data[5:5 + count]
                match = captured == command[:len(captured)] and count == len(command) and rx_xor == 0
                print(
                    f"trial={trial} len={len(data)} count={count} overflow={overflow} "
                    f"rx_xor=0x{rx_xor:02x} match={match} captured={captured.hex()} raw={data.hex()}"
                )
            else:
                print(f"trial={trial} len={len(data)} no-BC raw={data.hex()}")
            time.sleep(args.gap)


if __name__ == "__main__":
    raise SystemExit(main())
