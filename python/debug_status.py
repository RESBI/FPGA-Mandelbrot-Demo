import serial, struct, time

PORT = 'COM6'
BAUD = 12000000

def build_query_status():
    frame = bytearray([0x55, 0xAA, 0x02, 0x00])
    cs = 0
    for b in frame[2:]:
        cs = (cs + b) & 0xFF
    frame.append((-cs) & 0xFF)
    return bytes(frame)

def read_frame(ser, timeout=5):
    data = bytearray()
    t0 = time.time()
    while time.time() - t0 < timeout:
        b = ser.read(1)
        if b:
            data += b
            while len(data) >= 5:
                flen = data[3]
                needed = 4 + flen + 1
                if len(data) < needed:
                    break
                if data[0] == 0x55 and data[1] == 0xAA:
                    s = data[2] + data[3]
                    for i in range(flen):
                        s = (s + data[4+i]) & 0xFF
                    if (s + data[4+flen]) & 0xFF == 0:
                        return (data[2], data[4:4+flen])
                data = data[1:]
    return None

def parse_debug(payload):
    if len(payload) < 10:
        print(f"  Debug payload too short: {len(payload)}")
        return
    cmd_state = payload[0] & 0xF
    flags = payload[1]
    compute_busy = (flags >> 7) & 1
    compute_started = (flags >> 6) & 1
    ddr_done = (flags >> 5) & 1
    tile_done_pend = (flags >> 4) & 1
    ack_pend = (flags >> 3) & 1
    fifo_rd_avail = (flags >> 2) & 1
    fifo_wr_avail = (flags >> 1) & 1
    axi_p_sent = payload[2]
    axi_p_total = payload[3]
    axi_state = payload[4]
    cmd_state_raw = payload[5]
    checksum_lo = payload[6]
    checksum_hi = payload[7]
    ack_status = payload[8]

    state_names = {
        0: "RX_SYNC0", 1: "RX_SYNC1", 2: "RX_TYPE", 3: "RX_LEN",
        4: "RX_PAY", 5: "RX_CSUM", 6: "TX_SYNC0", 7: "TX_SYNC1",
        8: "TX_TYPE", 9: "TX_LEN", 10: "TX_PAY", 11: "TX_CSUM"
    }
    axi_state_names = {
        0: "IDLE", 1: "GET", 2: "PACK", 3: "W", 4: "B", 5: "DONE"
    }

    print(f"  cmd_state={cmd_state} ({state_names.get(cmd_state, '?')})")
    print(f"  compute_busy={compute_busy} compute_started={compute_started}")
    print(f"  ddr_done={ddr_done} tile_done_pending={tile_done_pend} ack_pending={ack_pend}")
    print(f"  fifo_rd_avail={fifo_rd_avail} fifo_wr_avail={fifo_wr_avail}")
    print(f"  axi_state={axi_state} ({axi_state_names.get(axi_state, '?')})")
    print(f"  axi_p_sent={axi_p_sent} axi_p_total={axi_p_total}")
    print(f"  checksum=0x{checksum_hi:02X}{checksum_lo:02X} ack_status={ack_status}")

def main():
    ser = serial.Serial(PORT, BAUD, timeout=0.1)
    ser.reset_input_buffer()
    ser.reset_output_buffer()
    time.sleep(0.5)

    print("=== Querying debug status ===")
    for i in range(5):
        ser.reset_input_buffer()
        query = build_query_status()
        ser.write(query)
        ser.flush()
        time.sleep(0.3)
        frame = read_frame(ser, timeout=2)
        if frame:
            ftype, payload = frame
            if ftype == 0x90:
                print(f"\n[Query {i}] DEBUG_STATUS:")
                parse_debug(payload)
            elif ftype == 0x81:
                print(f"\n[Query {i}] ACK: status={payload[0]}")
            else:
                print(f"\n[Query {i}] type=0x{ftype:02X} payload={payload.hex()}")
        else:
            print(f"\n[Query {i}] No response")
        time.sleep(0.5)

    ser.close()

if __name__ == '__main__':
    main()
