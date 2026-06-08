"""Test if HW/SW pixel center mismatch explains the results."""
import serial, struct, time

# SW reference using integer half_w (matching HW)
def mandelbrot_hw_centers(center_re, center_im, step, max_iter, width, height):
    pixels = []
    half_w = (width - 1) >> 1
    half_h = (height - 1) >> 1
    c_re_start = center_re - half_w * step
    c_im_start = center_im + half_h * step
    for row in range(height):
        c_im = c_im_start - row * step
        c_re = c_re_start
        for col in range(width):
            z_re, z_im = 0.0, 0.0
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

# SW reference using standard float centers
def mandelbrot_sw(center_re, center_im, step, max_iter, width, height):
    pixels = []
    im_start = center_im + ((height - 1) / 2.0) * step
    for y in range(height):
        c_im = im_start - y * step
        for x in range(width):
            c_re = center_re + (x - (width - 1) / 2.0) * step
            z_re, z_im = 0.0, 0.0
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

# Test single point that the HW gets WRONG
cr, ci, step, mi = 2.5, 0.0, 0.005, 5
hw_pix = mandelbrot_hw_centers(cr, ci, step, mi, 1, 1)
sw_pix = mandelbrot_sw(cr, ci, step, mi, 1, 1)

print(f"c={cr}: HW-centers={hw_pix[0]}, SW-centers={sw_pix[0]}")
print(f"  HW c_re = {cr - ((1-1)>>1)*step} = {cr}")
print(f"  SW c_re = {cr + (0 - (1-1)/2.0)*step} = {cr}")
print(f"  Both compute same point (1x1 image)")
print(f"  |c|^2 = {cr**2:.2f}, should escape at iter=1")

# Now compare both center methods on 160x120
print("\nComparing center methods on 160x120...")
hw = mandelbrot_hw_centers(-0.5, 0.0, 0.005, 256, 160, 120)
sw = mandelbrot_sw(-0.5, 0.0, 0.005, 256, 160, 120)
match = sum(1 for i in range(160*120) if hw[i] == sw[i])
print(f"HW-centers vs SW-centers: {match}/{160*120} = {100.0*match/(160*120):.2f}%")
