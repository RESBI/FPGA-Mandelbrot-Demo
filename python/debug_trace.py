import serial, struct, time

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
    frame = bytearray([0x55, 0xAA, 0x10, len(payload)]) + payload
    cs = 0
    for b in frame[2:]: cs = (cs + b) & 0xFF
    frame.append((-cs) & 0xFF)
    return bytes(frame)

def build_query_status():
    frame = bytearray([0x55, 0xAA, 0x02, 0x00])
    cs = 0
    for b in frame[2:]: cs = (cs + b) & 0xFF
    frame.append((-cs) & 0xFF)
    return bytes(frame)

def read_frame(ser, timeout=2):
    data = bytearray()
    t0 = time.time()
    while time.time() - t0 < timeout:
        b = ser.read(1)
        if b:
            data += b
            while len(data) >= 5:
                flen = data[3]
                needed = 4 + flen + 1
                if len(data) < needed: break
                if data[0] == 0x55 and data[1] == 0xAA:
                    s = data[2] + data[3]
                    for i in range(flen): s = (s + data[4+i]) & 0xFF
                    if (s + data[4+flen]) & 0xFF == 0:
                        return (data[2], data[4:4+flen])
                data = data[1:]
    return None

def parse_debug(payload):
    cmd_state = payload[0] & 0xF
    flags = payload[1]
    cb = (flags >> 7) & 1; cs_ = (flags >> 6) & 1; dd = (flags >> 5) & 1
    tdp = (flags >> 4) & 1; ap = (flags >> 3) & 1
    fra = (flags >> 2) & 1; fwa = (flags >> 1) & 1
    axi_s = payload[4]
    sn = {
        0:"RX_SYNC0",1:"RX_SYNC1",2:"RX_TYPE",3:"RX_LEN",4:"RX_PAY",5:"RX_CSUM",
        6:"TX_SYNC0",7:"TX_SYNC1",8:"TX_TYPE",9:"TX_LEN",10:"TX_PAY",11:"TX_CSUM"
    }
    an = {0:"IDLE",1:"GET",2:"PACK",3:"W",4:"B",5:"DONE"}
    print(f"  cmd={sn.get(cmd_state,'?')} busy={cb} started={cs_} ddr_done={dd} tdp={tdp} ack_pend={ap} fifo_rd={fra} fifo_wr={fwa} axi={an.get(axi_s,'?')} p_sent={payload[2]} p_total={payload[3]}")

def main():
    ser = serial.Serial(PORT, BAUD, timeout=0.1)
    ser.reset_input_buffer(); ser.reset_output_buffer()
    time.sleep(0.5)

    cre = int(round(-0.5 * 2**FX_FRAC))
    cim = 0
    stp = int(round(0.005 * 2**FX_FRAC))
    frame = build_compute_tile(-0.5, 0.0, 0.005, 256, 4, 4, 0x10000000, 0)

    print("Sending 4x4 COMPUTE_TILE...")
    ser.reset_input_buffer()
    ser.write(frame); ser.flush()

    # Read ACK
    ack = read_frame(ser, timeout=3)
    if ack:
        print(f"ACK: type=0x{ack[0]:02X} status={ack[1][0]}")

    # Poll debug status every 200ms for 5s
    for i in range(25):
        time.sleep(0.2)
        ser.reset_input_buffer()
        ser.write(build_query_status()); ser.flush()
        time.sleep(0.05)
        frame_resp = read_frame(ser, timeout=1)
        if frame_resp and frame_resp[0] == 0x90:
            print(f"[{(i+1)*0.2:.1f}s]", end="")
            parse_debug(frame_resp[1])
        elif frame_resp:
            print(f"[{(i+1)*0.2:.1f}s] type=0x{frame_resp[0]:02X}")
        else:
            print(f"[{(i+1)*0.2:.1f}s] no response")

    ser.close()

if __name__ == '__main__':
    main()
