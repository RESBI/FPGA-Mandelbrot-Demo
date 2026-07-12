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
import colorsys
import math
from concurrent.futures import ThreadPoolExecutor

PORT = "COM6"
BAUD = 12000000
TIMEOUT = 180.0
DEFAULT_DYNAMIC_OWNER_DEPTH = 4096
DEFAULT_MAX_HOST_BYTES = 512 * 1024 * 1024
DEFAULT_HOST_TILE_HEIGHT = 120
DEFAULT_COMPUTE_TILE_MAX_WIDTH = 2048
DEFAULT_DDR_TILE_MAX_WIDTH = 1920
DEFAULT_TILE_READ_TIMEOUT = 5.0
TILE_PROGRESS_PACKET_INTERVAL = 1024
SOFT_RESET_COMMAND = b"RST!RST!"
QUIET_PROGRESS_BAR_WIDTH = 28
ASYNC_CHECKSUM_WORKERS = 4

# ============================================================
#  DDR Mode Constants
# ============================================================
FX_FRAC = 55
DDR_FRAME_SYNC0 = 0x55
DDR_FRAME_SYNC1 = 0xAA
DDR_TYPE_COMPUTE_TILE = 0x10
DDR_TYPE_ENTER_DOWNLOAD = 0x11
DDR_TYPE_QUERY_STATUS = 0x02
DDR_TYPE_ACK = 0x81
DDR_TYPE_TILE_DONE = 0x84
DDR_TYPE_DEBUG_STATUS = 0x90
DDR_DEFAULT_BASE = 0x10000000
DDR_SLOT_ALIGNMENT = 128
DDR_LOW_SAFE_END = 0x7FF00000


class LocalTileChecksumError(Exception):
    def __init__(self, pixels, failed_rects, valid_rects=None):
        super().__init__(f"{len(failed_rects)} local checksum tile(s) failed")
        self.pixels = pixels
        self.failed_rects = failed_rects
        self.valid_rects = valid_rects or []


def payload_xor(payload):
    checksum = 0
    for b in payload:
        checksum ^= b
    return checksum


def process_tiled_payload(payload, checksum_recv, row, col, tile_rows, tile_cols):
    checksum_calc = payload_xor(payload)
    if checksum_calc != checksum_recv:
        return {
            "ok": False,
            "row": row,
            "col": col,
            "tile_rows": tile_rows,
            "tile_cols": tile_cols,
            "checksum_calc": checksum_calc,
            "checksum_recv": checksum_recv,
            "payload_first32": payload[:32].hex(),
            "payload_last32": payload[-32:].hex() if payload else "",
        }
    return {
        "ok": True,
        "row": row,
        "col": col,
        "tile_rows": tile_rows,
        "tile_cols": tile_cols,
        "values": struct.unpack(f'<{tile_rows * tile_cols}H', payload),
    }


class PendingTiledResponse:
    def __init__(self, width, height, tile_futures, verbose=False, collect_local_failures=False):
        self.width = width
        self.height = height
        self.tile_futures = tile_futures
        self.verbose = verbose
        self.collect_local_failures = collect_local_failures

    def finalize(self):
        pixels = [0] * (self.width * self.height)
        failed_rects = []
        valid_rects = []
        received_pixels = 0
        for future in self.tile_futures:
            result = future.result()
            row = result["row"]
            col = result["col"]
            tile_rows = result["tile_rows"]
            tile_cols = result["tile_cols"]
            if not result["ok"]:
                failed_rects.append((col, row, tile_cols, tile_rows))
                received_pixels += tile_rows * tile_cols
                if self.verbose:
                    print(f"ERROR: Tile checksum mismatch at row={row}, col={col}: calc=0x{result['checksum_calc']:02X}, recv=0x{result['checksum_recv']:02X}")
                    print(f"  payload_first32={result['payload_first32']}")
                    print(f"  payload_last32={result['payload_last32']}")
                continue
            values = result["values"]
            valid_rects.append((col, row, tile_cols, tile_rows))
            idx = 0
            for dy in range(tile_rows):
                base = (row + dy) * self.width + col
                pixels[base:base + tile_cols] = values[idx:idx + tile_cols]
                received_pixels += tile_cols
                idx += tile_cols
        if failed_rects:
            if self.collect_local_failures:
                raise LocalTileChecksumError(pixels, failed_rects, valid_rects)
            return None
        if self.verbose:
            print(f"Finalized {received_pixels} pixels from {len(self.tile_futures)} async tile(s)")
        return pixels


def estimate_uart_seconds(width, height):
    # UART is 8N1, so every payload byte costs 10 serial bits.
    response_bytes = 6 + width * height * 2 + 1
    return response_bytes * 10.0 / BAUD


def configure_host_tiling(args):
    if args.full_frame:
        args.host_tiling = False
        return

    args.host_tiling = True
    if args.tile_width <= 0:
        args.tile_width = min(args.width, 65535)
    if args.tile_height <= 0:
        args.tile_height = min(args.height, DEFAULT_HOST_TILE_HEIGHT)
    if args.compute_tile_width <= 0:
        args.compute_tile_width = min(args.tile_width, DEFAULT_COMPUTE_TILE_MAX_WIDTH)
    if args.compute_tile_height <= 0:
        args.compute_tile_height = args.tile_height


def validate_request(args):
    pixels = args.width * args.height
    data_bytes = pixels * 2
    est_seconds = estimate_uart_seconds(args.width, args.height)

    if args.width <= 0 or args.height <= 0:
        print("ERROR: width and height must be positive")
        sys.exit(1)
    if args.host_tiling:
        if args.tile_width <= 0 or args.tile_height <= 0:
            print("ERROR: host tile width and height must be positive")
            sys.exit(1)
        if args.tile_width > 65535 or args.tile_height > 65535:
            print("ERROR: host tile width and height must fit the 16-bit hardware protocol")
            print(f"  tile={args.tile_width}x{args.tile_height}")
            sys.exit(1)
        if args.compute_tile_width <= 0 or args.compute_tile_height <= 0:
            print("ERROR: compute tile width and height must be positive")
            sys.exit(1)
        if args.compute_tile_width > args.tile_width or args.compute_tile_height > args.tile_height:
            print("ERROR: compute tile must not exceed the host tile")
            print(f"  host tile={args.tile_width}x{args.tile_height}, compute tile={args.compute_tile_width}x{args.compute_tile_height}")
            sys.exit(1)
        if args.compute_tile_width > 65535 or args.compute_tile_height > 65535:
            print("ERROR: compute tile width and height must fit the 16-bit hardware protocol")
            print(f"  compute tile={args.compute_tile_width}x{args.compute_tile_height}")
            sys.exit(1)
    elif args.width > 65535 or args.height > 65535:
        print("ERROR: full-frame width and height must fit the 16-bit hardware protocol")
        print("  Use host tiling instead of --full-frame for larger logical images.")
        sys.exit(1)
    if args.max_iter > 65535:
        print("ERROR: max_iter must be <= 65535")
        sys.exit(1)

    hardware_request_height = args.compute_tile_height if args.host_tiling else args.height
    if not args.force_large_frame and hardware_request_height > DEFAULT_DYNAMIC_OWNER_DEPTH:
        print("ERROR: requested height exceeds the current default dynamic scheduler limit")
        print(f"  hardware request height={hardware_request_height}, dynamic owner table depth={DEFAULT_DYNAMIC_OWNER_DEPTH}")
        print("  The current default bitstream records dynamic row ownership for 4096 rows per command.")
        print("  A taller single hardware request can stall when raster collection reaches an unrecorded row.")
        print("  Rebuild with a larger DYNAMIC_OWNER_DEPTH or use an appropriate static build.")
        print("  Use host tiling with a smaller --tile-height, or pass --force-large-frame only if the programmed bitstream supports this request.")
        sys.exit(1)

    if not args.force_large_frame and data_bytes > DEFAULT_MAX_HOST_BYTES:
        print("ERROR: response is too large for the default host receive path")
        print(f"  data bytes={data_bytes}, default limit={DEFAULT_MAX_HOST_BYTES}")
        print("  The host currently buffers the full response before rendering/verifying.")
        print("  Host tiling protects the FPGA transport, but this script still buffers the final image in memory.")
        print("  Use a smaller frame, implement streaming output, or pass --force-large-frame knowingly.")
        sys.exit(1)

    print(f"Estimated UART payload time at {BAUD} baud: {est_seconds:.1f}s")


