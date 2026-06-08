#!/usr/bin/env python3
"""Randomized software-reference checks for the FPGA Mandelbrot host."""

import argparse
import os
import random
import sys

sys.path.insert(0, os.path.dirname(__file__))
from mandelbrot_host import mandelbrot_software


def independent_hw_center_ref(center_re, center_im, step, max_iter, width, height):
    pixels = []
    half_w = (width - 1) >> 1
    half_h = (height - 1) >> 1
    c_im = center_im + half_h * step
    for _row in range(height):
        c_re = center_re - half_w * step
        for _col in range(width):
            z_re = 0.0
            z_im = 0.0
            it = 0
            while it < max_iter:
                z_re_sq = z_re * z_re
                z_im_sq = z_im * z_im
                if z_re_sq + z_im_sq > 4.0:
                    break
                next_im = 2.0 * z_re * z_im + c_im
                next_re = z_re_sq - z_im_sq + c_re
                z_re = next_re
                z_im = next_im
                it += 1
            pixels.append(it)
            c_re += step
        c_im -= step
    return pixels


def standard_float_center_ref(center_re, center_im, step, max_iter, width, height):
    pixels = []
    im_start = center_im + ((height - 1) / 2.0) * step
    for y in range(height):
        c_im = im_start - y * step
        for x in range(width):
            c_re = center_re + (x - (width - 1) / 2.0) * step
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
    return pixels


def compare_case(case_idx, center_re, center_im, step, max_iter, width, height):
    host = mandelbrot_software(center_re, center_im, step, max_iter, width, height)
    ref = independent_hw_center_ref(center_re, center_im, step, max_iter, width, height)
    if host != ref:
        for idx, (h, r) in enumerate(zip(host, ref)):
            if h != r:
                y, x = divmod(idx, width)
                raise AssertionError(
                    f"case {case_idx}: mismatch at [{y},{x}], host={h}, ref={r}, "
                    f"center=({center_re},{center_im}), step={step}, max_iter={max_iter}, "
                    f"size={width}x{height}"
                )

    std = standard_float_center_ref(center_re, center_im, step, max_iter, width, height)
    std_matches = sum(1 for a, b in zip(ref, std) if a == b)
    return std_matches, len(ref)


def main():
    parser = argparse.ArgumentParser(description="Randomized host software-reference tests")
    parser.add_argument("--cases", type=int, default=100)
    parser.add_argument("--seed", type=int, default=12345)
    args = parser.parse_args()

    rng = random.Random(args.seed)
    std_match_total = 0
    pixel_total = 0

    fixed_cases = [
        (-0.5, 0.0, 0.005, 64, 1, 1),
        (2.5, 0.0, 0.005, 8, 1, 1),
        (0.0, 0.0, 0.005, 8, 1, 1),
        (-0.75, 0.1, 0.005, 64, 5, 3),
        (-0.5, 0.0, 0.005, 128, 16, 12),
    ]

    for idx, case in enumerate(fixed_cases):
        matched, total = compare_case(idx, *case)
        std_match_total += matched
        pixel_total += total

    for i in range(args.cases):
        width = rng.randint(1, 24)
        height = rng.randint(1, 18)
        max_iter = rng.choice([1, 2, 3, 5, 8, 16, 32, 64, 96])
        step = rng.choice([0.001, 0.0025, 0.005, 0.01, 0.02, 0.05])
        center_re = rng.uniform(-2.0, 1.0)
        center_im = rng.uniform(-1.2, 1.2)
        matched, total = compare_case(len(fixed_cases) + i, center_re, center_im, step, max_iter, width, height)
        std_match_total += matched
        pixel_total += total

    pct = 100.0 * std_match_total / pixel_total if pixel_total else 100.0
    print(f"PASS: {len(fixed_cases) + args.cases} randomized host-reference cases")
    print(f"Standard floating-center agreement with RTL centers: {std_match_total}/{pixel_total} ({pct:.2f}%)")


if __name__ == "__main__":
    main()
