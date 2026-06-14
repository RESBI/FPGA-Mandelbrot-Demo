#!/usr/bin/env python3
"""
Mandelbrot FPGA Accelerator Host Script
Sends computation commands via UART and renders results.

Pixel data format: uint16 little-endian (2 bytes per pixel).

Protocol (binary, little-endian):
  Command:  0x4D | precision(0=FP64,1=FP128) | rows(u16) | cols(u16) |
            max_iter(u16) | center_re(FP) | center_im(FP) | step(FP) | checksum(XOR)
  Response: 0x52 0x4B | rows(u16) | cols(u16) | pixel_data(2*rows*cols bytes) | checksum(XOR)
"""

import serial
import struct
import time
import sys
import argparse
import os

PORT = "COM6"
BAUD = 12000000
TIMEOUT = 180.0
DEFAULT_DYNAMIC_OWNER_DEPTH = 4096
DEFAULT_MAX_HOST_BYTES = 512 * 1024 * 1024


def estimate_uart_seconds(width, height):
    # UART is 8N1, so every payload byte costs 10 serial bits.
    response_bytes = 6 + width * height * 2 + 1
    return response_bytes * 10.0 / BAUD


def validate_request(args):
    pixels = args.width * args.height
    data_bytes = pixels * 2
    est_seconds = estimate_uart_seconds(args.width, args.height)

    if args.width <= 0 or args.height <= 0:
        print("ERROR: width and height must be positive")
        sys.exit(1)
    if args.width > 65535 or args.height > 65535:
        print("ERROR: width and height must fit the 16-bit hardware protocol")
        sys.exit(1)
    if args.max_iter > 65535:
        print("ERROR: max_iter must be <= 65535")
        sys.exit(1)

    if not args.force_large_frame and args.height > DEFAULT_DYNAMIC_OWNER_DEPTH:
        print("ERROR: requested height exceeds the current default dynamic scheduler limit")
        print(f"  height={args.height}, dynamic owner table depth={DEFAULT_DYNAMIC_OWNER_DEPTH}")
        print("  The current default bitstream records dynamic row ownership for 4096 rows.")
        print("  A taller frame can stall when raster collection reaches an unrecorded row.")
        print("  Rebuild with a larger DYNAMIC_OWNER_DEPTH or use an appropriate static build.")
        print("  Pass --force-large-frame only if the programmed bitstream supports this frame.")
        sys.exit(1)

    if not args.force_large_frame and data_bytes > DEFAULT_MAX_HOST_BYTES:
        print("ERROR: response is too large for the default host receive path")
        print(f"  data bytes={data_bytes}, default limit={DEFAULT_MAX_HOST_BYTES}")
        print("  The host currently buffers the full response before rendering/verifying.")
        print("  Use a smaller frame, implement streaming output, or pass --force-large-frame knowingly.")
        sys.exit(1)

    print(f"Estimated UART payload time at {BAUD} baud: {est_seconds:.1f}s")

# ============================================================
#  Color Palette
# ============================================================
def make_palette(n_colors=256):
    """Generate a color palette for Mandelbrot rendering."""
    palette = []
    for i in range(n_colors):
        if i == 0:
            palette.append((0, 0, 0))
        else:
            r = int((i * 9) % 256)
            g = int((i * 13 + 80) % 256)
            b = int((i * 17 + 160) % 256)
            palette.append((r, g, b))
    return palette


def render_image(pixels, width, height, max_iter, output_path):
    """Render pixel data to PNG image. Pixels are 16-bit iteration counts."""
    try:
        from PIL import Image
    except ImportError:
        print("ERROR: Pillow not installed. Run: pip install pillow")
        sys.exit(1)

    # Build palette: map 16-bit values -> RGB
    # For values > palette size, wrap with periodic mapping
    pal_size = min(2048, max_iter + 1)
    palette = make_palette(pal_size)
    img = Image.new("RGB", (width, height))
    for y in range(height):
        for x in range(width):
            val = pixels[y * width + x]
            if val >= max_iter:
                color = (0, 0, 0)  # black for points in the set
            else:
                idx = val % pal_size
                color = palette[idx]
            img.putpixel((x, y), color)
    img.save(output_path)
    print(f"Image saved to {output_path}")


def render_text(pixels, width, height, max_iter, output_path):
    """Render pixel data to ASCII text."""
    chars = " .:-=+*#%@"
    with open(output_path, "w") as f:
        for y in range(height):
            line = ""
            for x in range(width):
                val = pixels[y * width + x]
                if val >= max_iter:
                    line += " "
                else:
                    idx = int(val * (len(chars) - 1) / max(max_iter, 1))
                    line += chars[idx]
            f.write(line + "\n")
    print(f"Text saved to {output_path}")


