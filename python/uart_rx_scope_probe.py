#!/usr/bin/env python3
import argparse
import struct
import threading
import time

import serial


FRAME_LEN = 11
MAGIC = b"\xA5\x5A"


def writer(port, stop_event, payload, interval):
    data = bytes([payload]) * 256
    while not stop_event.is_set():
        port.write(data)
        port.flush()
        time.sleep(interval)


def parse_frames(buf):
    frames = []
    i = 0
    while True:
        idx = buf.find(MAGIC, i)
        if idx < 0 or len(buf) - idx < FRAME_LEN:
            return frames, buf[idx:] if idx >= 0 else b""
        frame = buf[idx:idx + FRAME_LEN]
        seq = frame[2]
        level = frame[3] & 1
        falls = struct.unpack_from("<H", frame, 4)[0]
        rises = struct.unpack_from("<H", frame, 6)[0]
        low = frame[8] | (frame[9] << 8) | (frame[10] << 16)
        frames.append((seq, level, falls, rises, low))
        i = idx + FRAME_LEN


def main():
    parser = argparse.ArgumentParser(description="Probe whether FPGA samples edges on uart_rx")
    parser.add_argument("--port", default="COM6")
    parser.add_argument("--baud", type=int, default=1536000)
    parser.add_argument("--seconds", type=float, default=5.0)
    parser.add_argument("--payload", type=lambda x: int(x, 0), default=0x55)
    parser.add_argument("--write-interval", type=float, default=0.01)
    args = parser.parse_args()

    stop_event = threading.Event()
    buf = b""
    frames = []

    with serial.Serial(args.port, args.baud, timeout=0.05) as ser:
        ser.reset_input_buffer()
        ser.reset_output_buffer()
        thread = threading.Thread(
            target=writer,
            args=(ser, stop_event, args.payload, args.write_interval),
            daemon=True,
        )
        thread.start()
        deadline = time.time() + args.seconds
        try:
            while time.time() < deadline:
                data = ser.read(4096)
                if data:
                    buf += data
                    new_frames, buf = parse_frames(buf)
                    for frame in new_frames:
                        seq, level, falls, rises, low = frame
                        print(
                            f"seq={seq:3d} level={level} falls={falls:5d} "
                            f"rises={rises:5d} low_samples={low:7d}"
                        )
                        frames.append(frame)
        finally:
            stop_event.set()
            thread.join(timeout=0.2)

    total_falls = sum(frame[2] for frame in frames)
    total_rises = sum(frame[3] for frame in frames)
    total_low = sum(frame[4] for frame in frames)
    print(
        f"frames={len(frames)} total_falls={total_falls} "
        f"total_rises={total_rises} total_low_samples={total_low}"
    )


if __name__ == "__main__":
    main()