def print_quiet_progress(done_compute, total_compute, host_index, host_total, current_task, final=False):
    total_compute = max(total_compute, 1)
    done_compute = min(done_compute, total_compute)
    filled = int(QUIET_PROGRESS_BAR_WIDTH * done_compute / total_compute)
    bar = "#" * filled + "-" * (QUIET_PROGRESS_BAR_WIDTH - filled)
    line = (f"\r[{bar}] ({done_compute} / {total_compute} compute tile) "
            f"({host_index} / {host_total} host tile) {current_task}")
    sys.stdout.write(line + " " * 8)
    if final:
        sys.stdout.write("\n")
    sys.stdout.flush()

# ============================================================
#  Color Palette
# ============================================================
PALETTE_CHOICES = ("classic", "fire", "ocean", "twilight", "grayscale")


def _clamp_u8(value):
    return max(0, min(255, int(value)))


def make_palette(n_colors=256, scheme="classic"):
    """Generate a color palette for Mandelbrot rendering."""
    palette = []
    denom = max(n_colors - 1, 1)
    for i in range(n_colors):
        if i == 0:
            palette.append((0, 0, 0))
        else:
            t = i / denom
            if scheme == "classic":
                r = int((i * 9) % 256)
                g = int((i * 13 + 80) % 256)
                b = int((i * 17 + 160) % 256)
            elif scheme == "fire":
                r = _clamp_u8(255 * min(1.0, t * 3.0))
                g = _clamp_u8(255 * max(0.0, min(1.0, (t - 0.20) * 2.0)))
                b = _clamp_u8(160 * max(0.0, min(1.0, (t - 0.72) * 3.6)))
            elif scheme == "ocean":
                r_f, g_f, b_f = colorsys.hsv_to_rgb(0.58 + 0.12 * t, 0.85, 0.30 + 0.70 * t)
                r, g, b = _clamp_u8(r_f * 255), _clamp_u8(g_f * 255), _clamp_u8(b_f * 255)
            elif scheme == "twilight":
                r_f, g_f, b_f = colorsys.hsv_to_rgb((0.78 + 0.34 * t) % 1.0, 0.70, 0.25 + 0.75 * t)
                r, g, b = _clamp_u8(r_f * 255), _clamp_u8(g_f * 255), _clamp_u8(b_f * 255)
            elif scheme == "grayscale":
                level = _clamp_u8(255 * (t ** 0.55))
                r, g, b = level, level, level
            else:
                raise ValueError(f"Unknown palette: {scheme}")
            palette.append((r, g, b))
    return palette


def render_image(pixels, width, height, max_iter, output_path, palette_scheme="classic"):
    """Render pixel data to PNG image. Pixels are 16-bit iteration counts."""
    try:
        from PIL import Image
    except ImportError:
        print("ERROR: Pillow not installed. Run: pip install pillow")
        sys.exit(1)

    # Build palette: map 16-bit values -> RGB
    # For values > palette size, wrap with periodic mapping
    pal_size = min(2048, max_iter + 1)
    palette = make_palette(pal_size, palette_scheme)
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
    print(f"Image saved to {output_path} (palette={palette_scheme})")


