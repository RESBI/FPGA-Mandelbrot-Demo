#!/usr/bin/env python3
import argparse

from mandelbrot_host import mandelbrot_software
from test_points import send_point

import serial


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--port', default='COM4')
    parser.add_argument('--max-iter', type=int, default=128)
    parser.add_argument('--y', type=int, required=True)
    parser.add_argument('--x0', type=int, required=True)
    parser.add_argument('--x1', type=int, required=True)
    args = parser.parse_args()

    width = 160
    height = 120
    center_re = -0.5
    center_im = 0.0
    step = 0.005
    half_w = (width - 1) >> 1
    half_h = (height - 1) >> 1
    re_start = center_re - half_w * step
    ci = center_im + half_h * step - args.y * step

    with serial.Serial(args.port, 460800, timeout=5) as ser:
        for x in range(args.x0, args.x1 + 1):
            cr = re_start + x * step
            hw = send_point(ser, cr, ci, args.max_iter, step)
            sw = mandelbrot_software(cr, ci, step, args.max_iter, 1, 1)[0]
            print(f"x={x:3d} c=({cr:.17g},{ci:.17g}) HW={hw:3d} SW={sw:3d}")


if __name__ == '__main__':
    main()
