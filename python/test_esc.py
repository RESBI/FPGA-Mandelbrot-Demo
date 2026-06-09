import serial, struct, time

s = serial.Serial('COM4', 576000, timeout=5)

# Test points that should all escape at iter=1 (|c|^2 > 4)
tests = [(2.5, 0), (2.6, 0), (3.0, 0), (4.1, 0)]
for cr, ci in tests:
    for attempt in range(3):
        p = bytearray([0x4D, 0x00])
        p += struct.pack('<HHH', 1, 1, 5)
        p += struct.pack('<d', cr)
        p += struct.pack('<d', ci)
        p += struct.pack('<d', 0.005)
        ck = 0
        for b in p:
            ck ^= b
        p.append(ck)
        s.reset_input_buffer()
        s.write(p)
        s.flush()
        r = s.read(100)
        if len(r) >= 8:
            val = struct.unpack('<H', r[6:8])[0]
            ok = "OK" if val == 1 else "FAIL(exp=1)"
        else:
            val = -1
            ok = "TIMEOUT"
        print("%s c=(%s,%s) -> iter=%d" % (ok, cr, ci, val))
        if val == 1:
            break

s.close()
