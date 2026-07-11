import serial, struct, time, sys

PORT = 'COM6'
BAUD = 12000000
FX_FRAC = 55

SCENES = [
    ("fast escape @128", (1.0, 1.0), "0.002", 128),
    ("standard @64",     (-0.5, 0.0), "0.002", 64),
    ("Seahorse @512",    (-0.743643887037151, 0.13182590420533), "5e-6", 512),
    ("deep tendrils @8192", (-0.77568377, 0.13646737), "1e-9", 8192),
    ("deep minibrot @8192", (-1.25066, 0.02012), "1e-9", 8192),
    ("deep Seahorse @1024", (-0.743643887037151, 0.13182590420533), "1e-8", 1024),
]

WIDTH = 1920
HEIGHT = 1080
TILE_W = 1920
TILE_H = 120
DDR_BASE = 0x10000000

def to_fx(v):
    return int(round(v * (2**FX_FRAC)))

def build_compute_tile(cre, cim, step, max_iter, rows, cols, ddr_base, tile_id):
    payload = bytearray()
    payload += struct.pack('<q', to_fx(cre))
    payload += struct.pack('<q', to_fx(cim))
    payload += struct.pack('<q', to_fx(step))
    payload += struct.pack('<H', max_iter)
    payload += struct.pack('<H', rows)
    payload += struct.pack('<H', cols)
    payload += struct.pack('<Q', ddr_base)
    payload += struct.pack('<I', tile_id)
    frame = bytearray([0x55, 0xAA, 0x10, len(payload)]) + payload
    checksum = 0
    for b in frame[2:]:
        checksum = (checksum + b) & 0xFF
    frame.append((-checksum) & 0xFF)
    return bytes(frame)

def read_frame(ser, timeout=30):
    data = bytearray()
    t0 = time.time()
    while time.time() - t0 < timeout:
        b = ser.read(1)
        if b:
            data += b
            if len(data) >= 5:
                flen = data[3]
                needed = 4 + flen + 1
                while len(data) >= needed:
                    if data[0] == 0x55 and data[1] == 0xAA:
                        s = data[2] + data[3]
                        for i in range(flen):
                            s = (s + data[4+i]) & 0xFF
                        if (s + data[4+flen]) & 0xFF == 0:
                            return (data[2], data[4:4+flen])
                    data = data[1:]
                    if len(data) < 5:
                        break
    return None

def calc_subtile_center(full_cx, full_cy, step, full_w, full_h, tx0, ty0, tw, th):
    fhw = (full_w - 1) >> 1
    fhh = (full_h - 1) >> 1
    thw = (tw - 1) >> 1
    thh = (th - 1) >> 1
    cx = full_cx + (tx0 + thw - fhw) * step
    cy = full_cy + (fhh - (ty0 + thh)) * step
    return cx, cy

def run_scene(ser, name, center, step, max_iter):
    step_f = float(step)
    tiles_x = (WIDTH + TILE_W - 1) // TILE_W
    tiles_y = (HEIGHT + TILE_H - 1) // TILE_H
    total_tiles = tiles_x * tiles_y
    total_pixels = WIDTH * HEIGHT

    print(f"\n=== {name} ({total_tiles} tiles, {total_pixels} pixels) ===")

    t_start = time.time()
    tile_idx = 0

    for ty in range(tiles_y):
        for tx in range(tiles_x):
            tx0 = tx * TILE_W
            ty0 = ty * TILE_H
            tw = min(TILE_W, WIDTH - tx0)
            th = min(TILE_H, HEIGHT - ty0)

            cx, cy = calc_subtile_center(center[0], center[1], step_f, WIDTH, HEIGHT, tx0, ty0, tw, th)
            ddr_addr = DDR_BASE + tile_idx * tw * th * 2

            frame = build_compute_tile(cx, cy, step_f, max_iter, th, tw, ddr_addr, tile_idx)
            ser.reset_input_buffer()
            ser.write(frame)
            ser.flush()

            ack = read_frame(ser, timeout=10)
            if not ack or ack[0] != 0x81:
                print(f"  tile {tile_idx}: ACK failed!")
                return None

            done = read_frame(ser, timeout=120)
            if not done or done[0] != 0x84:
                print(f"  tile {tile_idx}: TILE_DONE failed!")
                return None

            tile_idx += 1

    t_end = time.time()
    elapsed = t_end - t_start
    pps = total_pixels / elapsed
    print(f"  FPGA time: {elapsed:.3f}s ({pps:.0f} pps)")
    return elapsed, pps

def main():
    ser = serial.Serial(PORT, BAUD, timeout=0.1)
    ser.reset_input_buffer()
    ser.reset_output_buffer()
    time.sleep(0.1)

    print(f"PL-PS DDR Benchmark: {WIDTH}x{HEIGHT}, tile {TILE_W}x{TILE_H}")
    print(f"Port: {PORT}, Baud: {BAUD}")

    results = []
    for name, center, step, max_iter in SCENES:
        r = run_scene(ser, name, center, step, max_iter)
        if r:
            results.append((name, r[0], r[1]))

    print("\n\n=== Summary ===")
    print(f"{'Scene':28s} {'Time':>8s} {'pps':>10s}")
    print("-" * 50)
    for name, t, pps in results:
        print(f"{name:28s} {t:7.3f}s {pps:10.0f}")

    ser.close()

if __name__ == '__main__':
    main()