class PreviewWindow:
    def __init__(self, width, height, max_iter, palette_scheme="classic", max_size=512):
        try:
            import tkinter as tk
            from PIL import Image, ImageTk
        except ImportError:
            print("WARNING: Preview requires tkinter and pillow; continuing without preview")
            self.enabled = False
            return
        scale = min(max_size / max(width, 1), max_size / max(height, 1), 1.0)
        self.preview_w = max(1, int(width * scale))
        self.preview_h = max(1, int(height * scale))
        self.width = width
        self.height = height
        self.max_iter = max_iter
        self.palette = make_palette(min(2048, max_iter + 1), palette_scheme)
        self.palette_size = len(self.palette)
        self.Image = Image
        self.ImageTk = ImageTk
        self.root = tk.Tk()
        self.root.title("Mandelbrot FPGA Preview")
        self.image = Image.new("RGB", (self.preview_w, self.preview_h), (0, 0, 0))
        self.photo = ImageTk.PhotoImage(self.image)
        self.label = tk.Label(self.root, image=self.photo)
        self.label.pack()
        self.enabled = True
        self.refresh([0] * (width * height))

    def _color(self, value):
        if value >= self.max_iter:
            return (0, 0, 0)
        return self.palette[value % self.palette_size]

    def refresh(self, pixels):
        if not self.enabled:
            return
        data = []
        for py in range(self.preview_h):
            sy = min(self.height - 1, py * self.height // self.preview_h)
            row = sy * self.width
            for px in range(self.preview_w):
                sx = min(self.width - 1, px * self.width // self.preview_w)
                data.append(self._color(pixels[row + sx]))
        self.image.putdata(data)
        self.photo = self.ImageTk.PhotoImage(self.image)
        self.label.configure(image=self.photo)
        self.root.update_idletasks()
        self.root.update()

    def refresh_rects(self, pixels, rects):
        if not self.enabled or not rects:
            return
        for py in range(self.preview_h):
            sy = min(self.height - 1, py * self.height // self.preview_h)
            row = sy * self.width
            for px in range(self.preview_w):
                sx = min(self.width - 1, px * self.width // self.preview_w)
                for rx, ry, rw, rh in rects:
                    if rx <= sx < rx + rw and ry <= sy < ry + rh:
                        self.image.putpixel((px, py), self._color(pixels[row + sx]))
                        break
        self.photo = self.ImageTk.PhotoImage(self.image)
        self.label.configure(image=self.photo)
        self.root.update_idletasks()
        self.root.update()

    def close(self):
        if self.enabled:
            try:
                self.root.update_idletasks()
                self.root.update()
            except Exception:
                pass


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
        precision = 0 if mode in ('fp64', 'fx64') else 1
        payload = bytearray()
        payload.append(0x4D)
        payload.append(precision)

        if mode == 'fx64':
            F = 55
            fp_cre = struct.pack('<q', round(center_re * (2**F)))
            fp_cim = struct.pack('<q', round(center_im * (2**F)))
            fp_stp = struct.pack('<q', round(step * (2**F)))
        elif mode == 'fp64':
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

    def soft_reset(self, drain_before=True, drain_after=True):
        if drain_before:
            drain_serial_until_quiet(self, quiet_seconds=0.05, max_seconds=0.5)
        if self.verbose:
            print("Sending soft reset")
        self.ser.write(SOFT_RESET_COMMAND)
        self.ser.flush()
        time.sleep(0.02)
        self.ser.reset_input_buffer()
        if drain_after:
            drain_serial_until_quiet(self, quiet_seconds=0.05, max_seconds=0.5)

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

    def recv_tiled_response(self, header, width, height, collect_local_failures=False,
                            checksum_executor=None, async_finalize=False):
        resp_rows = struct.unpack('<H', header[2:4])[0]
        resp_cols = struct.unpack('<H', header[4:6])[0]

        if self.verbose:
            print(f"Tiled response header: {resp_rows}x{resp_cols}")
        if resp_rows != height or resp_cols != width:
            print(f"ERROR: Dims mismatch: {resp_rows}x{resp_cols} vs {height}x{width}")
            return None

        total_pixels = resp_rows * resp_cols
        received_pixels = 0
        tile_count = 0
        tile_futures = []
        expected_row = 0

        while True:
            deadline = time.perf_counter() + max(self.ser.timeout or TIMEOUT, 0.001)
            tile_magic = self._read_exact(2, deadline) if hasattr(self, '_read_exact') else self.ser.read(2)
            if tile_magic is None or len(tile_magic) < 2:
                print(f"ERROR: Incomplete tile magic after {received_pixels}/{total_pixels} pixels")
                return None

            if tile_magic == b"TE":
                end_payload = self._read_exact(4, deadline) if hasattr(self, '_read_exact') else self.ser.read(4)
                if end_payload is None or len(end_payload) < 4:
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
                if expected_row != resp_rows:
                    print(f"ERROR: End frame before full row coverage: {expected_row}/{resp_rows}")
                    return None
                if self.verbose:
                    print(f"Received {received_pixels} pixels in {tile_count} tiles")
                response = PendingTiledResponse(resp_cols, resp_rows, tile_futures,
                                               verbose=self.verbose,
                                               collect_local_failures=collect_local_failures)
                if async_finalize:
                    return response
                return response.finalize()

            if tile_magic != b"TD":
                print(f"ERROR: Bad tile magic: {tile_magic.hex()}")
                return None

            tile_rest = self._read_exact(8, deadline) if hasattr(self, '_read_exact') else self.ser.read(8)
            if tile_rest is None or len(tile_rest) < 8:
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
            if col != 0 or tile_cols != resp_cols or row != expected_row:
                print(f"ERROR: Unexpected tile geometry: row={row}, expected_row={expected_row}, "
                      f"col={col}, tile_cols={tile_cols}, frame_cols={resp_cols}")
                return None

            payload_timeout = max(self.ser.timeout or TIMEOUT,
                                  payload_bytes * 10.0 / BAUD + 1.0)
            payload_deadline = time.perf_counter() + payload_timeout
            payload = self._read_exact(payload_bytes, payload_deadline) if hasattr(self, '_read_exact') else self.ser.read(payload_bytes)
            if payload is None or len(payload) < payload_bytes:
                got = len(payload) if payload is not None else 0
                print(f"ERROR: Incomplete tile payload at row={row}, col={col}: {got}/{payload_bytes}")
                return None

            ck_byte = self._read_exact(1, payload_deadline) if hasattr(self, '_read_exact') else self.ser.read(1)
            if ck_byte is None or len(ck_byte) < 1:
                print(f"ERROR: Missing tile checksum at row={row}, col={col}")
                return None

            if checksum_executor is None:
                result = process_tiled_payload(payload, ck_byte[0], row, col, tile_rows, tile_cols)

                class CompletedFuture:
                    def __init__(self, value):
                        self.value = value

                    def result(self):
                        return self.value

                tile_futures.append(CompletedFuture(result))
            else:
                tile_futures.append(checksum_executor.submit(
                    process_tiled_payload, payload, ck_byte[0], row, col, tile_rows, tile_cols))
            received_pixels += tile_pixels
            expected_row += tile_rows

            tile_count += 1
            if self.verbose and (tile_count % TILE_PROGRESS_PACKET_INTERVAL == 0 or received_pixels == total_pixels):
                print(f"  Tile progress: {received_pixels}/{total_pixels} pixels ({tile_count} tiles)")

    def recv_response(self, width, height, collect_local_failures=False,
                      checksum_executor=None, async_finalize=False):
        if hasattr(self, '_read_exact'):
            deadline = time.perf_counter() + max(self.ser.timeout or TIMEOUT, 0.001)
            header = self._read_exact(6, deadline)
        else:
            header = self.ser.read(6)
        if header is None or len(header) < 6:
            got = header.hex() if header is not None else 'none'
            print(f"ERROR: Incomplete header: {got}")
            return None

        if header[0:2] == b"RK":
            return self.recv_legacy_response(header, width, height)
        if header[0:2] == b"RT":
            return self.recv_tiled_response(header, width, height,
                                            collect_local_failures=collect_local_failures,
                                            checksum_executor=checksum_executor,
                                            async_finalize=async_finalize)

        print(f"ERROR: Bad magic: {header[0]:#x} {header[1]:#x}, header={header.hex()}")
        return None


# ============================================================
#  DDR Mode Protocol and Communication
# ============================================================
def to_fx64(value):
    """Convert a float to Q8.55 fixed-point signed 64-bit integer."""
    return int(round(value * (2 ** FX_FRAC)))


def build_ddr_frame(frame_type, payload=b''):
    """Build a 55 AA TYPE LEN PAYLOAD CHECKSUM frame (two's-complement checksum)."""
    if len(payload) > 255:
        raise ValueError("DDR control payload must fit the 8-bit length field")
    frame = bytearray([DDR_FRAME_SYNC0, DDR_FRAME_SYNC1, frame_type, len(payload)])
    frame += payload
    checksum = 0
    for b in frame[2:]:
        checksum = (checksum + b) & 0xFF
    frame.append((-checksum) & 0xFF)
    return bytes(frame)


def parse_ddr_frame(data):
    """Parse a 55 AA TYPE LEN PAYLOAD CHECKSUM frame. Returns (ftype, payload) or None."""
    if len(data) < 5:
        return None
    if data[0] != DDR_FRAME_SYNC0 or data[1] != DDR_FRAME_SYNC1:
        return None
    ftype = data[2]
    flen = data[3]
    if len(data) < 4 + flen + 1:
        return None
    payload = data[4:4 + flen]
    checksum = data[4 + flen]
    s = (ftype + flen) & 0xFF
    for b in payload:
        s = (s + b) & 0xFF
    if (s + checksum) & 0xFF != 0:
        return None
    return (ftype, payload)


def build_compute_tile_payload(cre, cim, step, max_iter, rows, cols, ddr_base, tile_id):
    """Build COMPUTE_TILE payload (42 bytes): center_re(8) center_im(8) step(8) max_iter(2) rows(2) cols(2) ddr_base(8) tile_id(4)."""
    payload = bytearray()
    payload += struct.pack('<q', to_fx64(cre))
    payload += struct.pack('<q', to_fx64(cim))
    payload += struct.pack('<q', to_fx64(step))
    payload += struct.pack('<H', max_iter)
    payload += struct.pack('<H', rows)
    payload += struct.pack('<H', cols)
    payload += struct.pack('<Q', ddr_base)
    payload += struct.pack('<I', tile_id)
    return bytes(payload)


def build_compute_tile_payload_fx(cre_fx, cim_fx, step_fx, max_iter,
                                  rows, cols, ddr_base, tile_id):
    return struct.pack('<qqqHHHQI', cre_fx, cim_fx, step_fx, max_iter,
                       rows, cols, ddr_base, tile_id)


def align_up(value, alignment):
    return (value + alignment - 1) & ~(alignment - 1)


def pixel_xor16(pixels):
    checksum = 0
    for value in pixels:
        checksum ^= value
    return checksum


class MandelbrotDDR(MandelbrotFPGA):
    """DDR mode communicator: sends COMPUTE_TILE commands, receives ACK/TILE_DONE."""

    def read_frame(self, timeout=30):
        """Read one complete DDR frame from UART. Returns (ftype, payload) or None."""
        deadline = time.perf_counter() + timeout
        old_timeout = self.ser.timeout
        sync_state = 0
        try:
            self.ser.timeout = min(0.1, max(timeout, 0.001))
            while time.perf_counter() < deadline:
                byte = self.ser.read(1)
                if not byte:
                    continue
                value = byte[0]
                if sync_state == 0:
                    sync_state = 1 if value == DDR_FRAME_SYNC0 else 0
                    continue
                if value != DDR_FRAME_SYNC1:
                    sync_state = 1 if value == DDR_FRAME_SYNC0 else 0
                    continue

                header = self._read_exact(2, deadline)
                if header is None:
                    return None
                frame_type, frame_len = header
                tail = self._read_exact(frame_len + 1, deadline)
                if tail is None:
                    return None
                result = parse_ddr_frame(
                    bytes([DDR_FRAME_SYNC0, DDR_FRAME_SYNC1]) + header + tail)
                if result is not None:
                    return result
                sync_state = 0
        finally:
            self.ser.timeout = old_timeout
        return None

    def _read_exact(self, size, deadline):
        data = bytearray()
        while len(data) < size and time.perf_counter() < deadline:
            chunk = self.ser.read(size - len(data))
            if chunk:
                data += chunk
        return bytes(data) if len(data) == size else None

    def send_compute_tile(self, cre, cim, step, max_iter, rows, cols, ddr_base, tile_id):
        payload = build_compute_tile_payload(cre, cim, step, max_iter, rows, cols, ddr_base, tile_id)
        frame = build_ddr_frame(DDR_TYPE_COMPUTE_TILE, payload)
        self.ser.write(frame)
        self.ser.flush()
        if self.verbose:
            print(f"  COMPUTE_TILE: {cols}x{rows} max_iter={max_iter} "
                  f"ddr_base=0x{ddr_base:X} tile_id={tile_id}")

    def send_compute_tile_fx(self, cre_fx, cim_fx, step_fx, max_iter,
                             rows, cols, ddr_base, tile_id):
        payload = build_compute_tile_payload_fx(
            cre_fx, cim_fx, step_fx, max_iter, rows, cols, ddr_base, tile_id)
        frame = build_ddr_frame(DDR_TYPE_COMPUTE_TILE, payload)
        self.ser.write(frame)
        self.ser.flush()
        if self.verbose:
            print(f"  COMPUTE_TILE: {cols}x{rows} max_iter={max_iter} "
                  f"ddr_base=0x{ddr_base:X} tile_id={tile_id}")

    def send_enter_download(self, ddr_base, rows, cols):
        frame = build_ddr_frame(
            DDR_TYPE_ENTER_DOWNLOAD, struct.pack('<QHH', ddr_base, rows, cols))
        self.ser.write(frame)
        self.ser.flush()
        if self.verbose:
            print(f"  ENTER_DOWNLOAD: {cols}x{rows} ddr_base=0x{ddr_base:X}")

    def query_status(self):
        frame = build_ddr_frame(DDR_TYPE_QUERY_STATUS)
        self.ser.write(frame)
        self.ser.flush()
        return self.read_frame(timeout=5)

    def send_compute_tile_and_wait(self, cre, cim, step, max_iter, rows, cols,
                                   ddr_base, tile_id, timeout=120):
        """Send COMPUTE_TILE, wait for ACK then TILE_DONE. Returns (checksum, ack_status) or (None, -1)."""
        self.send_compute_tile(cre, cim, step, max_iter, rows, cols, ddr_base, tile_id)

        ack = self.read_frame(timeout=10)
        if not ack or ack[0] != DDR_TYPE_ACK or len(ack[1]) != 1:
            if self.verbose:
                print(f"  ERROR: ACK timeout or wrong type: {ack}")
            return None, -1
        ack_status = ack[1][0] if ack[1] else -1
        if ack_status != 0:
            if self.verbose:
                print(f"  ERROR: ACK status={ack_status}")
            return None, ack_status

        done = self.read_frame(timeout=timeout)
        if not done or done[0] != DDR_TYPE_TILE_DONE or len(done[1]) != 4:
            if self.verbose:
                print(f"  ERROR: TILE_DONE timeout or wrong type: {done}")
            return None, -1

        checksum = struct.unpack('<H', done[1][:2])[0]
        done_status = done[1][2]
        if done_status != 0:
            if self.verbose:
                print(f"  ERROR: TILE_DONE status={done_status}")
            return None, done_status
        return checksum, 0

    def send_compute_tile_fx_and_wait(self, cre_fx, cim_fx, step_fx, max_iter,
                                      rows, cols, ddr_base, tile_id, timeout=None):
        self.send_compute_tile_fx(
            cre_fx, cim_fx, step_fx, max_iter, rows, cols, ddr_base, tile_id)
        ack = self.read_frame(timeout=10)
        if not ack or ack[0] != DDR_TYPE_ACK or len(ack[1]) != 1:
            return None, -1
        if ack[1][0] != 0:
            return None, ack[1][0]

        compute_timeout = timeout if timeout is not None else (self.ser.timeout or TIMEOUT)
        done = self.read_frame(timeout=compute_timeout)
        if not done or done[0] != DDR_TYPE_TILE_DONE or len(done[1]) != 4:
            return None, -1
        checksum = struct.unpack('<H', done[1][:2])[0]
        done_status = done[1][2]
        return (checksum, 0) if done_status == 0 else (None, done_status)

    def download_tile(self, ddr_base, rows, cols, expected_checksum,
                      retries=5, timeout=30):
        for attempt in range(1, retries + 2):
            self.send_enter_download(ddr_base, rows, cols)
            ack = self.read_frame(timeout=10)
            if not ack or ack[0] != DDR_TYPE_ACK or len(ack[1]) != 1:
                if attempt <= retries:
                    print(f"WARNING: Download ACK failed for 0x{ddr_base:X}, attempt={attempt}")
                    drain_serial_until_quiet(self, quiet_seconds=0.1, max_seconds=2.0)
                    time.sleep(0.05)
                    continue
                print(f"ERROR: Download ACK failed for 0x{ddr_base:X}")
                return None
            if ack[1][0] == 1 and attempt <= retries:
                time.sleep(0.05)
                continue
            if ack[1][0] != 0:
                print(f"ERROR: Download ACK status={ack[1][0]} for 0x{ddr_base:X}")
                return None

            old_timeout = self.ser.timeout
            self.ser.timeout = timeout
            checksum_failed = False
            try:
                try:
                    pixels = self.recv_response(
                        cols, rows, collect_local_failures=True)
                except LocalTileChecksumError:
                    pixels = None
                    checksum_failed = True
            finally:
                self.ser.timeout = old_timeout

            if pixels is not None:
                actual_checksum = pixel_xor16(pixels)
                if actual_checksum == expected_checksum:
                    return pixels
                print(f"WARNING: DDR tile checksum mismatch: expected=0x{expected_checksum:04X}, "
                      f"actual=0x{actual_checksum:04X}, attempt={attempt}")
            else:
                if checksum_failed:
                    print(f"WARNING: DDR UART tile checksum failed, attempt={attempt}")
                    continue
                print(f"WARNING: DDR UART framing failed, attempt={attempt}")
                remaining_stream_seconds = rows * cols * 2 * 10.0 / BAUD
                drain_serial_until_quiet(
                    self, quiet_seconds=0.1,
                    max_seconds=max(2.0, remaining_stream_seconds + 1.0))
                time.sleep(0.05)
                if attempt <= retries:
                    continue
                return None

        return None


# ============================================================
#  Software Reference
# ============================================================
def mandelbrot_software(center_re, center_im, step, max_iter, width, height, mode='fp64'):
    pixels = []
    half_w = (width - 1) >> 1
    half_h = (height - 1) >> 1
    re_start = center_re - half_w * step
    im_start = center_im + half_h * step
    if mode == 'fx64':
        F = 55
        center_re_fx = to_fx64(center_re)
        center_im_fx = to_fx64(center_im)
        step_fx = to_fx64(step)
        cre_start = center_re_fx - half_w * step_fx
        cim_start = center_im_fx + half_h * step_fx
        four = 4 << F
        for y in range(height):
            cim = cim_start - y * step_fx
            cre = cre_start
            for x in range(width):
                zr = 0; zi = 0
                it = 0
                while it < max_iter:
                    zr2 = (zr * zr) >> F
                    zi2 = (zi * zi) >> F
                    if zr2 + zi2 > four:
                        break
                    zrzi = (zr * zi) >> F
                    zi = (zrzi << 1) + cim
                    zr = zr2 - zi2 + cre
                    it += 1
                pixels.append(it)
                cre += step_fx
        return pixels
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


def request_image(fpga, center_re, center_im, step, max_iter, width, height, mode,
                  collect_local_failures=False, checksum_executor=None, async_finalize=False):
    fpga.send_command(center_re, center_im, step, max_iter, width, height, mode=mode)
    return fpga.recv_response(width, height, collect_local_failures=collect_local_failures,
                              checksum_executor=checksum_executor,
                              async_finalize=async_finalize)


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


def merge_rects(rects):
    if not rects:
        return []

    horizontal = []
    for x, y, w, h in sorted(rects, key=lambda r: (r[1], r[3], r[0])):
        if horizontal:
            px, py, pw, ph = horizontal[-1]
            if py == y and ph == h and px + pw == x:
                horizontal[-1] = (px, py, pw + w, ph)
                continue
        horizontal.append((x, y, w, h))

    merged = []
    for x, y, w, h in sorted(horizontal, key=lambda r: (r[0], r[2], r[1])):
        if merged:
            px, py, pw, ph = merged[-1]
            if px == x and pw == w and py + ph == y:
                merged[-1] = (px, py, pw, ph + h)
                continue
        merged.append((x, y, w, h))
    return sorted(merged, key=lambda r: (r[1], r[0]))


def copy_rect(dst_pixels, dst_width, x0, y0, src_pixels, src_width, rect_w, rect_h):
    for dy in range(rect_h):
        src = dy * src_width
        dst = (y0 + dy) * dst_width + x0
        dst_pixels[dst:dst + rect_w] = src_pixels[src:src + rect_w]


def copy_rect_region(dst_pixels, dst_width, dst_x, dst_y,
                     src_pixels, src_width, src_x, src_y, rect_w, rect_h):
    for dy in range(rect_h):
        src = (src_y + dy) * src_width + src_x
        dst = (dst_y + dy) * dst_width + dst_x
        dst_pixels[dst:dst + rect_w] = src_pixels[src:src + rect_w]


def calc_subtile_center(center_re, center_im, step, full_half_w, full_half_h, x0, y0, w, h):
    half_w = (w - 1) >> 1
    half_h = (h - 1) >> 1
    return (
        center_re + (x0 + half_w - full_half_w) * step,
        center_im + (full_half_h - (y0 + half_h)) * step,
    )


def request_image_tiled(fpga, center_re, center_im, step, max_iter, width, height, mode,
                        tile_width, tile_height, compute_tile_width, compute_tile_height,
                        retries, tile_read_timeout, soft_reset_on_retry, preview=None):
    pixels = [0] * (width * height)
    full_half_w = (width - 1) >> 1
    full_half_h = (height - 1) >> 1
    tiles_x = (width + tile_width - 1) // tile_width
    tiles_y = (height + tile_height - 1) // tile_height
    tile_total = tiles_x * tiles_y
    tile_index = 0
    failed_compute_tiles = []
    deferred_retry_tiles = []
    pending_finalized_tiles = []
    total_compute_tiles = 0
    for y_base in range(0, height, tile_height):
        host_h = min(tile_height, height - y_base)
        compute_tiles_y = (host_h + compute_tile_height - 1) // compute_tile_height
        for x_base in range(0, width, tile_width):
            host_w = min(tile_width, width - x_base)
            compute_tiles_x = (host_w + compute_tile_width - 1) // compute_tile_width
            total_compute_tiles += compute_tiles_x * compute_tiles_y
    completed_compute_tiles = 0
    def show_progress(current_task, final=False):
        if fpga.verbose:
            return
        print_quiet_progress(completed_compute_tiles, total_compute_tiles, tile_index, tile_total,
                             current_task, final=final)

    def finalize_pending(block=False):
        nonlocal pending_finalized_tiles
        still_pending = []
        for item in pending_finalized_tiles:
            future = item["future"]
            if not block and not future.done():
                still_pending.append(item)
                continue
            cx0, cy0, cw, ch = item["rect"]
            deferred_for_item = False
            copied_valid_only = False
            try:
                subtile_pixels = future.result()
            except LocalTileChecksumError as exc:
                subtile_pixels = exc.pixels
                deferred_for_item = True
                failed = [(cx0 + rx, cy0 + ry, rw, rh) for rx, ry, rw, rh in exc.failed_rects]
                for rx0, ry0, rw, rh in merge_rects(failed):
                    deferred_retry_tiles.append({
                        "host_tile": item["host_tile"],
                        "compute_tile": item["compute_tile"],
                        "compute_rect": (cx0, cy0, cw, ch),
                        "rect": (rx0, ry0, rw, rh),
                    })
                if not fpga.verbose:
                    sys.stdout.write("\n")
                    sys.stdout.flush()
                print(f"    Deferred {len(failed)} checksum retry tile(s): host_tile={item['host_tile']}, compute_tile={item['compute_tile']}, x={cx0}, y={cy0}, size={cw}x{ch}")
                valid_abs_rects = []
                for vx, vy, vw, vh in exc.valid_rects:
                    copy_rect_region(pixels, width, cx0 + vx, cy0 + vy,
                                     exc.pixels, cw, vx, vy, vw, vh)
                    valid_abs_rects.append((cx0 + vx, cy0 + vy, vw, vh))
                if preview is not None:
                    preview.refresh_rects(pixels, valid_abs_rects)
                copied_valid_only = True
            if subtile_pixels is None:
                failed_compute_tiles.append({
                    "host_tile": item["host_tile"],
                    "compute_tile": item["compute_tile"],
                    "x": cx0,
                    "y": cy0,
                    "width": cw,
                    "height": ch,
                    "attempt": 1,
                    "retry_tiles": 1,
                })
                continue
            if copied_valid_only:
                continue
            copy_rect(pixels, width, cx0, cy0, subtile_pixels, cw, cw, ch)
            if preview is not None:
                preview.refresh_rects(pixels, [(cx0, cy0, cw, ch)])
        pending_finalized_tiles = still_pending

    checksum_executor = ThreadPoolExecutor(max_workers=ASYNC_CHECKSUM_WORKERS)
    finalize_executor = ThreadPoolExecutor(max_workers=2)
    try:
        for y0 in range(0, height, tile_height):
            th = min(tile_height, height - y0)
            for x0 in range(0, width, tile_width):
                tw = min(tile_width, width - x0)
                tile_index += 1
                compute_tiles_x = (tw + compute_tile_width - 1) // compute_tile_width
                compute_tiles_y = (th + compute_tile_height - 1) // compute_tile_height
                compute_total = compute_tiles_x * compute_tiles_y
                compute_index = 0

                if fpga.verbose:
                    print(f"Tile {tile_index}/{tile_total}: x={x0}, y={y0}, size={tw}x{th}, compute_tiles={compute_total}")
                else:
                    show_progress(f"host x={x0}, y={y0}, size={tw}x{th}")

                for cy0 in range(y0, y0 + th, compute_tile_height):
                    ch = min(compute_tile_height, y0 + th - cy0)
                    for cx0 in range(x0, x0 + tw, compute_tile_width):
                        cw = min(compute_tile_width, x0 + tw - cx0)
                        compute_index += 1
                        subtile_center_re, subtile_center_im = calc_subtile_center(
                            center_re, center_im, step, full_half_w, full_half_h, cx0, cy0, cw, ch)

                        response_enqueued = False
                        pending_rects = [(cx0, cy0, cw, ch)]
                        finalize_pending(block=False)
                        show_progress(f"compute x={cx0}, y={cy0}, size={cw}x{ch}")

                        for attempt in range(1, retries + 2):
                            retry_rects = merge_rects(pending_rects)
                            subtile_pixels = None
                            next_failed = []
                            local_checksum_retry = False
                            if fpga.verbose or attempt > 1:
                                if not fpga.verbose:
                                    sys.stdout.write("\n")
                                    sys.stdout.flush()
                                retry_desc = f"{len(retry_rects)} retry tile(s)" if attempt > 1 else "full compute tile"
                                print(f"  Compute tile {compute_index}/{compute_total}: x={cx0}, y={cy0}, size={cw}x{ch}, attempt={attempt}, {retry_desc}")
                            elif not fpga.verbose:
                                show_progress(f"compute x={cx0}, y={cy0}, size={cw}x{ch}")

                            old_timeout = fpga.ser.timeout
                            fpga.ser.timeout = tile_read_timeout
                            try:
                                if attempt == 1:
                                    response = request_image(
                                        fpga, subtile_center_re, subtile_center_im, step, max_iter, cw, ch, mode,
                                        collect_local_failures=True,
                                        checksum_executor=checksum_executor,
                                        async_finalize=True)
                                    if response is not None:
                                        if hasattr(response, "finalize"):
                                            pending_finalized_tiles.append({
                                                "future": finalize_executor.submit(response.finalize),
                                                "host_tile": tile_index,
                                                "compute_tile": compute_index,
                                                "rect": (cx0, cy0, cw, ch),
                                            })
                                            response_enqueued = True
                                        else:
                                            copy_rect(pixels, width, cx0, cy0, response, cw, cw, ch)
                                            if preview is not None:
                                                preview.refresh(pixels)
                                else:
                                    for rx0, ry0, rw, rh in retry_rects:
                                        rect_center_re, rect_center_im = calc_subtile_center(
                                            center_re, center_im, step, full_half_w, full_half_h, rx0, ry0, rw, rh)
                                        try:
                                            rect_pixels = request_image(
                                                fpga, rect_center_re, rect_center_im, step, max_iter, rw, rh, mode,
                                                collect_local_failures=True,
                                                checksum_executor=checksum_executor)
                                        except LocalTileChecksumError as exc:
                                            rect_pixels = exc.pixels
                                            next_failed.extend((rx0 + fx, ry0 + fy, fw, fh) for fx, fy, fw, fh in exc.failed_rects)
                                            local_checksum_retry = True
                                        if rect_pixels is not None:
                                            if subtile_pixels is None:
                                                subtile_pixels = [0] * (cw * ch)
                                            copy_rect(subtile_pixels, cw, rx0 - cx0, ry0 - cy0, rect_pixels, rw, rw, rh)
                                        elif not next_failed:
                                            next_failed.append((rx0, ry0, rw, rh))
                            finally:
                                fpga.ser.timeout = old_timeout

                            if attempt == 1 and (response_enqueued or response is not None):
                                pending_rects = []
                                break
                            if attempt > 1 and subtile_pixels is not None and not next_failed:
                                copy_rect(pixels, width, cx0, cy0, subtile_pixels, cw, cw, ch)
                                pending_rects = []
                                if preview is not None:
                                    preview.refresh(pixels)
                                break

                            pending_rects = merge_rects(next_failed) if next_failed else [(cx0, cy0, cw, ch)]
                            failed_compute_tiles.append({
                                "host_tile": tile_index,
                                "compute_tile": compute_index,
                                "x": cx0,
                                "y": cy0,
                                "width": cw,
                                "height": ch,
                                "attempt": attempt,
                                "retry_tiles": len(pending_rects),
                            })
                            if not fpga.verbose:
                                sys.stdout.write("\n")
                                sys.stdout.flush()
                            print(f"    Compute tile receive failed: host_tile={tile_index}, compute_tile={compute_index}, x={cx0}, y={cy0}, size={cw}x{ch}, attempt={attempt}, retry_tiles={len(pending_rects)}")
                            if local_checksum_retry:
                                continue
                            drain_serial_until_quiet(fpga)
                            fpga.ser.reset_input_buffer()
                            if soft_reset_on_retry:
                                fpga.soft_reset(drain_before=False)

                        if (not response_enqueued and pending_rects):
                            print("ERROR: Failed compute tiles:")
                            for failure in failed_compute_tiles[-10:]:
                                print(f"  host_tile={failure['host_tile']}, compute_tile={failure['compute_tile']}, x={failure['x']}, y={failure['y']}, size={failure['width']}x{failure['height']}, attempt={failure['attempt']}")
                            return None

                        completed_compute_tiles += 1
                        if not fpga.verbose:
                            show_progress(f"rx done x={cx0}, y={cy0}, size={cw}x{ch}")

                if fpga.verbose:
                    print("  Host tile complete")
                finalize_pending(block=True)
    finally:
        finalize_executor.shutdown(wait=True)
        checksum_executor.shutdown(wait=True)

    deferred_failures = []
    if deferred_retry_tiles:
        deferred_rects = merge_rects([item["rect"] for item in deferred_retry_tiles])
        if not fpga.verbose:
            sys.stdout.write("\n")
            sys.stdout.flush()
        print(f"Deferred checksum retries: {len(deferred_retry_tiles)} tile(s), {len(deferred_rects)} merged request(s)")
        for retry_idx, (rx0, ry0, rw, rh) in enumerate(deferred_rects, 1):
            pending_rects = [(rx0, ry0, rw, rh)]
            rect_pixels = None
            for attempt in range(1, retries + 2):
                retry_rects = merge_rects(pending_rects)
                next_failed = []
                framing_failed = False
                print(f"  Deferred retry {retry_idx}/{len(deferred_rects)}: x={rx0}, y={ry0}, size={rw}x{rh}, attempt={attempt}, {len(retry_rects)} request(s)")
                old_timeout = fpga.ser.timeout
                fpga.ser.timeout = tile_read_timeout
                try:
                    for px0, py0, pw, ph in retry_rects:
                        part_center_re, part_center_im = calc_subtile_center(
                            center_re, center_im, step, full_half_w, full_half_h, px0, py0, pw, ph)
                        try:
                            part_pixels = request_image(fpga, part_center_re, part_center_im, step,
                                                        max_iter, pw, ph, mode,
                                                        collect_local_failures=True)
                            part_valid_rects = [(0, 0, pw, ph)]
                        except LocalTileChecksumError as exc:
                            part_pixels = exc.pixels
                            part_valid_rects = exc.valid_rects
                            next_failed.extend((px0 + fx, py0 + fy, fw, fh) for fx, fy, fw, fh in exc.failed_rects)
                        if part_pixels is not None:
                            refreshed = []
                            for vx, vy, vw, vh in part_valid_rects:
                                copy_rect_region(pixels, width, px0 + vx, py0 + vy,
                                                 part_pixels, pw, vx, vy, vw, vh)
                                refreshed.append((px0 + vx, py0 + vy, vw, vh))
                            if preview is not None:
                                preview.refresh_rects(pixels, refreshed)
                        elif not next_failed:
                            next_failed.append((px0, py0, pw, ph))
                            framing_failed = True
                            break
                finally:
                    fpga.ser.timeout = old_timeout
                if not next_failed:
                    rect_pixels = True
                    break
                pending_rects = merge_rects(next_failed)
                deferred_failures.extend({
                    "x": fx,
                    "y": fy,
                    "width": fw,
                    "height": fh,
                    "attempt": attempt,
                } for fx, fy, fw, fh in pending_rects)
                if framing_failed:
                    drain_serial_until_quiet(fpga)
                    fpga.ser.reset_input_buffer()
                    if soft_reset_on_retry:
                        fpga.soft_reset(drain_before=False)
            if rect_pixels is None:
                print("ERROR: Failed deferred checksum retry tiles:")
                for failure in deferred_failures[-10:]:
                    print(f"  x={failure['x']}, y={failure['y']}, size={failure['width']}x{failure['height']}, attempt={failure['attempt']}")
                return None

    if failed_compute_tiles:
        if not fpga.verbose:
            sys.stdout.write("\n")
            sys.stdout.flush()
        print(f"Recovered {len(failed_compute_tiles)} failed compute tile attempts")
    if deferred_retry_tiles:
        print(f"Recovered {len(deferred_retry_tiles)} deferred checksum retry tile(s)")
    elif not fpga.verbose:
        show_progress("complete", final=True)

    return pixels


def request_image_ddr(fpga, center_re, center_im, step, max_iter, width, height,
                      tile_width, tile_height, ddr_base, compute_only,
                      download_retries, download_timeout, compute_timeout,
                      preview=None):
    """Request an image in PL-PS DDR mode. Returns pixel list or None."""
    pixels = [0] * (width * height)
    full_half_w = (width - 1) >> 1
    full_half_h = (height - 1) >> 1
    center_re_fx = to_fx64(center_re)
    center_im_fx = to_fx64(center_im)
    step_fx = to_fx64(step)

    tiles_x = (width + tile_width - 1) // tile_width
    tiles_y = (height + tile_height - 1) // tile_height
    tile_total = tiles_x * tiles_y

    tile_id = 0
    tiles = []
    ddr_offset = 0

    completed_compute_tiles = 0

    def show_progress(current_task, final=False):
        if fpga.verbose:
            return
        print_quiet_progress(completed_compute_tiles, tile_total, tile_id, tile_total,
                             current_task, final=final)

    t0 = time.perf_counter()

    for y0 in range(0, height, tile_height):
        th = min(tile_height, height - y0)
        for x0 in range(0, width, tile_width):
            tw = min(tile_width, width - x0)
            tile_id += 1

            tile_half_w = (tw - 1) >> 1
            tile_half_h = (th - 1) >> 1
            subtile_center_re_fx = center_re_fx + (
                x0 + tile_half_w - full_half_w) * step_fx
            subtile_center_im_fx = center_im_fx + (
                full_half_h - (y0 + tile_half_h)) * step_fx

            tile_ddr_addr = ddr_base + ddr_offset
            tile_pixels = tw * th
            slot_bytes = align_up(tile_pixels * 2, DDR_SLOT_ALIGNMENT)

            if fpga.verbose:
                print(f"Tile {tile_id}/{tile_total}: x={x0}, y={y0}, size={tw}x{th}, "
                      f"ddr=0x{tile_ddr_addr:X}")
            else:
                show_progress(f"compute x={x0}, y={y0}, size={tw}x{th}")

            checksum, status = fpga.send_compute_tile_fx_and_wait(
                subtile_center_re_fx, subtile_center_im_fx, step_fx,
                max_iter, th, tw, tile_ddr_addr, tile_id - 1,
                timeout=compute_timeout)

            if checksum is None:
                print(f"ERROR: Tile {tile_id} compute failed (status={status})")
                return None

            if fpga.verbose:
                print(f"  TILE_DONE: checksum=0x{checksum:04X}")

            tiles.append({
                "x": x0,
                "y": y0,
                "width": tw,
                "height": th,
                "ddr_base": tile_ddr_addr,
                "slot_bytes": slot_bytes,
                "checksum": checksum,
            })
            ddr_offset += slot_bytes

            completed_compute_tiles += 1
            if not fpga.verbose:
                show_progress(f"done x={x0}, y={y0}")

    t_compute = time.perf_counter()
    compute_elapsed = t_compute - t0
    pps = (width * height) / compute_elapsed if compute_elapsed > 0 else 0.0
    print(f"FPGA elapsed: {compute_elapsed:.3f}s ({pps:.2f} pixels/s)")

    if compute_only:
        print("Skipping UART DDR download (--compute-only)")
        return pixels

    t_download0 = time.perf_counter()
    for download_index, tile in enumerate(tiles, 1):
        if fpga.verbose:
            print(f"Download {download_index}/{len(tiles)}: x={tile['x']}, y={tile['y']}, "
                  f"size={tile['width']}x{tile['height']}, ddr=0x{tile['ddr_base']:X}")
        tile_pixels = fpga.download_tile(
            tile['ddr_base'], tile['height'], tile['width'], tile['checksum'],
            retries=download_retries, timeout=download_timeout)
        if tile_pixels is None:
            print(f"ERROR: Failed to download DDR tile at 0x{tile['ddr_base']:X}")
            return None
        copy_rect(pixels, width, tile['x'], tile['y'], tile_pixels,
                  tile['width'], tile['width'], tile['height'])
        if preview is not None:
            preview.refresh_rects(pixels, [(
                tile['x'], tile['y'], tile['width'], tile['height'])])

    t_download1 = time.perf_counter()
    print(f"UART DDR download elapsed: {t_download1 - t_download0:.3f}s")

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
    parser.add_argument("--palette", type=str, choices=PALETTE_CHOICES, default="classic",
                        help="PNG/BMP color palette: classic, fire, ocean, twilight, or grayscale")
    parser.add_argument("--mode", type=str, choices=["ddr", "fx64"], default="ddr",
                        help="Mode: ddr (PL-PS DDR + fx64, default), fx64 (UART fixed-point)")
    parser.add_argument("--verify", action="store_true",
                        help="Also compute in software and compare")
    parser.add_argument("--port", type=str, default=PORT,
                        help=f"Serial port (default: {PORT})")
    parser.add_argument("--timeout", type=float, default=TIMEOUT,
                        help=f"Serial timeout in seconds (default: {TIMEOUT})")
    parser.add_argument("--force-large-frame", action="store_true",
                        help="Bypass host-side guards for very large frames; use only with a matching bitstream")
    parser.add_argument("--full-frame", action="store_true",
                        help="Disable default host-driven tiling and request one full frame in a single hardware command")
    parser.add_argument("--tile-width", type=int, default=0,
                        help="Host-driven request tile width. Default: full image width capped to 65535.")
    parser.add_argument("--tile-height", type=int, default=0,
                        help=f"Host-driven request tile height. Default: min(height, {DEFAULT_HOST_TILE_HEIGHT}).")
    parser.add_argument("--compute-tile-width", type=int, default=0,
                        help=f"Hardware compute tile width inside each host tile. Default: min(host tile width, {DEFAULT_COMPUTE_TILE_MAX_WIDTH}).")
    parser.add_argument("--compute-tile-height", type=int, default=0,
                        help="Hardware compute tile height inside each host tile. Default: host tile height.")
    parser.add_argument("--tile-retries", type=int, default=3,
                        help="Retries per hardware compute tile request")
    parser.add_argument("--tile-read-timeout", type=float, default=DEFAULT_TILE_READ_TIMEOUT,
                        help=f"Per-read serial timeout while receiving one host tile (default: {DEFAULT_TILE_READ_TIMEOUT}s)")
    parser.add_argument("--no-soft-reset-on-retry", action="store_true",
                        help="Do not send the UART soft reset command after a failed compute tile attempt")
    parser.add_argument("--soft-reset", action="store_true",
                        help="Send only the UART soft reset command, then exit")
    parser.add_argument("--quiet", action="store_true",
                        help="Reduce per-tile logging during large transfers")
    parser.add_argument("--preview", action="store_true",
                        help="Show a live thumbnail preview window while tiled rendering progresses")
    parser.add_argument("--preview-size", type=int, default=512,
                        help="Maximum preview window dimension in pixels (default: 512)")
    parser.add_argument("--ddr-base", type=lambda x: int(x, 0), default=DDR_DEFAULT_BASE,
                        help=f"DDR base address for pixel buffer (default: 0x{DDR_DEFAULT_BASE:X})")
    parser.add_argument("--compute-only", action="store_true",
                        help="Compute and write DDR only; skip UART download")
    parser.add_argument("--download-retries", type=int, default=5,
                        help="Retries per DDR tile UART download")
    parser.add_argument("--download-timeout", type=float, default=30.0,
                        help="UART timeout per DDR tile download")
    args = parser.parse_args()

    is_ddr_mode = (args.mode == 'ddr')

    if is_ddr_mode:
        args.host_tiling = True
        if args.full_frame:
            if args.width > DEFAULT_DDR_TILE_MAX_WIDTH and not args.force_large_frame:
                parser.error(f"--full-frame with width>{DEFAULT_DDR_TILE_MAX_WIDTH} requires --force-large-frame in DDR mode")
            args.tile_width = args.width
            args.tile_height = args.height
        elif args.tile_width <= 0:
            args.tile_width = min(args.width, DEFAULT_DDR_TILE_MAX_WIDTH)
        if args.tile_height <= 0:
            args.tile_height = min(args.height, DEFAULT_HOST_TILE_HEIGHT)
        args.compute_tile_width = args.tile_width
        args.compute_tile_height = args.tile_height
    else:
        configure_host_tiling(args)

    if args.soft_reset:
        fpga = MandelbrotFPGA(port=args.port, timeout=args.timeout, verbose=not args.quiet)
        try:
            fpga.soft_reset()
        finally:
            fpga.close()
        print("Soft reset sent")
        return

    validate_request(args)

    if is_ddr_mode:
        if args.ddr_base & (DDR_SLOT_ALIGNMENT - 1):
            parser.error(f"--ddr-base must be {DDR_SLOT_ALIGNMENT}-byte aligned")
        if args.tile_height > DEFAULT_DYNAMIC_OWNER_DEPTH and not args.force_large_frame:
            parser.error(f"DDR compute tile height must be <= {DEFAULT_DYNAMIC_OWNER_DEPTH}")
        if args.tile_width > 65535 or args.tile_height > 65535:
            parser.error("DDR compute tile width/height must fit uint16")
        if args.max_iter < 0:
            parser.error("--max-iter must be >= 0")
        if args.download_retries < 0:
            parser.error("--download-retries must be >= 0")
        if args.download_timeout <= 0:
            parser.error("--download-timeout must be > 0")
        if not all(math.isfinite(value) for value in (*args.center, args.step)):
            parser.error("--center and --step must be finite")
        q_min = -(1 << 63)
        q_max = (1 << 63) - 1
        center_re_fx = to_fx64(args.center[0])
        center_im_fx = to_fx64(args.center[1])
        step_fx = to_fx64(args.step)
        if not all(q_min <= value <= q_max for value in (
                center_re_fx, center_im_fx, step_fx)):
            parser.error("center/step do not fit signed Q8.55")
        half_w = (args.width - 1) >> 1
        half_h = (args.height - 1) >> 1
        extrema = (
            center_re_fx - half_w * step_fx,
            center_re_fx + (args.width - 1 - half_w) * step_fx,
            center_im_fx + half_h * step_fx,
            center_im_fx - (args.height - 1 - half_h) * step_fx,
        )
        if not all(q_min <= value <= q_max for value in extrema):
            parser.error("image coordinate extent does not fit signed Q8.55")
        total_slots = 0
        for y0 in range(0, args.height, args.tile_height):
            th = min(args.tile_height, args.height - y0)
            for x0 in range(0, args.width, args.tile_width):
                tw = min(args.tile_width, args.width - x0)
                total_slots += align_up(tw * th * 2, DDR_SLOT_ALIGNMENT)
        if args.ddr_base < 0 or args.ddr_base >= (1 << 64):
            parser.error("--ddr-base must fit uint64")
        if args.ddr_base + total_slots > DDR_LOW_SAFE_END:
            parser.error("DDR allocation reaches the PS-reserved top of the low DDR window")

    center_re, center_im = args.center
    print("=" * 50)
    print(" Mandelbrot FPGA Accelerator")
    if is_ddr_mode:
        print(f" Mode: DDR (fx64, PL-PS DDR)")
        print(f" DDR base: 0x{args.ddr_base:X}")
        print(f" UART download: {'disabled' if args.compute_only else 'enabled'}")
    else:
        print(f" Mode: {args.mode.upper()}")
    print(f" Center: ({center_re}, {center_im})")
    print(f" Step: {args.step}")
    print(f" Max iterations: {args.max_iter}")
    print(f" Image: {args.width}x{args.height}")
    if args.format != "txt":
        print(f" Palette: {args.palette}")
    if args.host_tiling:
        print(f" Compute tiles: {args.tile_width}x{args.tile_height}")
        if not is_ddr_mode:
            print(f" Retries: {args.tile_retries}, read_timeout={args.tile_read_timeout}s")
            print(f" Soft reset on retry: {not args.no_soft_reset_on_retry}")
        print(f" Preview: {'enabled' if args.preview else 'disabled'}")
    else:
        print(" Host tiles: disabled (--full-frame)")
    print("=" * 50)

    preview = None
    fpga = None
    try:
        total_pixels = args.width * args.height
        t0 = time.perf_counter()

        if is_ddr_mode:
            fpga = MandelbrotDDR(port=args.port, timeout=args.timeout, verbose=not args.quiet)
            if args.preview and args.format != "txt":
                preview = PreviewWindow(args.width, args.height, args.max_iter,
                                        args.palette, args.preview_size)
            pixels = request_image_ddr(fpga, center_re, center_im, args.step,
                                       args.max_iter, args.width, args.height,
                                       args.tile_width, args.tile_height,
                                       args.ddr_base, args.compute_only,
                                       args.download_retries, args.download_timeout,
                                       args.timeout,
                                       preview)
            t_recv = time.perf_counter()
            if pixels is None:
                print("ERROR: Failed to compute image")
                sys.exit(1)

            if args.compute_only:
                print("(No pixel data — readback skipped)")
            else:
                ext = os.path.splitext(args.output)[1].lower()
                if args.format == "txt" or ext == ".txt":
                    render_text(pixels, args.width, args.height, args.max_iter, args.output)
                else:
                    render_image(pixels, args.width, args.height, args.max_iter,
                                 args.output, args.palette)
                t_render = time.perf_counter()
                print(f"Render elapsed: {t_render - t_recv:.3f}s")

            if args.verify and not args.compute_only:
                print("\n--- Software Verification ---")
                t_sw0 = time.perf_counter()
                sw = mandelbrot_software(center_re, center_im, args.step,
                                         args.max_iter, args.width, args.height,
                                         mode='fx64')
                t_sw1 = time.perf_counter()
                compare_results(pixels, sw, args.width, args.height)
                print(f"Software elapsed: {t_sw1 - t_sw0:.3f}s")
            t_done = time.perf_counter()
            print(f"Total elapsed: {t_done - t0:.3f}s")
        else:
            fpga = MandelbrotFPGA(port=args.port, timeout=args.timeout, verbose=not args.quiet)
            if args.preview and args.host_tiling and args.format != "txt":
                preview = PreviewWindow(args.width, args.height, args.max_iter,
                                        args.palette, args.preview_size)
            if args.host_tiling:
                pixels = request_image_tiled(fpga, center_re, center_im, args.step,
                                             args.max_iter, args.width, args.height,
                                             args.mode, args.tile_width, args.tile_height,
                                             args.compute_tile_width, args.compute_tile_height,
                                             args.tile_retries, args.tile_read_timeout,
                                             not args.no_soft_reset_on_retry,
                                             preview)
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
                render_image(pixels, args.width, args.height, args.max_iter, args.output, args.palette)
            t_render = time.perf_counter()
            print(f"Render elapsed: {t_render - t_recv:.3f}s")

            if args.verify:
                print("\n--- Software Verification ---")
                t_sw0 = time.perf_counter()
                sw = mandelbrot_software(center_re, center_im, args.step,
                                         args.max_iter, args.width, args.height,
                                         mode=args.mode)
                t_sw1 = time.perf_counter()
                compare_results(pixels, sw, args.width, args.height)
                print(f"Software elapsed: {t_sw1 - t_sw0:.3f}s")
            t_done = time.perf_counter()
            print(f"Total elapsed: {t_done - t0:.3f}s")
    finally:
        if preview is not None:
            preview.close()
        if fpga is not None:
            fpga.close()


if __name__ == "__main__":
    main()
