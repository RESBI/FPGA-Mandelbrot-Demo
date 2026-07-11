import serial, struct, time, sys

PORT = 'COM6'
BAUD = 12000000
FX_FRAC = 55

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
    frame = bytearray()
    frame.append(0x55)
    frame.append(0xAA)
    frame.append(0x10)
    frame.append(len(payload))
    frame += payload
    checksum = 0
    for b in frame[2:]:
        checksum = (checksum + b) & 0xFF
    frame.append((-checksum) & 0xFF)
    return bytes(frame)

def build_enter_download():
    frame = bytearray([0x55, 0xAA, 0x11, 0x00])
    checksum = 0
    for b in frame[2:]:
        checksum = (checksum + b) & 0xFF
    frame.append((-checksum) & 0xFF)
    return bytes(frame)

def parse_frame(data):
    if len(data) < 5:
        return None
    if data[0] != 0x55 or data[1] != 0xAA:
        return None
    ftype = data[2]
    flen = data[3]
    if len(data) < 4 + flen + 1:
        return None
    payload = data[4:4+flen]
    checksum = data[4+flen]
    s = ftype + flen
    for b in payload:
        s = (s + b) & 0xFF
    if (s + checksum) & 0xFF != 0:
        return None
    return (ftype, payload)

def read_frame(ser, timeout=10):
    data = bytearray()
    t0 = time.time()
    while time.time() - t0 < timeout:
        b = ser.read(1)
        if b:
            data += b
            if len(data) >= 5:
                flen = data[3]
                needed = 4 + flen + 1
                if len(data) >= needed:
                    frame = parse_frame(data[:needed])
                    if frame:
                        return frame
                    data = data[1:]
    return None

def main():
    ser = serial.Serial(PORT, BAUD, timeout=0.1)
    ser.reset_input_buffer()
    ser.reset_output_buffer()
    time.sleep(0.1)

    cre, cim = -0.5, 0.0
    step = 0.005
    max_iter = 256
    rows, cols = 4, 4
    ddr_base = 0x10000000
    tile_id = 0

    print(f"Sending COMPUTE_TILE {cols}x{rows} center=({cre},{cim}) step={step} max_iter={max_iter} ddr_base=0x{ddr_base:X}")
    frame = build_compute_tile(cre, cim, step, max_iter, rows, cols, ddr_base, tile_id)
    ser.write(frame)
    ser.flush()

    print("Waiting for ACK...")
    ack = read_frame(ser, timeout=5)
    if ack:
        ftype, payload = ack
        print(f"  ACK: type=0x{ftype:02X} status={payload[0] if payload else 'N/A'}")
    else:
        print("  ACK timeout!")
        ser.close()
        return

    print("Waiting for TILE_DONE...")
    done = read_frame(ser, timeout=30)
    if done:
        ftype, payload = done
        checksum = struct.unpack('<H', payload[:2])[0] if len(payload) >= 2 else 0
        print(f"  TILE_DONE: type=0x{ftype:02X} checksum=0x{checksum:04X}")
    else:
        print("  TILE_DONE timeout!")

    print("Test complete.")
    ser.close()

if __name__ == '__main__':
    main()
