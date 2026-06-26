#!/usr/bin/env python3
import argparse
import struct

import serial

from mandelbrot_host import mandelbrot_software


def send_point(ser, cr, ci, max_iter, step):
    payload = bytearray([0x4D, 0x00])
    payload += struct.pack('<HHH', 1, 1, max_iter)
    payload += struct.pack('<d', cr)
    payload += struct.pack('<d', ci)
    payload += struct.pack('<d', step)
    checksum = 0
    for b in payload:
        checksum ^= b
    payload.append(checksum)
    ser.reset_input_buffer()
    ser.write(payload)
    ser.flush()
    resp = ser.read(9)
    if len(resp) < 8:
        raise TimeoutError(f"short response for ({cr},{ci}): {resp.hex()}")
    if resp[0:2] != b'RK':
        raise ValueError(f"bad header for ({cr},{ci}): {resp.hex()}")
    return struct.unpack('<H', resp[6:8])[0]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--port', default='COM6')
    parser.add_argument('--max-iter', type=int, default=256)
    parser.add_argument('--pixel', action='append', help='Image pixel as y,x for the 160x120 default view')
    args = parser.parse_args()

    width = 160
    height = 120
    center_re = -0.5
    center_im = 0.0
    step = 0.005
    half_w = (width - 1) >> 1
    half_h = (height - 1) >> 1
    points = [
        ('image[0,0]', center_re - half_w * step, center_im + half_h * step),
        ('image[0,79]', center_re, center_im + half_h * step),
        ('image[59,79]', center_re, center_im),
        ('image[119,0]', center_re - half_w * step, center_im - (height - 1 - half_h) * step),
        ('escape 2.5', 2.5, 0.0),
        ('boundary -0.75+0.1i', -0.75, 0.1),
    ]

    if args.pixel:
        points = []
        for spec in args.pixel:
            y_s, x_s = spec.split(',', 1)
            y = int(y_s)
            x = int(x_s)
            cr = center_re - half_w * step + x * step
            ci = center_im + half_h * step - y * step
            points.append((f'image[{y},{x}]', cr, ci))

    with serial.Serial(args.port, 576000, timeout=5) as ser:
        for name, cr, ci in points:
            hw = send_point(ser, cr, ci, args.max_iter, step)
            sw = mandelbrot_software(cr, ci, step, args.max_iter, 1, 1)[0]
            status = 'OK' if hw == sw else 'FAIL'
            print(f"{status} {name}: c=({cr:.17g},{ci:.17g}) HW={hw} SW={sw}")


if __name__ == '__main__':
    main()
