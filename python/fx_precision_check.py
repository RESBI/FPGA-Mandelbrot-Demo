import sys

def iter_fp(cre, cim, max_iter):
    zr, zi = 0.0, 0.0
    for i in range(max_iter):
        zr2 = zr*zr
        zi2 = zi*zi
        if zr2 + zi2 > 4.0:
            return i
        zi = 2.0*zr*zi + cim
        zr = zr2 - zi2 + cre
    return max_iter

def iter_fx(cre_i, cim_i, max_iter, F):
    mask = (1 << (1 + 4 + F)) - 1          # 1 sign + 4 int + F frac = 64-bit for F=59
    signbit = 1 << (4 + F)
    zr = 0
    zi = 0
    four = 4 << F
    for i in range(max_iter):
        zr2 = (zr * zr) >> F
        zi2 = (zi * zi) >> F
        mag = (zr2 + zi2)
        if mag > four:
            return i
        cross = (2 * ((zr * zi) >> F))
        zi = (cross + cim_i) & mask
        zr = (zr2 - zi2 + cre_i) & mask
        if zi & signbit:
            zi -= (1 << (5 + F))
        if zr & signbit:
            zr -= (1 << (5 + F))
    return max_iter

def to_fx(v, F):
    return int(round(v * (1 << F)))

center = (-1.25066, 0.02012)
step = 1e-9
max_iter = 8192
F = 59                                   # Q4.59 in 64-bit -> resolution 2^-59 ~ 1.7e-18

mismatch = 0
total = 0
maxdiff = 0
samples = []
import random
random.seed(7)
# sample a grid of points around the minibrot center
for dy in range(-6, 7):
    for dx in range(-6, 7):
        cre = center[0] + dx * step
        cim = center[1] + dy * step
        i_fp = iter_fp(cre, cim, max_iter)
        cre_i = to_fx(cre, F)
        cim_i = to_fx(cim, F)
        i_fx = iter_fx(cre_i, cim_i, max_iter, F)
        total += 1
        if i_fp != i_fx:
            mismatch += 1
            maxdiff = max(maxdiff, abs(i_fp - i_fx))
        samples.append((dx, dy, i_fp, i_fx))

print(f"F={F} (Q4.59, 64-bit), resolution 2^-F = {2.0**-F:.3e}")
print(f"FP64 mantissa resolution ~2^-52 = {2.0**-52:.3e}")
print(f"points={total}  mismatches={mismatch}  max_iter_diff={maxdiff}")
print("sample (dx,dy, iter_fp, iter_fx):")
for s in samples[:12]:
    print("  ", s)