# ============================================================
#  FP128 encoding / decoding
# ============================================================
def float_to_fp128(val):
    import math
    if val == 0.0:
        return b'\x00' * 16
    sign = 0
    if val < 0:
        sign = 1
        val = -val
    BIAS = 16383
    exp = int(math.floor(math.log2(val)))
    if exp > 16383:
        raise OverflowError("FP128 overflow")
    if exp < -16382:
        return b'\x00' * 16
    mantissa_val = val / (2.0 ** exp) - 1.0
    man_int = int(mantissa_val * (2 ** 112))
    fp_val = (sign << 127) | ((exp + BIAS) << 112) | man_int
    return struct.pack('<QQ', fp_val & 0xFFFFFFFFFFFFFFFF, (fp_val >> 64) & 0xFFFFFFFFFFFFFFFF)


# ============================================================
#  FPGA Communication
# ============================================================
class MandelbrotFPGA:
    def __init__(self, port=PORT, baud=BAUD, timeout=TIMEOUT):
        self.ser = serial.Serial(port, baud, timeout=timeout)

    def close(self):
        if self.ser:
            self.ser.close()

    def send_command(self, center_re, center_im, step, max_iter, width, height, mode='fp64'):
        precision = 0 if mode == 'fp64' else 1
        payload = bytearray()
        payload.append(0x4D)
        payload.append(precision)

        if mode == 'fp64':
            fp_cre = struct.pack('<d', center_re)
            fp_cim = struct.pack('<d', center_im)
            fp_stp = struct.pack('<d', step)
        else:
            fp_cre = float_to_fp128(center_re)
            fp_cim = float_to_fp128(center_im)
            fp_stp = float_to_fp128(step)

        payload += struct.pack('<H', height)
        payload += struct.pack('<H', width)
        payload += struct.pack('<H', max_iter)
        payload += fp_cre
        payload += fp_cim
        payload += fp_stp

        checksum = 0
        for b in payload:
            checksum ^= b
        payload.append(checksum)

        print(f"Sending: {width}x{height}, max_iter={max_iter}, "
              f"center=({center_re},{center_im}), step={step}, mode={mode}")
        print(f"Command: {len(payload)} bytes")
        self.ser.reset_input_buffer()
        self.ser.write(payload)
        self.ser.flush()

    def recv_response(self, width, height):
        total_pixels = width * height
        header = self.ser.read(6)
        if len(header) < 6:
            print(f"ERROR: Incomplete header: {header.hex() if header else 'none'}")
            return None

        magic_r, magic_k = header[0], header[1]
        resp_rows = struct.unpack('<H', header[2:4])[0]
        resp_cols = struct.unpack('<H', header[4:6])[0]

        if magic_r != 0x52 or magic_k != 0x4B:
            print(f"ERROR: Bad magic: {hex(magic_r)} {hex(magic_k)}, header={header.hex()}")
            return None

        print(f"Response header: {resp_rows}x{resp_cols}")
        if resp_rows != height or resp_cols != width:
            print(f"WARNING: Dims mismatch: {resp_rows}x{resp_cols} vs {height}x{width}")
            total_pixels = resp_rows * resp_cols

        # 2 bytes per pixel (uint16 LE)
        total_data_bytes = total_pixels * 2
        print(f"Receiving {total_data_bytes} data bytes ({total_pixels} pixels)...")

        raw = bytearray()
        checksum_calc = 0

        while len(raw) < total_data_bytes:
            chunk = self.ser.read(min(4096, total_data_bytes - len(raw)))
            if not chunk:
                print(f"ERROR: Timeout after {len(raw)}/{total_data_bytes} bytes")
                break
            raw += chunk
            for b in chunk:
                checksum_calc ^= b
            if len(raw) % 20000 == 0:
                print(f"  Progress: {len(raw)}/{total_data_bytes}")

        if len(raw) < total_data_bytes:
            return None

        ck_byte = self.ser.read(1)
        if len(ck_byte) < 1:
            print("ERROR: Missing checksum")
            return None

        if checksum_calc != ck_byte[0]:
            print(f"WARNING: Checksum mismatch: calc=0x{checksum_calc:02X}, recv=0x{ck_byte[0]:02X}")

        # Parse uint16 LE
        pixels = []
        for i in range(0, len(raw), 2):
            pixels.append(struct.unpack('<H', raw[i:i+2])[0])

        print(f"Received {len(pixels)} pixels")
        return pixels


