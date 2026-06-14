#!/usr/bin/env python3
"""
Mandelbrot FPGA Accelerator Host Script
Sends computation commands via UART and renders results.

Pixel data format: uint16 little-endian (2 bytes per pixel).

Protocol (binary, little-endian):
  Command:  0x4D | precision(0=FP64,1=FP128) | rows(u16) | cols(u16) |
            max_iter(u16) | center_re(FP) | center_im(FP) | step(FP) | checksum(XOR)
  Legacy response: 0x52 0x4B | rows(u16) | cols(u16) | pixel_data | checksum(XOR)
  Tiled response:  0x52 0x54 | rows(u16) | cols(u16) |
                   repeated tiles: 0x54 0x44 | row(u16) | col(u16) |
                   tile_rows(u16) | tile_cols(u16) | pixel_data | checksum(XOR) |
                   end: 0x54 0x45 | rows(u16) | cols(u16)
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
    def __init__(self, port=PORT, baud=BAUD, timeout=TIMEOUT, verbose=True):
        self.ser = serial.Serial(port, baud, timeout=timeout)
        self.verbose = verbose

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

        if self.verbose:
            print(f"Sending: {width}x{height}, max_iter={max_iter}, "
                  f"center=({center_re},{center_im}), step={step}, mode={mode}")
            print(f"Command: {len(payload)} bytes")
        self.ser.reset_input_buffer()
        self.ser.write(payload)
        self.ser.flush()

    def recv_legacy_response(self, header, width, height):
        total_pixels = width * height
        resp_rows = struct.unpack('<H', header[2:4])[0]
        resp_cols = struct.unpack('<H', header[4:6])[0]

        if self.verbose:
            print(f"Response header: {resp_rows}x{resp_cols}")
        if resp_rows != height or resp_cols != width:
            print(f"WARNING: Dims mismatch: {resp_rows}x{resp_cols} vs {height}x{width}")
            total_pixels = resp_rows * resp_cols

        # 2 bytes per pixel (uint16 LE)
        total_data_bytes = total_pixels * 2
        if self.verbose:
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
            if self.verbose and len(raw) % 20000 == 0:
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

        if self.verbose:
            print(f"Received {len(pixels)} pixels")
        return pixels

    def recv_tiled_response(self, header, width, height):
        resp_rows = struct.unpack('<H', header[2:4])[0]
        resp_cols = struct.unpack('<H', header[4:6])[0]

        if self.verbose:
            print(f"Tiled response header: {resp_rows}x{resp_cols}")
        if resp_rows != height or resp_cols != width:
            print(f"WARNING: Dims mismatch: {resp_rows}x{resp_cols} vs {height}x{width}")

        total_pixels = resp_rows * resp_cols
        pixels = [0] * total_pixels
        received_pixels = 0
        tile_count = 0

        while True:
            tile_magic = self.ser.read(2)
            if len(tile_magic) < 2:
                print(f"ERROR: Incomplete tile magic after {received_pixels}/{total_pixels} pixels")
                return None

            if tile_magic == b"TE":
                end_payload = self.ser.read(4)
                if len(end_payload) < 4:
                    print(f"ERROR: Incomplete end frame after {received_pixels}/{total_pixels} pixels")
                    return None
                end_rows = struct.unpack('<H', end_payload[0:2])[0]
                end_cols = struct.unpack('<H', end_payload[2:4])[0]
                if end_rows != resp_rows or end_cols != resp_cols:
                    print(f"ERROR: Bad end dims: {end_rows}x{end_cols}")
                    return None
                if received_pixels != total_pixels:
                    print(f"ERROR: End frame before full image: {received_pixels}/{total_pixels} pixels")
                    return None
                if self.verbose:
                    print(f"Received {received_pixels} pixels in {tile_count} tiles")
                return pixels

            if tile_magic != b"TD":
                print(f"ERROR: Bad tile magic: {tile_magic.hex()}")
                return None

            tile_rest = self.ser.read(8)
            if len(tile_rest) < 8:
                print(f"ERROR: Incomplete tile header after {received_pixels}/{total_pixels} pixels")
                return None

            tile_header = tile_magic + tile_rest

            row = struct.unpack('<H', tile_header[2:4])[0]
            col = struct.unpack('<H', tile_header[4:6])[0]
            tile_rows = struct.unpack('<H', tile_header[6:8])[0]
            tile_cols = struct.unpack('<H', tile_header[8:10])[0]
            tile_pixels = tile_rows * tile_cols
            payload_bytes = tile_pixels * 2

            if tile_rows == 0 or tile_cols == 0:
                print(f"ERROR: Empty tile at row={row}, col={col}")
                return None
            if row + tile_rows > resp_rows or col + tile_cols > resp_cols:
                print(f"ERROR: Tile out of bounds: row={row}, col={col}, size={tile_rows}x{tile_cols}")
                return None

            payload = self.ser.read(payload_bytes)
            if len(payload) < payload_bytes:
                print(f"ERROR: Incomplete tile payload at row={row}, col={col}: {len(payload)}/{payload_bytes}")
                return None

            ck_byte = self.ser.read(1)
            if len(ck_byte) < 1:
                print(f"ERROR: Missing tile checksum at row={row}, col={col}")
                return None

            checksum_calc = 0
            for b in payload:
                checksum_calc ^= b
            if checksum_calc != ck_byte[0]:
                print(f"ERROR: Tile checksum mismatch at row={row}, col={col}: calc=0x{checksum_calc:02X}, recv=0x{ck_byte[0]:02X}")
                print(f"  tile_header={tile_header.hex()}")
                print(f"  payload_first32={payload[:32].hex()}")
                print(f"  payload_last32={payload[-32:].hex() if payload else ''}")
                return None

            tile_values = struct.unpack(f'<{tile_pixels}H', payload)
            idx = 0
            for dy in range(tile_rows):
                base = (row + dy) * resp_cols + col
                pixels[base:base + tile_cols] = tile_values[idx:idx + tile_cols]
                received_pixels += tile_cols
                idx += tile_cols

            tile_count += 1
            if self.verbose and (tile_count % 64 == 0 or received_pixels == total_pixels):
                print(f"  Tile progress: {received_pixels}/{total_pixels} pixels ({tile_count} tiles)")

    def recv_response(self, width, height):
        header = self.ser.read(6)
        if len(header) < 6:
            print(f"ERROR: Incomplete header: {header.hex() if header else 'none'}")
            return None

        if header[0:2] == b"RK":
            return self.recv_legacy_response(header, width, height)
        if header[0:2] == b"RT":
            return self.recv_tiled_response(header, width, height)

        print(f"ERROR: Bad magic: {header[0]:#x} {header[1]:#x}, header={header.hex()}")
        return None


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


def request_image(fpga, center_re, center_im, step, max_iter, width, height, mode):
    fpga.send_command(center_re, center_im, step, max_iter, width, height, mode=mode)
    return fpga.recv_response(width, height)


def drain_serial_until_quiet(fpga, quiet_seconds=0.25, max_seconds=3.0):
    old_timeout = fpga.ser.timeout
    fpga.ser.timeout = quiet_seconds
    drained = 0
    start = time.perf_counter()
    try:
        while time.perf_counter() - start < max_seconds:
            chunk = fpga.ser.read(4096)
            if not chunk:
                break
            drained += len(chunk)
    finally:
        fpga.ser.timeout = old_timeout
    if drained:
        print(f"  Drained {drained} stale bytes before retry")


def request_image_tiled(fpga, center_re, center_im, step, max_iter, width, height, mode,
                        tile_width, tile_height, retries):
    pixels = [0] * (width * height)
    full_half_w = (width - 1) >> 1
    full_half_h = (height - 1) >> 1
    tiles_x = (width + tile_width - 1) // tile_width
    tiles_y = (height + tile_height - 1) // tile_height
    tile_total = tiles_x * tiles_y
    tile_index = 0

    for y0 in range(0, height, tile_height):
        th = min(tile_height, height - y0)
        for x0 in range(0, width, tile_width):
            tw = min(tile_width, width - x0)
            tile_index += 1
            tile_half_w = (tw - 1) >> 1
            tile_half_h = (th - 1) >> 1
            tile_center_re = center_re + (x0 + tile_half_w - full_half_w) * step
            tile_center_im = center_im + (full_half_h - (y0 + tile_half_h)) * step

            tile_pixels = None
            for attempt in range(1, retries + 2):
                if fpga.verbose or attempt > 1:
                    print(f"Tile {tile_index}/{tile_total}: x={x0}, y={y0}, size={tw}x{th}, attempt={attempt}")
                elif tile_index == 1 or tile_index == tile_total or tile_index % 16 == 0:
                    print(f"Tile progress: {tile_index}/{tile_total}")
                request_t0 = time.perf_counter()
                tile_pixels = request_image(fpga, tile_center_re, tile_center_im, step,
                                            max_iter, tw, th, mode)
                if tile_pixels is not None:
                    if fpga.verbose:
                        print(f"  Tile elapsed: {time.perf_counter() - request_t0:.3f}s")
                    break
                print("  Tile receive failed")
                drain_serial_until_quiet(fpga)
                fpga.ser.reset_input_buffer()

            if tile_pixels is None:
                return None

            for dy in range(th):
                src = dy * tw
                dst = (y0 + dy) * width + x0
                pixels[dst:dst + tw] = tile_pixels[src:src + tw]

    return pixels


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
    parser.add_argument("--tile-width", type=int, default=0,
                        help="Host-driven request tile width. 0 disables host tiling.")
    parser.add_argument("--tile-height", type=int, default=0,
                        help="Host-driven request tile height. 0 disables host tiling.")
    parser.add_argument("--tile-retries", type=int, default=2,
                        help="Retries per host-driven tile request")
    parser.add_argument("--quiet", action="store_true",
                        help="Reduce per-tile logging during large transfers")
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
    if args.tile_width > 0 or args.tile_height > 0:
        print(f" Host tiles: {args.tile_width}x{args.tile_height}, retries={args.tile_retries}")
    print("=" * 50)

    fpga = MandelbrotFPGA(port=args.port, timeout=args.timeout, verbose=not args.quiet)
    try:
        total_pixels = args.width * args.height
        t0 = time.perf_counter()
        if args.tile_width > 0 or args.tile_height > 0:
            if args.tile_width <= 0 or args.tile_height <= 0:
                print("ERROR: both --tile-width and --tile-height must be positive when host tiling is enabled")
                sys.exit(1)
            pixels = request_image_tiled(fpga, center_re, center_im, args.step,
                                         args.max_iter, args.width, args.height,
                                         args.mode, args.tile_width, args.tile_height,
                                         args.tile_retries)
        else:
            pixels = request_image(fpga, center_re, center_im, args.step,
                                   args.max_iter, args.width, args.height, args.mode)
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
