#!/usr/bin/env python3
"""Trace HW vs SW divergence for a specific Mandelbrot boundary pixel.

This script compares two FP64 computation models:
  - SW: native Python float (IEEE 754 round-to-nearest-even)
  - HW: truncation-rounding (emulates FPGA fp_mul/fp_add truncation)
"""

import struct


# ---------- FP64 truncation helpers ----------

def fp64_from_u64(u):
    return struct.unpack('<d', struct.pack('<Q', u))[0]

def fp64_to_u64(f):
    return struct.unpack('<Q', struct.pack('<d', f))[0]

def fp64_trunc_add(a, b):
    """FP64 add with truncation (no rounding)."""
    # This is hard to emulate exactly in Python. We approximate by computing
    # the exact sum in higher precision and truncating the mantissa.
    # Using Python's float (53-bit) and then introducing truncation bias.
    #
    # Real FPGA: align mantissas via right-shift (discard shifted-out bits),
    # add/subtract, normalize via left-shift, then discard 1-2 LSBs.
    #
    # Approximate emulation: compute with Python float, then truncate.
    # This is NOT exact but shows the systematic bias direction.
    exact = a + b
    u = fp64_to_u64(exact)
    # Truncate by clearing the rounding-related bits. This is an
    # approximation - real truncation happens during alignment/normalization.
    # For demonstration, we flip the rounding mode: round TOWARD ZERO
    # instead of to-nearest-even.
    import math
    # For negative numbers, truncation is different from floor/ceil.
    # We use a high-precision representation.
    return float(int(exact * (2**48)) / (2**48))  # crude truncation

def fp64_trunc_mul(a, b):
    """FP64 multiply with truncation (no rounding)."""
    import math
    exact = a * b
    return float(int(exact * (2**48)) / (2**48))  # crude truncation

def fp64_trunc_mul_emulate(a, b):
    """Emulate FPGA truncation more precisely.
    
    FPGA: 53-bit × 53-bit → 106-bit product. Select 52-bit mantissa
    from bits [104:53] or [103:52], discarding 53-54 LSBs.
    This is equivalent to computing the product in higher precision
    and chopping off the lower bits.
    """
    # Use integer arithmetic for exactness
    # Decompose into sign, exp, mantissa
    ua = fp64_to_u64(a)
    ub = fp64_to_u64(b)
    sa = (ua >> 63) & 1
    sb = (ub >> 63) & 1
    ea = (ua >> 52) & 0x7FF
    eb = (ub >> 52) & 0x7FF
    ma = ua & 0xFFFFFFFFFFFFF
    mb = ub & 0xFFFFFFFFFFFFF
    
    if ea == 0 or eb == 0:  # zero or subnormal - simplified
        return 0.0
    
    # Full mantissa with implicit 1
    ma_full = (1 << 52) | ma
    mb_full = (1 << 52) | mb
    
    # Exact product: 106 bits
    product_106 = ma_full * mb_full  # Python big int, exact
    
    sign = sa ^ sb
    exp_sum = ea + eb
    
    msb = (product_106 >> 105) & 1
    
    if msb:
        # Result in [2, 4). Extract bits [104:53] (52 bits)
        man = (product_106 >> 53) & 0xFFFFFFFFFFFFF
        exp_final = exp_sum - 1023 + 1
        # Truncate: discard bits [52:0], no rounding
    else:
        # Result in [1, 2). Extract bits [103:52] (52 bits)
        man = (product_106 >> 52) & 0xFFFFFFFFFFFFF
        exp_final = exp_sum - 1023
        # Truncate: discard bits [51:0], no rounding
    
    if exp_final <= 0:
        return 0.0
    if exp_final >= 2047:
        return 0.0
    
    result_u64 = (sign << 63) | (exp_final << 52) | man
    return fp64_from_u64(result_u64)


def fp64_trunc_add_emulate(a, b, negate_b=False):
    """Emulate FPGA fp_add truncation.
    
    Simplified: FPGA aligns by right-shift, adds/subs, normalizes,
    then truncates LSBs.
    """
    if negate_b:
        b = -b
    
    # Use the trunc-mul helper for the add (same truncation principle)
    # For proper emulation we'd need full integer alignment + add + normalize.
    # Use a simple approximation: compute in Python float, then round toward zero
    # at the IEEE 754 level.
    import math
    exact = a + b
    u = fp64_to_u64(exact)
    
    # For negative results, truncation (toward zero) is different from
    # floor or ceil. We need to handle this carefully.
    # Actually, the FPGA truncates the mantissa during normalization,
    # which for positive numbers rounds toward zero, and for negative
    # numbers also rounds toward zero (since the magnitude is truncated).
    # So the result is closer to zero than the exact value.
    
    # Approximate: use Python's decimal or just compute differently
    # For this analysis, we use a simpler approach: subtract 1 ULP
    # half the time to simulate truncation bias.
    # This is NOT a perfect emulation but illustrates the concept.
    return exact  # placeholder - actual FPGA behavior needs full simulation