# ============================================================
#  Software Reference
# ============================================================
def mandelbrot_software(center_re, center_im, step, max_iter, width, height):
    pixels = []
    # Match RTL: half_w/half_h are integer truncated, not floating half pixels.
    half_w = (width - 1) >> 1
    half_h = (height - 1) >> 1
    re_start = center_re - half_w * step
    im_start = center_im + half_h * step
    for y in range(height):
        c_im = im_start - y * step
        c_re = re_start
        for x in range(width):
            z_re = 0.0
            z_im = 0.0
            it = 0
            while it < max_iter:
                z_re_sq = z_re * z_re
                z_im_sq = z_im * z_im
                if z_re_sq + z_im_sq > 4.0:
                    break
                z_im = 2.0 * z_re * z_im + c_im
                z_re = z_re_sq - z_im_sq + c_re
                it += 1
            pixels.append(it)
            c_re += step
    return pixels


def compare_results(hw, sw, width, height):
    total = width * height
    match = sum(1 for i in range(total) if hw[i] == sw[i])
    pct = 100.0 * match / total if total > 0 else 0
    print(f"HW vs SW: {match}/{total} match ({pct:.2f}%)")
    if match != total:
        diffs = [(i, hw[i], sw[i]) for i in range(total) if hw[i] != sw[i]]
        print(f"  Differences: {len(diffs)}")
        for i, h, s in diffs[:10]:
            y, x = divmod(i, width)
            print(f"    [{y},{x}] HW={h} SW={s}")
    return match == total


# ============================================================
#  Main
# ============================================================
def main():
    parser = argparse.ArgumentParser(description="Mandelbrot FPGA Accelerator Host")
    parser.add_argument("--center", nargs=2, type=float, default=[-0.5, 0.0],
                        help="Center point (real imag)")
    parser.add_argument("--step", type=float, default=0.005,
                        help="Pixel step size")
    parser.add_argument("--max-iter", type=int, default=256,
                        help="Maximum iterations (up to 65535)")
    parser.add_argument("--width", type=int, default=160,
                        help="Image width")
    parser.add_argument("--height", type=int, default=120,
                        help="Image height")
    parser.add_argument("--output", type=str, default="mandelbrot.png",
                        help="Output file path")
    parser.add_argument("--format", type=str, choices=["png", "bmp", "txt"], default="png",
                        help="Output format")
    parser.add_argument("--mode", type=str, choices=["fp64", "fp128"], default="fp64",
                        help="Precision mode")
    parser.add_argument("--verify", action="store_true",
                        help="Also compute in software and compare")
    parser.add_argument("--port", type=str, default=PORT,
                        help=f"Serial port (default: {PORT})")
    parser.add_argument("--timeout", type=float, default=TIMEOUT,
                        help=f"Serial timeout in seconds (default: {TIMEOUT})")
    parser.add_argument("--force-large-frame", action="store_true",
                        help="Bypass host-side guards for very large frames; use only with a matching bitstream")
    args = parser.parse_args()

    validate_request(args)

    center_re, center_im = args.center
    print("=" * 50)
    print(" Mandelbrot FPGA Accelerator")
    print(f" Mode: {args.mode.upper()}")
    print(f" Center: ({center_re}, {center_im})")
    print(f" Step: {args.step}")
    print(f" Max iterations: {args.max_iter}")
    print(f" Image: {args.width}x{args.height}")
    print("=" * 50)

    fpga = MandelbrotFPGA(port=args.port, timeout=args.timeout)
    try:
        total_pixels = args.width * args.height
        t0 = time.perf_counter()
        fpga.send_command(center_re, center_im, args.step, args.max_iter,
                          args.width, args.height, mode=args.mode)
        pixels = fpga.recv_response(args.width, args.height)
        t_recv = time.perf_counter()
        if pixels is None:
            print("ERROR: Failed to receive response")
            sys.exit(1)

        comm_elapsed = t_recv - t0
        pps = total_pixels / comm_elapsed if comm_elapsed > 0 else 0.0
        print(f"FPGA elapsed: {comm_elapsed:.3f}s ({pps:.2f} pixels/s)")

        ext = os.path.splitext(args.output)[1].lower()
        if args.format == "txt" or ext == ".txt":
            render_text(pixels, args.width, args.height, args.max_iter, args.output)
        else:
            render_image(pixels, args.width, args.height, args.max_iter, args.output)
        t_render = time.perf_counter()
        print(f"Render elapsed: {t_render - t_recv:.3f}s")

        if args.verify:
            print("\n--- Software Verification ---")
            t_sw0 = time.perf_counter()
            sw = mandelbrot_software(center_re, center_im, args.step,
                                     args.max_iter, args.width, args.height)
            t_sw1 = time.perf_counter()
            compare_results(pixels, sw, args.width, args.height)
            print(f"Software elapsed: {t_sw1 - t_sw0:.3f}s")
        t_done = time.perf_counter()
        print(f"Total elapsed: {t_done - t0:.3f}s")
    finally:
        fpga.close()


if __name__ == "__main__":
    main()