def mandelbrot_hw_emulated(center_re, center_im, step, max_iter, width, height):
    """Mandelbrot using FPGA truncation-emulated FP64 operations."""
    half_w = (width - 1) >> 1
    half_h = (height - 1) >> 1
    re_start = center_re - half_w * step
    im_start = center_im + half_h * step
    
    pixels = []
    for y in range(height):
        c_im = im_start - y * step
        c_re_val = re_start
        for x in range(width):
            z_re = 0.0
            z_im = 0.0
            it = 0
            while it < max_iter:
                z_re_sq = fp64_trunc_mul_emulate(z_re, z_re)
                z_im_sq = fp64_trunc_mul_emulate(z_im, z_im)
                # Escape check: z_re² + z_im² > 4.0
                # Use exact float for the sum check (close enough for demo)
                if z_re_sq + z_im_sq > 4.0:
                    break
                z_re_z_im = fp64_trunc_mul_emulate(z_re, z_im)
                # z_new_im = 2*z_re*z_im + c_im
                two_zrzi = fp64_trunc_add_emulate(z_re_z_im, z_re_z_im)
                z_im_new = fp64_trunc_add_emulate(two_zrzi, c_im)
                # z_new_re = z_re_sq - z_im_sq + c_re
                diff_sq = fp64_trunc_add_emulate(z_re_sq, -z_im_sq)
                z_re_new = fp64_trunc_add_emulate(diff_sq, c_re_val)
                z_re = z_re_new
                z_im = z_im_new
                it += 1
            pixels.append(it)
            c_re_val += step
    return pixels


def trace_pixel(c_re, c_im, max_iter):
    """Trace one pixel iteration-by-iteration, comparing SW vs HW-emulated."""
    z_re_sw, z_im_sw = 0.0, 0.0
    z_re_hw, z_im_hw = 0.0, 0.0
    it_sw, it_hw = 0, 0
    first_div = None
    
    print(f"c = ({c_re:.18g}, {c_im:.18g})")
    print(f"{'it':>4s} {'z_re_sw':>22s} {'z_im_sw':>22s} {'z_re_hw':>22s} {'z_im_hw':>22s} {'|z|_sw':>12s} {'|z|_hw':>12s} {'diff':>10s}")
    
    for it in range(min(max_iter, 70)):
        # SW: native Python float (IEEE 754 RNE)
        z_re_sq_sw = z_re_sw * z_re_sw
        z_im_sq_sw = z_im_sw * z_im_sw
        mag_sw = (z_re_sq_sw + z_im_sq_sw) ** 0.5
        
        # HW: truncated operations
        z_re_sq_hw = fp64_trunc_mul_emulate(z_re_hw, z_re_hw)
        z_im_sq_hw = fp64_trunc_mul_emulate(z_im_hw, z_im_hw)
        sum_sq_hw = z_re_sq_hw + z_im_sq_hw  # approx for magnitude
        mag_hw = max(sum_sq_hw, 0) ** 0.5
        
        diff = abs(z_re_sw - z_re_hw) + abs(z_im_sw - z_im_hw)
        
        marker_sw = " <-- ESCAPE" if (z_re_sq_sw + z_im_sq_sw > 4.0) else ""
        marker_hw = ""  # simplified
        
        if diff > 1e-12 and first_div is None:
            first_div = it
        
        print(f" {it:3d}  {z_re_sw:22.16g} {z_im_sw:22.16g} {z_re_hw:22.16g} {z_im_hw:22.16g} {mag_sw:12.6g} {mag_hw:12.6g} {diff:10.2e}{marker_sw}")
        
        if z_re_sq_sw + z_im_sq_sw > 4.0:
            it_sw = it
        if sum_sq_hw > 4.0:
            it_hw = it
            
        # Both escaped
        if z_re_sq_sw + z_im_sq_sw > 4.0 and sum_sq_hw > 4.0:
            break
        # One escaped but not the other - continue the one that hasn't
        if z_re_sq_sw + z_im_sq_sw > 4.0:
            it_sw = it
            # Continue HW?
        if sum_sq_hw > 4.0:
            it_hw = it
        
        z_re_z_im_hw = fp64_trunc_mul_emulate(z_re_hw, z_im_hw)
        two_zrzi_hw = z_re_z_im_hw + z_re_z_im_hw
        z_im_hw_new = two_zrzi_hw + c_im
        diff_sq_hw = z_re_sq_hw - z_im_sq_hw
        z_re_hw_new = diff_sq_hw + c_re
        
        z_re_z_im_sw = z_re_sw * z_im_sw
        z_im_sw_new = 2.0 * z_re_z_im_sw + c_im
        z_re_sw_new = z_re_sq_sw - z_im_sq_sw + c_re
        
        z_re_sw, z_im_sw = z_re_sw_new, z_im_sw_new
        z_re_hw, z_im_hw = z_re_hw_new, z_im_hw_new
    
    if first_div:
        print(f"\nFirst visible divergence at iteration {first_div}")
    print(f"SW: it={it_sw}  HW: it={it_hw}")


if __name__ == "__main__":
    # Pixel [539, 210] from Standard benchmark
    # center=(-0.5, 0.0), step=0.002, width=1920, height=1080
    center_re, center_im = -0.5, 0.0
    step = 0.002
    width, height = 1920, 1080
    half_w = (width - 1) >> 1
    half_h = (height - 1) >> 1
    re_start = center_re - half_w * step
    im_start = center_im + half_h * step
    
    y, x = 539, 210
    c_im = im_start - y * step
    c_re = re_start + x * step
    
    trace_pixel(c_re, c_im, 128)
